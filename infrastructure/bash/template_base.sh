#!/usr/bin/env bash

# =========================================================
# Funcions per crear els templates Debian (activitat 2)
# =========================================================
# Requereix common.sh (variables, logs, download_iso i wait_ssh).

TEMPLATE_PRESEED_DIR="${CONFIGS_DIR}/preseed"
TEMPLATE_SNAPSHOT="base"
TEMPLATE_INSTALL_TIMEOUT="${TEMPLATE_INSTALL_TIMEOUT:-3600}"
TEMPLATE_TEST_SSH_PORT="${TEMPLATE_TEST_SSH_PORT:-2299}"

SSH_TEST_OPTS=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o IdentitiesOnly=yes
    -i "$SYSADMIN_PRIVATE_KEY_FILE"
)


# =========================================================
# UTILITATS
# =========================================================

vm_exists() {
    "$VBOXMANAGE_BIN" showvminfo "$1" &>/dev/null
}

vm_state() {
    "$VBOXMANAGE_BIN" showvminfo "$1" --machinereadable |
        sed -n 's/^VMState="\(.*\)"$/\1/p'
}

vm_dir() {
    dirname "$(
        "$VBOXMANAGE_BIN" showvminfo "$1" --machinereadable |
            sed -n 's/^CfgFile="\(.*\)"$/\1/p'
    )"
}


# =========================================================
# PREREQUISITS
# =========================================================

check_template_prerequisites() {
    local f

    if ! command -v xorriso &>/dev/null; then
        log_err "Cal xorriso per preparar la ISO desatesa: sudo apt install xorriso"
        return 1
    fi

    for f in "$SYSADMIN_PUB_KEY_FILE" "$AUDIT_PUB_KEY_FILE" "$SYSADMIN_PRIVATE_KEY_FILE"; do
        if [[ ! -f "$f" ]]; then
            log_err "No s'ha trobat '$f'."
            return 1
        fi
    done
}


# =========================================================
# ISO DESATESA
# =========================================================
# Copia la ISO oficial afegint-hi el preseed, el menú d'arrencada
# automàtic i els fitxers de /vcorp. La ISO oficial no es modifica.

build_preseed_iso() {
    local preseed_file="$1"
    local output_iso="$2"
    local source_iso="${ISO_DIR}/${DEBIAN_ISO_FILENAME}"
    local keys_file key

    keys_file="$(mktemp)" || return 1

    # Clau personal + clau del professor. Es genera a cada execució
    # i no es desa al repositori.
    for key in "$SYSADMIN_PUB_KEY_FILE" "$AUDIT_PUB_KEY_FILE"; do
        cat "$key"
        echo
    done | sed '/^$/d' > "$keys_file"

    log_info "Generant ISO desatesa '$(basename "$output_iso")'"

    rm -f "$output_iso"

    if ! xorriso \
            -indev "$source_iso" \
            -outdev "$output_iso" \
            -map "$preseed_file" /preseed.cfg \
            -map "$TEMPLATE_PRESEED_DIR/isolinux.cfg" /isolinux/isolinux.cfg \
            -map "$TEMPLATE_PRESEED_DIR/late_command.sh" /vcorp/late_command.sh \
            -map "$TEMPLATE_PRESEED_DIR/regen-ssh-host-keys.service" /vcorp/regen-ssh-host-keys.service \
            -map "$keys_file" /vcorp/authorized_keys \
            -boot_image any replay \
            2>"${output_iso}.log"; then
        log_err "xorriso ha fallat (detalls a ${output_iso}.log)."
        rm -f "$keys_file"
        return 1
    fi

    rm -f "$keys_file" "${output_iso}.log"
}


# =========================================================
# CREACIÓ DE LA VM
# =========================================================

create_template_vm() {
    local name="$1"
    local iso="$2"
    local cpus="$3"
    local memory="$4"
    local disk_mb="$5"
    local dir

    log_info "Creant VM '$name' (${cpus} CPU, ${memory} MB RAM, ${disk_mb} MB de disc)"

    "$VBOXMANAGE_BIN" createvm \
        --name "$name" \
        --ostype Debian_64 \
        --register >/dev/null || return 1

    # NIC1 en NAT només durant la instal·lació: la ISO netinst
    # descarrega els paquets d'Internet.
    "$VBOXMANAGE_BIN" modifyvm "$name" \
        --groups "$VM_TEMPLATES_GROUP" \
        --cpus "$cpus" \
        --memory "$memory" \
        --firmware bios \
        --graphicscontroller vmsvga \
        --vram 16 \
        --audio-enabled off \
        --boot1 disk --boot2 dvd --boot3 none --boot4 none \
        --nic1 nat \
        --cableconnected1 on || return 1

    dir="$(vm_dir "$name")"

    "$VBOXMANAGE_BIN" createmedium disk \
        --filename "$dir/$name.vdi" \
        --size "$disk_mb" \
        --format VDI >/dev/null || return 1

    "$VBOXMANAGE_BIN" storagectl "$name" \
        --name "SATA" \
        --add sata \
        --controller IntelAhci \
        --portcount 2 || return 1

    "$VBOXMANAGE_BIN" storageattach "$name" \
        --storagectl "SATA" --port 0 --device 0 \
        --type hdd --medium "$dir/$name.vdi" || return 1

    "$VBOXMANAGE_BIN" storageattach "$name" \
        --storagectl "SATA" --port 1 --device 0 \
        --type dvddrive --medium "$iso" || return 1
}


# =========================================================
# INSTAL·LACIÓ DESATESA
# =========================================================
# El preseed acaba apagant la VM: és el senyal que la instal·lació
# ha acabat.

install_template() {
    local name="$1"
    local iso="$2"
    local elapsed=0
    local interval=20
    local state=""

    log_info "Instal·lació desatesa de '$name' (uns 15 minuts)..."

    "$VBOXMANAGE_BIN" startvm "$name" --type headless >/dev/null || return 1

    while (( elapsed < TEMPLATE_INSTALL_TIMEOUT )); do
        sleep "$interval"
        elapsed=$((elapsed + interval))
        state="$(vm_state "$name")"

        case "$state" in
            poweroff)
                log_ok "Instal·lació de '$name' completada ($((elapsed / 60)) min)"
                break
                ;;
            running)
                if (( elapsed % 120 == 0 )); then
                    log_info "... instal·lant '$name' ($((elapsed / 60)) min)"
                fi
                ;;
            *)
                log_err "Estat inesperat de '$name': $state"
                return 1
                ;;
        esac
    done

    if [[ "$state" != "poweroff" ]]; then
        "$VBOXMANAGE_BIN" controlvm "$name" screenshotpng "${ISO_DIR}/${name}-timeout.png" &>/dev/null
        log_err "Timeout: '$name' no ha acabat en $((TEMPLATE_INSTALL_TIMEOUT / 60)) min."
        log_err "Captura de la pantalla de l'instal·lador: ${ISO_DIR}/${name}-timeout.png"
        return 1
    fi

    # La ISO desatesa ja no cal
    "$VBOXMANAGE_BIN" storageattach "$name" \
        --storagectl "SATA" --port 1 --device 0 \
        --type dvddrive --medium emptydrive || return 1

    "$VBOXMANAGE_BIN" closemedium dvd "$iso" &>/dev/null || true
    rm -f "$iso"
}


# =========================================================
# SEGELLAT DEL TEMPLATE
# =========================================================
# Cap clon ha d'heretar NAT: la NIC1 passa a una xarxa interna
# desconnectada. El snapshot és la base dels clons enllaçats.

seal_template() {
    local name="$1"

    "$VBOXMANAGE_BIN" modifyvm "$name" \
        --nic1 intnet \
        --intnet1 "unused1" \
        --cableconnected1 off || return 1

    "$VBOXMANAGE_BIN" snapshot "$name" take "$TEMPLATE_SNAPSHOT" \
        --description "Base per als clons enllaçats" >/dev/null || return 1

    log_ok "Snapshot '$TEMPLATE_SNAPSHOT' de '$name' creat"
}


# =========================================================
# PROVA AMB UN CLON TEMPORAL
# =========================================================
# El template no es torna a arrencar: es prova un clon enllaçat
# amb NAT temporal i s'esborra sempre en acabar.

run_template_checks() {
    local clone="$1"
    local extra_checks="$2"
    local port="$TEMPLATE_TEST_SSH_PORT"

    "$VBOXMANAGE_BIN" modifyvm "$clone" \
        --nic1 nat \
        --cableconnected1 on \
        --natpf1 "ssh,tcp,127.0.0.1,${port},,22" || return 1

    "$VBOXMANAGE_BIN" startvm "$clone" --type headless >/dev/null || return 1

    wait_ssh 127.0.0.1 "$port" 180 || return 1

    # Les comprovacions s'envien per l'entrada estàndard per evitar
    # problemes de cometes; extra_checks són les pròpies de cada template.
    {
        cat <<'EOF'
echo "--- usuari"; id
echo "--- sudo"; sudo -n true && echo "sudo sense contrasenya: OK"
echo "--- claus autoritzades"
ssh-keygen -lf ~/.ssh/authorized_keys
test "$(wc -l < ~/.ssh/authorized_keys)" -eq 2
echo "--- xarxa"; ip -brief address
EOF
        printf '%s\n' "$extra_checks"
    } | ssh "${SSH_TEST_OPTS[@]}" -p "$port" sysadmin@127.0.0.1 'sh -e' || return 1
}

test_template() {
    local name="$1"
    local extra_checks="$2"
    local clone="${name}-prova"
    local rc=0

    log_info "Provant '$name' amb el clon enllaçat temporal '$clone'"

    "$VBOXMANAGE_BIN" clonevm "$name" \
        --snapshot "$TEMPLATE_SNAPSHOT" \
        --options link \
        --name "$clone" \
        --register >/dev/null || return 1

    run_template_checks "$clone" "$extra_checks" || rc=1

    "$VBOXMANAGE_BIN" controlvm "$clone" poweroff &>/dev/null || true
    sleep 3
    "$VBOXMANAGE_BIN" unregistervm "$clone" --delete &>/dev/null \
        || log_warn "No s'ha pogut esborrar el clon temporal '$clone'."

    if (( rc != 0 )); then
        log_err "La prova del template '$name' ha fallat."
        return 1
    fi

    log_ok "Prova de '$name' correcta: sysadmin, sudo i les 2 claus SSH"
}


# =========================================================
# CREACIÓ COMPLETA D'UN TEMPLATE
# =========================================================
# Ús: create_debian_template <nom> <preseed> <cpus> <memòria_MB> <disc_MB> [comprovacions]

create_debian_template() {
    local name="$1"
    local preseed_file="$2"
    local cpus="$3"
    local memory="$4"
    local disk_mb="$5"
    local extra_checks="${6:-}"
    local iso="${ISO_DIR}/${name}-preseed.iso"

    if vm_exists "$name"; then
        if "$VBOXMANAGE_BIN" snapshot "$name" showvminfo "$TEMPLATE_SNAPSHOT" &>/dev/null; then
            log_warn "El template '$name' ja existeix. S'omet."
            return 0
        fi
        log_err "'$name' existeix però no té el snapshot '$TEMPLATE_SNAPSHOT' (creació incompleta)."
        log_err "Esborreu-lo i torneu-ho a provar: VBoxManage unregistervm '$name' --delete"
        return 1
    fi

    download_iso "$DEBIAN_ISO_URL" "$DEBIAN_ISO_FILENAME" "$DEBIAN_ISO_SHA256" || return 1
    build_preseed_iso "$preseed_file" "$iso" || return 1
    create_template_vm "$name" "$iso" "$cpus" "$memory" "$disk_mb" || return 1
    install_template "$name" "$iso" || return 1
    seal_template "$name" || return 1
    test_template "$name" "$extra_checks" || return 1

    log_ok "Template '$name' creat i verificat"
}
