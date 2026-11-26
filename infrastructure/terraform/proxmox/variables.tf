variable "proxmox_endpoint" {
  description = "URL de l'API de Proxmox (a través del túnel WireGuard)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Token API de terraform@pve (format usuari!id=secret). Es passa per terraform.local.tfvars o TF_VAR_proxmox_api_token"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Acceptar el certificat autosignat de pve01 (laboratori)"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Node de Proxmox on es creen els contenidors"
  type        = string
  default     = "pve01"
}

variable "lxc_template" {
  description = "Plantilla LXC carregada al node (pveam download local ...)"
  type        = string
  default     = "local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
}

variable "ssh_public_key_files" {
  description = "Claus públiques d'administració autoritzades a root: personal (sysadmin) i professor (auditor)"
  type        = list(string)
  default = [
    "../../../configs/ssh/vcorp_sysadmin.pub",
    "../../../configs/ssh/vcorp_auditor.pub",
  ]
}

variable "dns_domain" {
  description = "Domini de cerca dels contenidors"
  type        = string
  default     = "virtualcorp.lan"
}

variable "dhcp01" {
  description = "Contenidor del servei Kea DHCP: identificador, adreçament i recursos"
  type = object({
    vm_id     = number
    hostname  = string
    address   = string
    gateway   = string
    dns       = string
    bridge    = string
    datastore = string
    cores     = number
    memory    = number
    disk_gb   = number
  })
  default = {
    vm_id     = 201
    hostname  = "dhcp01"
    address   = "10.9.0.136/26" # zona privada; fixa per arrencar abans del DHCP
    gateway   = "10.9.0.129"    # mikrotik0
    dns       = "8.8.8.8"       # provisional fins a dns01 (10.9.0.137)
    bridge    = "vmbr0"         # bridge de pve01 connectat a la xarxa interna 'privada'
    datastore = "local-lvm"     # LVM-thin
    cores     = 1
    memory    = 512
    disk_gb   = 6
  }
}
