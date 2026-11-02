#!/usr/bin/env bash
# Engega els routers de la delegació en segon pla (headless) i espera
# que mikrotik0 accepti connexions SSH.
#   Ús: start_routers.sh [--pause]
#   --pause  espera Enter abans de tancar (per als llançadors d'escriptori)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ROUTERS=(mikrotik0 mikrotik1 mikrotik2 mikrotik3)
SSH_WAIT=90

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

for r in "${ROUTERS[@]}"; do
    state="$(vm_state "$r")"

    if [[ -z "$state" ]]; then
        log_err "'$r' no existeix. Desplega'l amb: make deploy-routers"
        continue
    fi

    if [[ "$state" == "running" ]]; then
        log_info "'$r' ja està engegat"
        continue
    fi

    log_info "Engegant '$r'..."
    if "$VBOXMANAGE_BIN" startvm "$r" --type headless >/dev/null; then
        log_ok "'$r' engegat"
    else
        log_err "No s'ha pogut engegar '$r'"
    fi
done

# mikrotik0 és el punt d'entrada (127.0.0.1:2200) i el salt cap als altres
log_info "Esperant que mikrotik0 accepti SSH (màx ${SSH_WAIT}s)..."
elapsed=0
until ssh-keyscan -T 2 -p 2200 127.0.0.1 >/dev/null 2>&1; do
    if (( elapsed >= SSH_WAIT )); then
        log_warn "mikrotik0 encara no respon per SSH. Torna-ho a provar d'aquí a una estona."
        pause_if_requested "${1:-}"
        exit 1
    fi
    sleep 3
    elapsed=$((elapsed + 3))
done

log_ok "Routers llestos. Accés: ssh mikrotik0 (i mikrotik1-3 pel salt)"
pause_if_requested "${1:-}"
