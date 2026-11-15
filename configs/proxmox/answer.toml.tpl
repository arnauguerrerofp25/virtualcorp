# =========================================================
# Answer file: instal·lació desatesa de pve01 (Proxmox VE)
# =========================================================
# Plantilla: deploy_equipment substitueix els marcadors ROOT_PASSWORD_HASH
# (contrasenya aleatòria, fora del repositori) i ROOT_SSH_KEYS (claus de
# configs/ssh/), escrits entre arroves.

[global]
keyboard = "es"
country = "es"
fqdn = "pve01.virtualcorp.lan"
mailto = "sysadmin@virtualcorp.lan"
timezone = "Europe/Madrid"
root-password-hashed = "@ROOT_PASSWORD_HASH@"
root-ssh-keys = [
@ROOT_SSH_KEYS@
]
reboot-mode = "power-off"

# IP fixa a la zona privada; passarel·la: mikrotik0
[network]
source = "from-answer"
cidr = "10.9.0.133/26"
dns = "1.1.1.1"
gateway = "10.9.0.129"
filter.ID_NET_NAME_MAC = "*"

# ext4 sobre LVM, amb emmagatzematge LVM-thin (local-lvm). Sense ZFS.
[disk-setup]
filesystem = "ext4"
disk-list = ["sda"]
