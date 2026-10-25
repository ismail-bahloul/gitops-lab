# ADR 0001 — K3s plutôt qu'un Kubernetes installé avec kubeadm

- **Statut** : accepté
- **Date** : 2026-10-25
- **Portée** : Sessions 1 et 2 (le cluster du lab)

## Contexte

Le cluster doit tourner sur une machine physique unique (Ryzen 7, 32 Go) et être
utilisable en quelques minutes, car l'objet de la Session 1 est la boucle GitOps,
pas l'installation de Kubernetes. La Session 2 reconstruira ensuite un cluster de
trois nœuds avec Terraform et Ansible, sans changer de distribution.

Contraintes : aucun coût cloud, aucun composant managé, et un cluster qui doit
rester démontrable dans six mois (donc versions épinglées).

## Décision

**K3s**, version `v1.36.5+k3s1` (canal `stable` au moment de l'écriture),
un serveur unique, installation via le script officiel.

## Conséquences

**Positives**

- Un seul binaire embarque l'API server, le controller-manager, le scheduler,
  le kubelet, containerd, le CNI (Flannel), Traefik, ServiceLB, le
  provisionneur `local-path` et metrics-server. Installation complète en moins
  d'une minute, un seul service systemd à superviser.
- Distribution **certifiée conforme CNCF** : les objets manipulés (Deployment,
  Service, Ingress, CRD, RBAC) sont du Kubernetes standard. Ce qui est appris
  ici se transpose.
- Empreinte faible : le cluster complet tient dans une VM de 4 Go, ce qui laisse
  de la place à Argo CD et à la stack d'observabilité.
- Le même binaire servira d'agent en Session 2 (`k3s agent --server …`), donc
  une seule mécanique à comprendre pour le serveur et les agents.

**Négatives / limites assumées**

- Ce n'est pas kubeadm : l'emplacement des certificats, le datastore (SQLite via
  kine par défaut, etcd disponible) et les manifests système diffèrent des
  tutoriels « vanilla ». Il faut savoir transposer, et le dire.
- Certaines briques sont masquées : pas de `kubeadm upgrade`, pas de manifests
  statiques dans `/etc/kubernetes/manifests`. Le debug passe par
  `/var/lib/rancher/k3s` et `journalctl -u k3s`.
- Un seul serveur dans ce lab : **pas de haute disponibilité**. La perte du
  nœud perd le control-plane (cf. limites du README).

## Alternatives écartées

| Alternative | Raison du rejet |
|---|---|
| **kubeadm** | Plus proche de l'examen CKA et du Kubernetes « d'entreprise », mais il faut gérer le runtime de conteneurs, le CNI, les certificats et le kubelet séparément : environ une heure de plus avant le premier nœud `Ready`, pour un bénéfice nul sur l'objectif GitOps. |
| **kind / k3d** | Clusters dans des conteneurs : rapides, mais il n'y a pas de vraies machines, donc pas de Session 2 crédible (VMs libvirt, agents distincts, réseau). |
| **minikube** | Orienté poste de développement mono-nœud ; ne représente ni un cluster à agents ni une infrastructure provisionnée. |
| **Kubernetes complet (kubeadm + etcd + CNI)** | Surdimensionné pour 32 Go de RAM et un objectif de démonstration. |

## Références

- <https://docs.k3s.io/>
- `scripts/k3s-install.sh`
- ADR 0005 (environnement d'exécution)
