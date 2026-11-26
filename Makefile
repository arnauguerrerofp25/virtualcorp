ifeq ($(wildcard .env),)
$(error Missing .env; create it from .env.example with: cp .env.example .env)
endif

include .env

export PROJECT_ROOT ARTIFACTS_DIR CONFIGS_DIR SSH_PUBLIC_KEY_DIR SSH_PRIVATE_KEY_DIR
export ROUTEROS_VERSION ROUTEROS_VDI_FILENAME ROUTEROS_VDI_PATH ROUTEROS_BOX_NAME ROUTEROS_BOX_FILE
export VBOX_ROOT_GROUP VM_ROUTERS_GROUP VM_TEMPLATES_GROUP VBOXMANAGE_BIN

BASH_DIR := $(PROJECT_ROOT)/infrastructure/bash
BOOTSTRAP_DIR := $(PROJECT_ROOT)/automation/scripts/bootstrap
TF_PROXMOX_DIR := $(PROJECT_ROOT)/infrastructure/terraform/proxmox
ANSIBLE_DIR := $(PROJECT_ROOT)/automation/ansible
TF_VARS_FILE ?= terraform.local.tfvars

.PHONY: help deploy-routers delete-routers reset-routers reset_routers ssh-keys routeros-box create_templates deploy_equipment deploy_dhcp

help:
	@printf '%s\n' \
	  'Targets:' \
	  '  deploy-routers  Create and configure the router VMs' \
	  '  delete-routers  Delete the router VM group' \
	  '  reset-routers   Delete and redeploy the router VMs' \
	  '  ssh-keys        Generate the project SSH keys' \
	  '  routeros-box    Build the RouterOS Vagrant box' \
	  '  create_templates Create the Debian VM templates' \
	  '  deploy_equipment Deploy servers, printers and desktops' \
	  '  deploy_dhcp     Deploy dhcp01 (Terraform), Kea and the DHCP relays (Ansible)'

deploy-routers:
	"$(BASH_DIR)/deploy_routers.sh"

delete-routers:
	"$(BASH_DIR)/del_vbox_group.sh" --routers

reset-routers:
	"$(BASH_DIR)/del_vbox_group.sh" --routers
	"$(BASH_DIR)/deploy_routers.sh"

# Keep the original target name available for existing callers.
reset_routers: reset-routers

ssh-keys:
	"$(BOOTSTRAP_DIR)/create_ssh_keys.sh"

routeros-box:
	"$(BOOTSTRAP_DIR)/create_mikrotik_box.sh"

create_templates:
	"$(BASH_DIR)/create_templates.sh"

deploy_equipment:
	"$(BASH_DIR)/deploy_equipment.sh"

# Requisits: túnel WireGuard actiu, pve01 engegat i el token de Proxmox a
# $(TF_PROXMOX_DIR)/$(TF_VARS_FILE) (fitxer local, ignorat per Git).
deploy_dhcp:
	@test -f "$(TF_PROXMOX_DIR)/$(TF_VARS_FILE)" || { echo "Falta $(TF_PROXMOX_DIR)/$(TF_VARS_FILE) (token de Proxmox)"; exit 1; }
	cd "$(ANSIBLE_DIR)" && ansible-playbook playbooks/start_routers.yml
	@ping -c 2 -W 3 10.9.0.133 >/dev/null || { echo "No s'arriba a pve01 (10.9.0.133): comproveu el túnel WireGuard i que pve01 estigui engegat"; exit 1; }
	terraform -chdir="$(TF_PROXMOX_DIR)" init -input=false
	terraform -chdir="$(TF_PROXMOX_DIR)" plan -input=false -var-file=$(TF_VARS_FILE) -out=dhcp.tfplan
	terraform -chdir="$(TF_PROXMOX_DIR)" apply -input=false dhcp.tfplan
	rm -f "$(TF_PROXMOX_DIR)/dhcp.tfplan"
	cd "$(ANSIBLE_DIR)" && ansible-galaxy collection install -r requirements.yml
	cd "$(ANSIBLE_DIR)" && ansible-playbook playbooks/configure_dhcp_dns.yml
