# ADR 0005 — Environnement d'exécution : une VM dédiée plutôt que l'hôte

- **Statut** : accepté
- **Date** : 2026-10-25
- **Portée** : Session 1 (prototype manuel ; repris par Terraform en Session 2)

## Contexte

Le cluster doit tourner sur une seule machine physique (Ryzen 7 5800H, 32 Go de
RAM, hôte CachyOS — Arch-based, donc *rolling release*). Trois options ont été
évaluées :

1. installer K3s directement sur l'hôte ;
2. utiliser un conteneur système (Distrobox, LXD) ;
3. provisionner une VM sur libvirt.

La Session 2 prévoit de toute façon Terraform + provider libvirt pour créer un
cluster de trois nœuds. L'environnement de la Session 1 n'est donc pas neutre :
il doit préparer cette étape.

## Décision

Une **VM Ubuntu 24.04 LTS jetable**, créée par `scripts/vm-up.sh` :
2 vCPU, 4 Go de RAM, 25 Go en overlay qcow2, réseau NAT libvirt `default`.

## Conséquences

**Positives**

- L'hôte reste propre : aucun service K3s, aucune règle nftables, aucun
  kubeconfig global. `make destroy` remet la machine dans son état initial.
- Le substrat de la Session 1 est celui de la Session 2 : les commandes
  manuelles deviennent le contenu du rôle Ansible `k3s`, sans réécriture.
- Les particularités d'Arch (noyau *rolling*, `ip_forward=0` par défaut,
  `iptables-nft`, absence de `conntrack`) ne viennent pas polluer
  l'apprentissage de Kubernetes.
- Les scénarios de panne de la Session 3 pourront être précédés d'un snapshot
  libvirt, donc rejoués à l'identique.

**Négatives**

- Coût de mise en place : environ 45 minutes et 600 Mo d'image de base.
- Une couche de plus entre l'hôte et le cluster : en cas de problème réseau, il
  faut distinguer NAT libvirt et réseau Kubernetes.
- 4 Go de RAM immobilisés. Insuffisant pour trois nœuds : cette VM sera
  détruite avant la Session 2.

## Alternatives écartées

| Alternative | Raison du rejet |
|---|---|
| **K3s sur l'hôte** | Divergence avec la cible Ubuntu de la Session 2 ; impossible de démontrer « je reconstruis depuis zéro » proprement. |
| **Distrobox / LXD** | K3s exige systemd, des cgroups et des modules noyau ; il faudrait des contournements privilégiés. Aucun gain d'apprentissage. |
| **RHEL** | Souscription nominative obligatoire : `make up` ne serait pas reproductible par un lecteur, ou exigerait des identifiants (donc un secret). |
| **Fedora** | Cycle de vie d'environ 13 mois, incompatible avec un dépôt de portfolio destiné à rester démontrable. |
| **AlmaLinux 9** | Bon candidat si la cible devient le marché RHEL/Centreon. Écarté ici pour ne pas ajouter SELinux et firewalld aux sujets de la Session 1. Réversible : en Session 2, l'image devient une variable Terraform. |

## Références

- `scripts/vm-up.sh`, `scripts/vm-destroy.sh`, `cloud-init/user-data.yaml.tpl`
- Session 2 : `terraform/` remplacera `scripts/` et `cloud-init/`
