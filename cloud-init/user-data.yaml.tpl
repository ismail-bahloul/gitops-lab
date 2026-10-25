#cloud-config
# Généré par scripts/vm-up.sh à partir de ce template.
# La clé publique SSH n'est jamais commitée : le script l'injecte depuis
# $HOME/.ssh à la création de la VM.

hostname: __VM_NAME__
manage_etc_hosts: true
timezone: Europe/Paris

ssh_authorized_keys:
  - __SSH_PUBKEY__

package_update: true
packages:
  - qemu-guest-agent   # IP connue de libvirt sans dépendre du bail DHCP
  - conntrack          # kube-proxy purge les entrées obsolètes via cette CLI
  - curl
  - jq

# Prérequis noyau de Kubernetes. Ce n'est pas spécifique à K3s : sans
# ip_forward, le nœud ne route pas le trafic entre pods.
write_files:
  - path: /etc/modules-load.d/k8s.conf
    permissions: "0644"
    content: |
      overlay
      br_netfilter
  - path: /etc/sysctl.d/99-kubernetes.conf
    permissions: "0644"
    content: |
      net.ipv4.ip_forward = 1
      net.bridge.bridge-nf-call-iptables = 1
      net.bridge.bridge-nf-call-ip6tables = 1

runcmd:
  - [ systemctl, enable, --now, qemu-guest-agent ]
  - [ modprobe, br_netfilter ]
  - [ modprobe, overlay ]
  - [ sysctl, --system ]

final_message: "gitops-lab VM prête en $UPTIME secondes"
