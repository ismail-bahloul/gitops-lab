#!/usr/bin/env bash
#
# Affiche l'adresse IP de la VM, lue depuis les baux DHCP de libvirt.

set -euo pipefail

# virsh et virt-install se connectent par défaut au démon *session* pour un
# utilisateur non root. Les VMs et le réseau NAT vivent sur le démon système.
export LIBVIRT_DEFAULT_URI=qemu:///system

VM_NAME="${VM_NAME:-gitops-lab-01}"

ip="$(virsh domifaddr "${VM_NAME}" --source lease 2>/dev/null \
    | awk '/ipv4/ {print $4}' | cut -d/ -f1 | head -n1 || true)"

if [[ -z "${ip}" ]]; then
    echo "IP introuvable pour ${VM_NAME}" >&2
    exit 1
fi

echo "${ip}"
