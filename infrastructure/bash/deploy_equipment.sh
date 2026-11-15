#!/usr/bin/env bash

set -e

# Carregar les funcions d'ajuda
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/template_base.sh"
source "$SCRIPT_DIR/equipment_base.sh"

# Equips basats en templates (clons enllaçats), segons l'inventari
deployed=()
while IFS=';' read -r name template network cpus memory group ip role; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    deploy_clone "$name" "$template" "$network" "$cpus" "$memory" "$group" "$ip" "$role"
    deployed+=("$name")
done < "$EQUIPMENT_INVENTORY"

boot_check_all "${deployed[@]}"

# pve01 (Proxmox VE): procediment propi, s'afegirà en un pas posterior

log_info "=========================================="
log_info "[+] Equips desplegats correctament."
log_info "=========================================="
