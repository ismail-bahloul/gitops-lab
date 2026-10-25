# GitOps Lab — point d'entrée unique.
# Objectif : un lecteur doit pouvoir déployer sans lire le reste du dépôt.
# L'interface (up / destroy / status) reste stable ; seule son implémentation
# évolue : VM manuelle en Session 1, Terraform + Ansible en Session 2.

SHELL := /usr/bin/env bash

# virsh lancé par un utilisateur non root parle au démon *session* par défaut,
# qui ne contient ni le réseau NAT ni les VMs. On cible explicitement le système.
LIBVIRT_DEFAULT_URI ?= qemu:///system
export LIBVIRT_DEFAULT_URI

.DEFAULT_GOAL := help

VM_NAME ?= gitops-lab-01
SSH_KEY ?= $(HOME)/.ssh/id_ed25519
KUBECONFIG_FILE := $(CURDIR)/.kube/config
export KUBECONFIG := $(KUBECONFIG_FILE)

.PHONY: help up destroy vm-up vm-destroy vm-stop vm-ip ssh status

help: ## Affiche cette aide
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

up: vm-up ## Crée ou démarre la VM (convergent)

destroy: vm-destroy ## Détruit tout : VM, disque, seed (garde l'image de base)

vm-up: ## Crée / démarre la VM Ubuntu 24.04 et attend SSH
	./scripts/vm-up.sh

vm-stop: ## Arrêt propre de la VM (ACPI)
	@virsh shutdown $(VM_NAME) 2>/dev/null \
		&& echo "arrêt demandé (compter ~10 s)" || echo "VM déjà éteinte"

vm-destroy: ## Détruit la VM, son disque et son seed
	./scripts/vm-destroy.sh

vm-ip: ## Affiche l'adresse IP de la VM
	@./scripts/vm-ip.sh

ssh: ## Ouvre un shell sur la VM
	@ssh -i $(SSH_KEY) -o UserKnownHostsFile=build/known_hosts \
		-o StrictHostKeyChecking=accept-new "ubuntu@$$(./scripts/vm-ip.sh)"

status: ## Affiche l'état de la VM
	@virsh dominfo $(VM_NAME) 2>/dev/null | grep -E '^(Name|State)' \
		|| echo "VM $(VM_NAME) absente"
