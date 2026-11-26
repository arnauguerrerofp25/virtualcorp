terraform {
  required_version = ">= 1.6"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.112.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure
}

# Contenidor del servei Kea DHCPv4 (activitat 4)
resource "proxmox_virtual_environment_container" "dhcp01" {
  node_name     = var.proxmox_node
  vm_id         = var.dhcp01.vm_id
  description   = "Kea DHCPv4 de la delegació 09. Gestionat per Terraform."
  tags          = ["terraform", "dhcp"]
  unprivileged  = true
  start_on_boot = true
  started       = true

  # Debian 13 i systemd necessiten nesting en un contenidor sense privilegis.
  # No s'activa cap altra funció privilegiada.
  features {
    nesting = true
  }

  operating_system {
    template_file_id = var.lxc_template
    type             = "debian"
  }

  cpu {
    cores = var.dhcp01.cores
  }

  memory {
    dedicated = var.dhcp01.memory
  }

  disk {
    datastore_id = var.dhcp01.datastore
    size         = var.dhcp01.disk_gb
  }

  network_interface {
    name   = "eth0"
    bridge = var.dhcp01.bridge
  }

  initialization {
    hostname = var.dhcp01.hostname

    ip_config {
      ipv4 {
        address = var.dhcp01.address
        gateway = var.dhcp01.gateway
      }
    }

    dns {
      domain  = var.dns_domain
      servers = [var.dhcp01.dns]
    }

    user_account {
      keys = [for f in var.ssh_public_key_files : trimspace(file(f))]
    }
  }
}
