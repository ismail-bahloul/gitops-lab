#!/usr/bin/env bash
#
# Crée une VM Ubuntu 24.04 jetable sur libvirt (réseau NAT « default »).
#
# Ce script est le PROTOTYPE MANUEL de ce que Terraform automatisera en
# Session 2. Il existe pour deux raisons :
#   1. garder l'hôte propre : tout ce qui touche au cluster vit dans la VM ;
#   2. comprendre chaque paramètre avant de le traduire en HCL.
#
# Idempotent : si la VM existe déjà, le script ne fait rien.

set -euo pipefail

VM_NAME="${VM_NAME:-gitops-lab-01}"
VM_VCPUS="${VM_VCPUS:-2}"
VM_MEMORY_MB="${VM_MEMORY_MB:-4096}"
VM_DISK_GB="${VM_DISK_GB:-25}"

# Ubuntu 24.04 LTS (noble) : version majeure figée volontairement, supportée
# jusqu'en 2029. Une LTS n'est pas une contrainte esthétique : c'est ce qui
# garantit que le dépôt reste démontrable dans six mois.
UBUNTU_RELEASE="${UBUNTU_RELEASE:-noble}"
OS_VARIANT="${OS_VARIANT:-ubuntu24.04}"
IMAGE_BASE_URL="${IMAGE_BASE_URL:-https://cloud-images.ubuntu.com/${UBUNTU_RELEASE}/current}"

POOL_DIR="${POOL_DIR:-/var/lib/libvirt/images/gitops-lab}"
BASE_IMG="${POOL_DIR}/base/${UBUNTU_RELEASE}-server-cloudimg-amd64.img"
DISK="${POOL_DIR}/${VM_NAME}.qcow2"

SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-${HOME}/.ssh/id_ed25519.pub}"
SSH_KEY_FILE="${SSH_KEY_FILE:-${SSH_PUBKEY_FILE%.pub}}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLOUD_INIT_DIR="${REPO_ROOT}/cloud-init"
BUILD_DIR="${REPO_ROOT}/build"

QEMU_USER="${QEMU_USER:-qemu}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merreur:\033[0m %s\n' "$*" >&2; exit 1; }

# --- prérequis -------------------------------------------------------------
for bin in virt-install virsh qemu-img curl sha256sum; do
    command -v "${bin}" >/dev/null 2>&1 || die "${bin} introuvable"
done
[[ -r "${SSH_PUBKEY_FILE}" ]] || die "clé publique SSH introuvable : ${SSH_PUBKEY_FILE}"
id -u "${QEMU_USER}" >/dev/null 2>&1 || QEMU_USER="root"

if virsh dominfo "${VM_NAME}" >/dev/null 2>&1; then
    log "la VM ${VM_NAME} existe déjà — rien à faire"
    exit 0
fi

# --- libvirt : service et réseau NAT --------------------------------------
# Le réseau « default » (192.168.122.0/24) fait du NAT : la VM sort vers
# Internet (images K3s, Argo CD, ghcr.io) et l'hôte peut la joindre.
log "vérification de libvirtd et du réseau NAT"
systemctl is-active --quiet libvirtd || sudo systemctl enable --now libvirtd
virsh net-info default >/dev/null 2>&1 || die "réseau libvirt « default » absent"
if ! virsh net-info default | grep -q '^Active:[[:space:]]*yes'; then
    log "démarrage du réseau NAT"
    sudo virsh net-start default
fi
sudo virsh net-autostart default >/dev/null

# --- image de base --------------------------------------------------------
sudo mkdir -p "$(dirname "${BASE_IMG}")"

if [[ ! -f "${BASE_IMG}" ]]; then
    log "téléchargement de l'image cloud Ubuntu (${UBUNTU_RELEASE}, ~600 Mo)"
    sudo curl -fL --progress-bar -o "${BASE_IMG}.part" \
        "${IMAGE_BASE_URL}/$(basename "${BASE_IMG}")"
    sudo curl -fsSL -o "${BASE_IMG}.SHA256SUMS" "${IMAGE_BASE_URL}/SHA256SUMS"

    # Vérification d'intégrité : on ne démarre pas une image non vérifiée.
    expected="$(awk -v f="$(basename "${BASE_IMG}")" \
        '{ n = $2; sub(/^\*/, "", n); if (n == f) { print $1; exit } }' \
        "${BASE_IMG}.SHA256SUMS")"
    actual="$(sha256sum "${BASE_IMG}.part" | awk '{print $1}')"
    [[ -n "${expected}" ]] || die "image absente du fichier SHA256SUMS"
    [[ "${expected}" == "${actual}" ]] || die "checksum invalide (attendu ${expected}, obtenu ${actual})"
    log "checksum OK"

    sudo mv "${BASE_IMG}.part" "${BASE_IMG}"
    sudo rm -f "${BASE_IMG}.SHA256SUMS"
fi

# Lecture seule : c'est le disque de base partagé, il ne doit jamais changer.
sudo chmod 0444 "${BASE_IMG}"

# --- disque de la VM ------------------------------------------------------
# Overlay qcow2 : le disque de la VM ne stocke que ses différences avec
# l'image de base. Création instantanée, quelques centaines de Mo réels.
if [[ ! -f "${DISK}" ]]; then
    log "création du disque (overlay qcow2, ${VM_DISK_GB} Go virtuels)"
    sudo qemu-img create -q -f qcow2 -F qcow2 -b "${BASE_IMG}" "${DISK}" "${VM_DISK_GB}G"
fi
sudo chown "${QEMU_USER}:${QEMU_USER}" "${DISK}"
sudo chmod 0600 "${DISK}"

# --- cloud-init -----------------------------------------------------------
# Généré depuis un template : aucune clé SSH personnelle n'est commitée.
log "génération de la configuration cloud-init"
mkdir -p "${BUILD_DIR}"
SSH_PUBKEY="$(cat "${SSH_PUBKEY_FILE}")"
sed -e "s|__VM_NAME__|${VM_NAME}|g" \
    -e "s|__SSH_PUBKEY__|${SSH_PUBKEY}|g" \
    "${CLOUD_INIT_DIR}/user-data.yaml.tpl" > "${BUILD_DIR}/user-data.yaml"
sed -e "s|__VM_NAME__|${VM_NAME}|g" \
    "${CLOUD_INIT_DIR}/meta-data.yaml.tpl" > "${BUILD_DIR}/meta-data.yaml"

# --- création de la VM ----------------------------------------------------
# --import        : pas d'installateur, l'image cloud démarre directement
# --cloud-init    : injecte un ISO NoCloud (utilisateur, clé SSH, sysctl)
# --noautoconsole : rend la main au lieu d'ouvrir une console
log "définition et démarrage de la VM ${VM_NAME}"
sudo virt-install \
    --name "${VM_NAME}" \
    --memory "${VM_MEMORY_MB}" \
    --vcpus "${VM_VCPUS}" \
    --cpu host-passthrough \
    --os-variant "${OS_VARIANT}" \
    --disk "path=${DISK},bus=virtio,cache=none,discard=unmap" \
    --import \
    --network "network=default,model=virtio" \
    --cloud-init "user-data=${BUILD_DIR}/user-data.yaml,meta-data=${BUILD_DIR}/meta-data.yaml" \
    --graphics none \
    --console pty,target_type=serial \
    --noautoconsole \
    --autostart

# --- attente de disponibilité --------------------------------------------
# Un known_hosts dédié au lab évite de polluer ~/.ssh/known_hosts et évite le
# classique « REMOTE HOST IDENTIFICATION HAS CHANGED » quand recreate réutilise
# la même IP DHCP.
KNOWN_HOSTS="${BUILD_DIR}/known_hosts"

log "attente de l'adresse IP (DHCP du réseau NAT)"
IP=""
for _ in $(seq 1 60); do
    IP="$(virsh domifaddr "${VM_NAME}" --source lease 2>/dev/null \
        | awk '/ipv4/ {print $4}' | cut -d/ -f1 | head -n1 || true)"
    [[ -n "${IP}" ]] && break
    sleep 3
done
[[ -n "${IP}" ]] || die "aucune adresse IP obtenue pour ${VM_NAME}"

log "attente de SSH puis de la fin de cloud-init (1 à 2 min)"
ready=""
for _ in $(seq 1 60); do
    if ssh -i "${SSH_KEY_FILE}" -o UserKnownHostsFile="${KNOWN_HOSTS}" \
           -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 \
           -o BatchMode=yes "ubuntu@${IP}" true 2>/dev/null; then
        ready="yes"
        break
    fi
    sleep 5
done
[[ -n "${ready}" ]] || die "SSH injoignable sur ubuntu@${IP}"

ssh -i "${SSH_KEY_FILE}" -o UserKnownHostsFile="${KNOWN_HOSTS}" -o BatchMode=yes \
    "ubuntu@${IP}" 'cloud-init status --wait >/dev/null' \
    || warn "cloud-init n'a pas signalé de succès complet (voir : cloud-init status --long)"

log "VM prête"
printf '\n  Nom     : %s\n  IP      : %s\n  Accès   : ssh ubuntu@%s\n  Ressources : %s vCPU / %s Mo / %s Go\n\n' \
    "${VM_NAME}" "${IP}" "${IP}" "${VM_VCPUS}" "${VM_MEMORY_MB}" "${VM_DISK_GB}"
