#!/usr/bin/env bash
#
# Installe K3s dans la VM et branche l'hôte dessus.
#
# Trois choses distinctes, souvent confondues :
#   1. K3s (le cluster) tourne DANS la VM ;
#   2. kubectl (le client) tourne SUR L'HÔTE ;
#   3. le kubeconfig est le contrat entre les deux.
#
# Le kubeconfig contient des certificats d'authentification : il est écrit en
# 0600 et n'est jamais commité (.kube/ est dans .gitignore).
#
# Idempotent : ne réinstalle pas si la version attendue tourne déjà.

set -euo pipefail

export LIBVIRT_DEFAULT_URI=qemu:///system

# Canal « stable » de K3s au moment de l'écriture, épinglé volontairement :
# mettre à jour le cluster doit être une décision, pas un effet de bord d'un
# `make up` six mois plus tard.
K3S_VERSION="${K3S_VERSION:-v1.36.5+k3s1}"
VM_NAME="${VM_NAME:-gitops-lab-01}"

SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_ed25519}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build"
KNOWN_HOSTS="${BUILD_DIR}/known_hosts"
KUBECONFIG_FILE="${REPO_ROOT}/.kube/config"
KUBECTL_BIN="${KUBECTL_BIN:-${HOME}/.local/bin/kubectl}"

# K3s v1.36.5+k3s1 embarque Kubernetes v1.36.5. kubectl doit être de la même
# mineure : au-delà d'un écart de ±1, la compatibilité n'est pas garantie.
K8S_VERSION="${K3S_VERSION#v}"
K8S_VERSION="${K8S_VERSION%%+*}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merreur:\033[0m %s\n' "$*" >&2; exit 1; }

IP="$("${REPO_ROOT}/scripts/vm-ip.sh")" || die "VM introuvable (lancer 'make up' ?)"

vm_ssh() {
    ssh -i "${SSH_KEY}" -o UserKnownHostsFile="${KNOWN_HOSTS}" \
        -o StrictHostKeyChecking=accept-new -o BatchMode=yes \
        -o ConnectTimeout=10 "ubuntu@${IP}" "$@"
}

vm_ssh true 2>/dev/null || die "SSH injoignable sur ubuntu@${IP} (lancer 'make up' ?)"

# --- 1. K3s dans la VM ----------------------------------------------------
current_version=""
if vm_ssh 'systemctl is-active --quiet k3s' 2>/dev/null; then
    current_version="$(vm_ssh 'k3s --version' | awk '{print $3}')"
fi

if [[ "${current_version}" == "${K3S_VERSION}" ]]; then
    log "K3s ${K3S_VERSION} déjà en place"
else
    # --tls-san : le certificat de l'API doit contenir l'adresse que les
    # clients utilisent. Sans lui, kubectl depuis l'hôte échoue en x509.
    # C'est aussi le paramètre dont les agents auront besoin en Session 2.
    log "installation de K3s ${K3S_VERSION} (tls-san ${IP})"
    vm_ssh "curl -sfL https://get.k3s.io | sudo env \
        INSTALL_K3S_VERSION='${K3S_VERSION}' \
        INSTALL_K3S_EXEC='server --tls-san ${IP}' sh -"

    log "attente du nœud Ready"
    nodes=""
    for _ in $(seq 1 60); do
        nodes="$(vm_ssh 'sudo k3s kubectl get nodes --no-headers' 2>/dev/null || true)"
        [[ "${nodes}" == *" Ready "* ]] && break
        sleep 3
    done
    [[ "${nodes}" == *" Ready "* ]] || die "le nœud n'est pas devenu Ready"
fi

# --- 2. kubeconfig --------------------------------------------------------
# K3s écrit https://127.0.0.1:6443, valable seulement depuis la VM elle-même.
# Depuis l'hôte, on parle à son adresse sur le réseau NAT.
log "récupération du kubeconfig"
mkdir -p "$(dirname "${KUBECONFIG_FILE}")"
( umask 077; vm_ssh 'sudo cat /etc/rancher/k3s/k3s.yaml' > "${KUBECONFIG_FILE}" )
sed -i "s|https://127.0.0.1:6443|https://${IP}:6443|" "${KUBECONFIG_FILE}"
chmod 0600 "${KUBECONFIG_FILE}"

# Garde-fou : si l'adresse a changé depuis l'installation, le certificat ne la
# contient plus et kubectl échouera. Autant le dire tout de suite.
san="$(vm_ssh 'sudo openssl x509 -in /var/lib/rancher/k3s/server/tls/serving-kube-apiserver.crt -noout -ext subjectAltName' 2>/dev/null || true)"
if [[ "${san}" != *"IP Address:${IP}"* ]]; then
    warn "le certificat de l'API ne contient pas ${IP} (adresse changée depuis l'installation ?)"
    warn "correctif : make destroy && make up"
fi

# --- 3. kubectl sur l'hôte ------------------------------------------------
install_kubectl() {
    local base="https://dl.k8s.io/release/v${K8S_VERSION}/bin/linux/amd64"
    log "installation de kubectl v${K8S_VERSION} dans $(dirname "${KUBECTL_BIN}")"
    mkdir -p "$(dirname "${KUBECTL_BIN}")"
    curl -fsSL -o "${KUBECTL_BIN}.tmp" "${base}/kubectl"
    expected="$(curl -fsSL "${base}/kubectl.sha256")"
    actual="$(sha256sum "${KUBECTL_BIN}.tmp" | awk '{print $1}')"
    [[ "${expected}" == "${actual}" ]] || die "checksum kubectl invalide"
    chmod 0755 "${KUBECTL_BIN}.tmp"
    mv "${KUBECTL_BIN}.tmp" "${KUBECTL_BIN}"
}

installed_k8s=""
if [[ -x "${KUBECTL_BIN}" ]]; then
    installed_k8s="$("${KUBECTL_BIN}" version --client 2>/dev/null | awk '/Client Version/ {print $3}')"
fi
[[ "${installed_k8s}" == "v${K8S_VERSION}" ]] || install_kubectl

# --- 4. vérification depuis l'hôte ---------------------------------------
log "vérification depuis l'hôte"
KUBECONFIG="${KUBECONFIG_FILE}" "${KUBECTL_BIN}" get nodes -o wide

log "cluster prêt"
printf '\n  Kubeconfig : %s\n  Client     : %s v%s\n  Utiliser   : make status\n\n' \
    "${KUBECONFIG_FILE}" "${KUBECTL_BIN}" "${K8S_VERSION}"
