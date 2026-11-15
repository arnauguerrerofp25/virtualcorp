#!/usr/bin/env bash

# =========================================================
# Funcions de desplegament d'equips per clonació enllaçada
# =========================================================
# Requereix common.sh i template_base.sh (vm_exists, vm_state).

EQUIPMENT_INVENTORY="${CONFIGS_DIR}/equipment.csv"
BOOT_CHECK_WAIT="${BOOT_CHECK_WAIT:-90}"
SHUTDOWN_TIMEOUT="${SHUTDOWN_TIMEOUT:-120}"

# Crea un clon enllaçat des del snapshot 'base' del template i li aplica
# el maquinari i la xarxa. Si ja existeix, s'omet.
deploy_clone() {
    local name="$1" template="$2" network="$3" cpus="$4" memory="$5"
    local group="$6" ip="$7" role="$8"

    if vm_exists "$name"; then
        log_warn "La màquina '$name' ja existeix. S'omet."
        return 0
    fi

    if ! "$VBOXMANAGE_BIN" snapshot "$template" showvminfo "$TEMPLATE_SNAPSHOT" &>/dev/null; then
        log_err "No existeix el template '$template' amb snapshot '$TEMPLATE_SNAPSHOT': executeu make create_templates."
        return 1
    fi

    log_info "Clon enllaçat '$name' ← '$template' (xarxa '$network', ${cpus} CPU, ${memory} MB)"

    "$VBOXMANAGE_BIN" clonevm "$template" \
        --snapshot "$TEMPLATE_SNAPSHOT" \
        --options link \
        --name "$name" \
        --register >/dev/null || return 1

    # Única interfície: xarxa interna del seu segment (cap NAT)
    "$VBOXMANAGE_BIN" modifyvm "$name" \
        --groups "${VBOX_ROOT_GROUP}/${group}" \
        --cpus "$cpus" \
        --memory "$memory" \
        --nic1 intnet \
        --intnet1 "$network" \
        --cableconnected1 on \
        --description "${role}. IP prevista: ${ip}" || return 1
}

# Comprova que tots els equips arrenquen: s'engeguen, s'espera que el
# sistema estigui en marxa i s'apaguen amb el botó ACPI. Si una màquina
# s'apaga sola en rebre'l, vol dir que el sistema operatiu ha arrencat.
boot_check_all() {
    local names=("$@")
    local name elapsed failed=0

    log_info "Engegant ${#names[@]} màquines per comprovar l'arrencada..."
    for name in "${names[@]}"; do
        "$VBOXMANAGE_BIN" startvm "$name" --type headless >/dev/null || failed=1
    done

    sleep "$BOOT_CHECK_WAIT"

    for name in "${names[@]}"; do
        "$VBOXMANAGE_BIN" controlvm "$name" acpipowerbutton &>/dev/null
    done

    for name in "${names[@]}"; do
        elapsed=0
        while [[ "$(vm_state "$name")" != "poweroff" ]] && (( elapsed < SHUTDOWN_TIMEOUT )); do
            sleep 5
            elapsed=$((elapsed + 5))
        done

        if [[ "$(vm_state "$name")" == "poweroff" ]]; then
            log_ok "'$name' ha arrencat i s'ha aturat de forma ordenada"
        else
            log_err "'$name' no respon a l'apagada ACPI: probablement no ha arrencat bé."
            "$VBOXMANAGE_BIN" controlvm "$name" poweroff &>/dev/null
            failed=1
        fi
    done

    return "$failed"
}
