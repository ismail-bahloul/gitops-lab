#!/usr/bin/env bash
#
# Détruit la VM et son disque. L'image de base reste en cache : recréer une
# VM ne coûte alors que quelques secondes (overlay qcow2).

set -euo pipefail

VM_NAME="${VM_NAME:-gitops-lab-01}"
POOL_DIR="${POOL_DIR:-/var/lib/libvirt/images/gitops-lab}"
DISK="${POOL_DIR}/${VM_NAME}.qcow2"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if virsh dominfo "${VM_NAME}" >/dev/null 2>&1; then
    virsh destroy "${VM_NAME}" >/dev/null 2>&1 || true
    virsh undefine "${VM_NAME}" >/dev/null
    echo "VM ${VM_NAME} supprimée"
else
    echo "VM ${VM_NAME} absente"
fi

sudo rm -f "${DISK}"

# Le kubeconfig et les artefacts générés n'ont plus de sens sans la VM.
rm -rf "${REPO_ROOT}/.kube" "${REPO_ROOT}/build"

echo "disque et artefacts locaux supprimés (image de base conservée)"
