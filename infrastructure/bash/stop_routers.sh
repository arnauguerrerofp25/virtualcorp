#!/usr/bin/env bash
# Apaga de manera ordenada (ACPI) els routers de la delegació.
# Si algun no s'atura en TIMEOUT segons, es força l'apagada.
#   Ús: stop_routers.sh [--pause]
#   --pause  espera Enter abans de tancar (per als llançadors d'escriptori)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Ordre invers: el router de sortida (mikrotik0) és l'últim
ROUTERS=(mikrotik3 mikrotik2 mikrotik1 mikrotik0)
TIMEOUT=60

vm_state() {
    "$VBOXMANAGE_BIN" showvminfo "$1" --machinereadable 2>/dev/null |
        grep '^VMState=' | cut -d'"' -f2
}

pause_if_requested() {
    if [[ "${1:-}" == "--pause" ]]; then
        echo
        read -rp "Prem Enter per tancar..." _
    fi
}

pending=()

for r in "${ROUTERS[@]}"; do
    state="$(vm_state "$r")"

    if [[ -z "$state" ]]; then
        log_warn "'$r' no existeix"
        continue
    fi

    if [[ "$state" != "running" ]]; then
        log_info "'$r' ja està aturat ($state)"
        continue
    fi

    log_info "Enviant senyal d'apagada a '$r'..."
    "$VBOXMANAGE_BIN" controlvm "$r" acpipowerbutton
    pending+=("$r")
done

elapsed=0
while (( ${#pending[@]} > 0 && elapsed < TIMEOUT )); do
    sleep 2
    elapsed=$((elapsed + 2))

    still_running=()
    for r in "${pending[@]}"; do
        if [[ "$(vm_state "$r")" == "poweroff" ]]; then
            log_ok "'$r' aturat"
        else
            still_running+=("$r")
        fi
    done
    pending=("${still_running[@]}")
done

for r in "${pending[@]}"; do
    log_warn "'$r' no s'ha aturat en ${TIMEOUT}s: forçant l'apagada"
    "$VBOXMANAGE_BIN" controlvm "$r" poweroff >/dev/null 2>&1 &&
        log_ok "'$r' aturat (forçat)"
done

log_ok "Tots els routers estan aturats."
pause_if_requested "${1:-}"
