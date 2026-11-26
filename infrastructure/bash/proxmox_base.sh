#!/usr/bin/env bash

# =========================================================
# Funcions per a la instal·lació desatesa de pve01 (Proxmox VE)
# =========================================================
# Requereix common.sh i template_base.sh (vm_exists, vm_dir,
# install_template i SSH_TEST_OPTS).

PVE_NAME="pve01"
PVE_IP="10.9.0.133"            # ha de coincidir amb configs/proxmox/answer.toml.tpl
PVE_CPUS="${PVE_CPUS:-4}"
PVE_MEMORY="${PVE_MEMORY:-8192}"
PVE_DISK_MB="${PVE_DISK_MB:-65536}"
PVE_NETWORK="privada"
PVE_GROUP="${VBOX_ROOT_GROUP}/Servidors"
PVE_ANSWER_TEMPLATE="${CONFIGS_DIR}/proxmox/answer.toml.tpl"
PVE_PASSWORD_FILE="${PVE_PASSWORD_FILE:-${HOME}/.config/virtualcorp/pve01-root-password}"

# Comprovacions de connectivitat: els 4 routers i una IP pública
PVE_PING_TARGETS=(10.9.0.129 10.9.0.226 10.9.0.230 10.9.0.234 1.1.1.1)

# pve01 no té NAT: s'hi accedeix saltant per mikrotik0 (127.0.0.1:2200)
PVE_JUMP_PORT=2200
PVE_SSH_OPTS=(
    "${SSH_TEST_OPTS[@]}"
    -o "ProxyCommand=ssh ${SSH_TEST_OPTS[*]} -p ${PVE_JUMP_PORT} -W %h:%p ${SSH_USER}@127.0.0.1"
)

TOOLS_DIR="${PROJECT_ROOT}/artifacts/tools"
PVE_AIA_BIN="${TOOLS_DIR}/aia-${PROXMOX_AIA_VERSION}/usr/bin/proxmox-auto-install-assistant"


# =========================================================
# EINA OFICIAL D'INSTAL·LACIÓ DESATESA
# =========================================================
# Es descarrega el .deb fixat a la configuració, se'n verifica el SHA256
# i s'extreu a artifacts/tools/. No s'instal·la res al sistema.

get_proxmox_aia() {
    [[ -x "$PVE_AIA_BIN" ]] && return 0

    ISO_DIR="$TOOLS_DIR" download_iso \
        "$PROXMOX_AIA_URL" "$PROXMOX_AIA_FILENAME" "$PROXMOX_AIA_SHA256" || return 1

    dpkg-deb -x "${TOOLS_DIR}/${PROXMOX_AIA_FILENAME}" \
        "${TOOLS_DIR}/aia-${PROXMOX_AIA_VERSION}" || return 1
}


# =========================================================
# ISO DESATESA
# =========================================================
# Genera l'answer file real a partir de la plantilla, el valida amb
# l'eina oficial i l'integra a la ISO de Proxmox.

build_pve_iso() {
    local output_iso="$1"
    local answer_file password hash keys tpl key

    answer_file="$(mktemp)" || return 1

    # Contrasenya de root aleatòria: es desa NOMÉS a l'equip local (600),
    # mai al repositori. Cal per a la interfície web (https://IP:8006).
    password="$(openssl rand -base64 18)"
    mkdir -p "$(dirname "$PVE_PASSWORD_FILE")"
    ( umask 077; printf '%s\n' "$password" > "$PVE_PASSWORD_FILE" )
    hash="$(openssl passwd -6 "$password")"

    # Clau personal + clau del professor
    keys="$(
        for key in "$SYSADMIN_PUB_KEY_FILE" "$AUDIT_PUB_KEY_FILE"; do
            printf '    "%s",\n' "$(tr -d '\n' < "$key")"
        done
    )"

    tpl="$(<"$PVE_ANSWER_TEMPLATE")"
    tpl="${tpl//@ROOT_PASSWORD_HASH@/"$hash"}"
    tpl="${tpl//@ROOT_SSH_KEYS@/"$keys"}"
    printf '%s\n' "$tpl" > "$answer_file"

    log_info "Validant l'answer file de '$PVE_NAME'"
    # L'eina retorna 0 fins i tot amb errors: es comprova el missatge d'èxit
    if ! "$PVE_AIA_BIN" validate-answer "$answer_file" 2>&1 | grep -q 'parsed successfully'; then
        log_err "L'answer file de '$PVE_NAME' no és vàlid."
        rm -f "$answer_file"
        return 1
    fi

    log_info "Generant ISO desatesa '$(basename "$output_iso")'"
    rm -f "$output_iso"
    if ! "$PVE_AIA_BIN" prepare-iso \
            --fetch-from iso \
            --answer-file "$answer_file" \
            --output "$output_iso" \
            "${ISO_DIR}/${PROXMOX_ISO_FILENAME}" >/dev/null; then
        log_err "No s'ha pogut preparar la ISO de Proxmox."
        rm -f "$answer_file"
        return 1
    fi

    rm -f "$answer_file"
    log_ok "Contrasenya de root de '$PVE_NAME' desada a $PVE_PASSWORD_FILE"
}


# =========================================================
# CREACIÓ DE LA VM
# =========================================================

create_pve_vm() {
    local iso="$1"
    local dir

    log_info "Creant VM '$PVE_NAME' (${PVE_CPUS} CPU, ${PVE_MEMORY} MB RAM, ${PVE_DISK_MB} MB de disc)"

    "$VBOXMANAGE_BIN" createvm \
        --name "$PVE_NAME" \
        --ostype Debian_64 \
        --register >/dev/null || return 1

    # Una única interfície a la zona privada (cap NAT) i virtualització
    # anidada activada abans de la primera arrencada. La NIC va en mode
    # promiscu perquè els contenidors i VM de Proxmox surten pel bridge
    # amb la seva pròpia MAC; si no, VirtualBox en descarta les trames.
    "$VBOXMANAGE_BIN" modifyvm "$PVE_NAME" \
        --groups "$PVE_GROUP" \
        --cpus "$PVE_CPUS" \
        --memory "$PVE_MEMORY" \
        --firmware bios \
        --nested-hw-virt on \
        --graphicscontroller vmsvga \
        --vram 16 \
        --audio-enabled off \
        --boot1 disk --boot2 dvd --boot3 none --boot4 none \
        --nic1 intnet \
        --intnet1 "$PVE_NETWORK" \
        --nicpromisc1 allow-all \
        --cableconnected1 on \
        --description "Node Proxmox VE del CPD. IP fixa: ${PVE_IP}" || return 1

    dir="$(vm_dir "$PVE_NAME")"

    "$VBOXMANAGE_BIN" createmedium disk \
        --filename "$dir/$PVE_NAME.vdi" \
        --size "$PVE_DISK_MB" \
        --format VDI >/dev/null || return 1

    "$VBOXMANAGE_BIN" storagectl "$PVE_NAME" \
        --name "SATA" \
        --add sata \
        --controller IntelAhci \
        --portcount 2 || return 1

    "$VBOXMANAGE_BIN" storageattach "$PVE_NAME" \
        --storagectl "SATA" --port 0 --device 0 \
        --type hdd --medium "$dir/$PVE_NAME.vdi" || return 1

    "$VBOXMANAGE_BIN" storageattach "$PVE_NAME" \
        --storagectl "SATA" --port 1 --device 0 \
        --type dvddrive --medium "$iso" || return 1
}


# =========================================================
# VERIFICACIÓ
# =========================================================
# Des de pve01: sistema, IP, ping als 4 routers i a Internet,
# virtualització anidada (KVM) i claus SSH. Després s'apaga.

verify_pve01() {
    local elapsed=0

    if [[ "$(vm_state mikrotik0)" != "running" ]]; then
        log_info "Els routers estan aturats: s'engeguen per verificar '$PVE_NAME'"
        "$SCRIPT_DIR/start_routers.sh" || return 1
    fi

    "$VBOXMANAGE_BIN" startvm "$PVE_NAME" --type headless >/dev/null || return 1

    log_info "Esperant SSH de '$PVE_NAME' (${PVE_IP}) a través de mikrotik0..."
    until ssh "${PVE_SSH_OPTS[@]}" -o ConnectTimeout=5 root@"$PVE_IP" true &>/dev/null; do
        sleep 10
        elapsed=$((elapsed + 10))
        if (( elapsed >= 300 )); then
            log_err "'$PVE_NAME' no respon per SSH després de 5 minuts."
            return 1
        fi
    done

    {
        cat <<'EOF'
echo "--- sistema"; hostname -f; pveversion
echo "--- xarxa"; ip -brief address show vmbr0; ip route show default
echo "--- claus autoritzades (root)"; ssh-keygen -lf /root/.ssh/authorized_keys
echo "--- virtualització anidada"
test -e /dev/kvm && echo "/dev/kvm: OK"
echo "CPU amb extensions vmx/svm: $(grep -cwE 'vmx|svm' /proc/cpuinfo)"
grep -qwE 'vmx|svm' /proc/cpuinfo
lsmod | grep -E '^kvm_(intel|amd)'
echo "--- emmagatzematge"; pvesm status
echo "--- connectivitat"
EOF
        for ip in "${PVE_PING_TARGETS[@]}"; do
            printf 'ping -c 2 -W 2 %s >/dev/null || { echo "ping %s: ERROR"; exit 1; }; echo "ping %s: OK"\n' \
                "$ip" "$ip" "$ip"
        done
    } | ssh "${PVE_SSH_OPTS[@]}" root@"$PVE_IP" 'sh -e' || return 1

    # Apagada ordenada
    "$VBOXMANAGE_BIN" controlvm "$PVE_NAME" acpipowerbutton &>/dev/null
    elapsed=0
    until [[ "$(vm_state "$PVE_NAME")" == "poweroff" ]] || (( elapsed >= 120 )); do
        sleep 5
        elapsed=$((elapsed + 5))
    done
}


# =========================================================
# DESPLEGAMENT COMPLET DE pve01
# =========================================================

deploy_pve01() {
    local iso="${ISO_DIR}/${PVE_NAME}-auto.iso"

    if vm_exists "$PVE_NAME"; then
        log_warn "La màquina '$PVE_NAME' ja existeix. S'omet."
        return 0
    fi

    download_iso "$PROXMOX_ISO_URL" "$PROXMOX_ISO_FILENAME" "$PROXMOX_ISO_SHA256" || return 1
    get_proxmox_aia || return 1
    build_pve_iso "$iso" || return 1
    create_pve_vm "$iso" || return 1
    install_template "$PVE_NAME" "$iso" || return 1
    verify_pve01 || return 1

    log_ok "'$PVE_NAME' instal·lat i verificat (Proxmox VE, IP ${PVE_IP}, virtualització anidada)"
}
