# Décisions d'architecture

Chaque décision structurante est consignée ici au format court
**Contexte / Décision / Conséquences**, une page maximum.

Convention : un ADR est ajouté dans le commit qui matérialise la décision.
`git log` et cet index racontent ainsi la même histoire, et une décision se
retrouve en une commande :

```bash
git log -- docs/adr/0005-environnement-vm-vs-hote.md
```

| # | Décision | Statut |
|---|---|---|
| 0001 | K3s plutôt que kubeadm / Kubernetes complet | à venir (Session 1) |
| 0002 | Argo CD plutôt que Flux | à venir (Session 1) |
| 0003 | Terraform + libvirt plutôt qu'un cloud | à venir (Session 2) |
| 0004 | Gestion des secrets | à venir (au premier secret réel) |
| [0005](0005-environnement-vm-vs-hote.md) | VM dédiée plutôt que l'hôte | accepté |
