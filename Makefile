# GitOps Lab — point d'entrée unique.
# Objectif : un lecteur doit pouvoir déployer sans lire le reste du dépôt.
# L'interface (up / destroy / status) reste stable ; seule son implémentation
# évolue : VM manuelle en Session 1, Terraform + Ansible en Session 2.

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

VM_NAME ?= gitops-lab-01
KUBECONFIG_FILE := $(CURDIR)/.kube/config
export KUBECONFIG := $(KUBECONFIG_FILE)

.PHONY: help up destroy vm-up vm-destroy vm-ip ssh status

help: ## Affiche cette aide
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

up: vm-up ## Crée l'environnement (Session 1 : une VM jetable)

destroy: vm-destroy ## Détruit l'environnement

vm-up: ## Crée la VM Ubuntu 24.04 (idempotent)
	./scripts/vm-up.sh

vm-destroy: ## Détruit la VM et son disque (conserve l'image de base)
	./scripts/vm-destroy.sh

vm-ip: ## Affiche l'adresse IP de la VM
	@./scripts/vm-ip.sh

ssh: ## Ouvre un shell sur la VM
	@ssh "ubuntu@$$(./scripts/vm-ip.sh)"

status: ## Affiche l'état de la VM
	@virsh dominfo $(VM_NAME) 2>/dev/null | grep -E '^(Name|State)' \
		|| echo "VM $(VM_NAME) absente"
