# Terraform · Proxmox VE (activitat 4)

Declara el contenidor LXC `dhcp01`, que executa el servei Kea DHCPv4 de la delegació 09. Terraform crea el contenidor, la xarxa i l'accés inicial; Ansible hi instal·la i configura Kea (vegeu `automation/ansible/README.md`).

| Eina | Versió |
|---|---|
| Terraform | 1.17.2 (repositori APT oficial de HashiCorp) |
| Proveïdor | `bpg/proxmox` 0.112.0 (`~> 0.112.0`, fixat a `.terraform.lock.hcl`) |
| Proxmox VE | 9.2.2 (`pve01`, 10.9.0.133) |

## 1. Fitxers

| Fitxer | Contingut | A Git |
|---|---|---|
| `main.tf` | Proveïdor i recurs `proxmox_virtual_environment_container.dhcp01` | Sí |
| `variables.tf` | Endpoint, token, node, plantilla, claus SSH i dades de `dhcp01` | Sí |
| `.terraform.lock.hcl` | Versió i sumes del proveïdor | Sí |
| `terraform.local.tfvars` | Endpoint i **token** (permisos 600) | **No** (`*.tfvars`) |
| `.terraform/`, `terraform.tfstate*`, `*.tfplan` | Connectors, estat i plans desats | **No** |

L'estat (`terraform.tfstate`) és local i pot contenir dades sensibles: no es publica. Si cal, se'n fa una còpia de seguretat fora del repositori.

## 2. Credencials a Proxmox

Terraform accedeix a l'API de `pve01` a través del túnel WireGuard (la zona privada és una xarxa autoritzada). Usuari i token dedicats, amb un rol de permisos mínims (executat a `pve01` com a root):

```bash
pveum role add TerraformCT -privs "VM.Allocate VM.Audit VM.Config.CPU VM.Config.Disk VM.Config.Memory VM.Config.Network VM.Config.Options VM.PowerMgmt Datastore.AllocateSpace Datastore.Audit Sys.Audit SDN.Use"
pveum user add terraform@pve --comment "Terraform (VirtualCorp)"
pveum aclmod / -user terraform@pve -role TerraformCT
pveum user token add terraform@pve tf --privsep 0
```

- El rol només permet consultar el node i crear, configurar, iniciar i esborrar contenidors al seu emmagatzematge. No inclou usuaris, sistema ni còpies.
- No inclou `Datastore.AllocateTemplate`: la plantilla es descarrega amb `pveam` i Terraform només la fa servir.
- `--privsep 0`: el token té els permisos de l'usuari, ja limitats pel rol.

El secret del token només es mostra en crear-lo. Es desa a `terraform.local.tfvars`:

```hcl
proxmox_endpoint  = "https://10.9.0.133:8006/"
proxmox_api_token = "terraform@pve!tf=<secret>"
```

```bash
chmod 600 terraform.local.tfvars
```

Alternativa: variables d'entorn `TF_VAR_proxmox_endpoint` i `TF_VAR_proxmox_api_token`. El certificat de `pve01` és autosignat; per al laboratori `proxmox_insecure = true`.

## 3. Plantilla LXC

A `pve01` (emmagatzematge `local`, que admet el contingut `vztmpl`):

```bash
pveam update
pveam available --section system | grep debian-13
pveam download local debian-13-standard_13.6-1_amd64.tar.zst
```

`pveam` verifica la suma de comprovació en acabar la descàrrega.

## 4. Contenidor `dhcp01`

| Paràmetre | Valor |
|---|---|
| ID | 201 |
| Hostname | `dhcp01` |
| Plantilla | `local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst` |
| Tipus | Sense privilegis (`unprivileged = true`) |
| Funcions | Només `nesting = true` (necessari per a systemd de Debian 13) |
| Recursos | 1 core · 512 MB · 6 GB a `local-lvm` (LVM-thin) |
| Xarxa | `eth0` a `vmbr0` (xarxa interna `privada`) · `10.9.0.136/26` · passarel·la `10.9.0.129` |
| DNS | `8.8.8.8` provisional · domini `virtualcorp.lan` |
| Arrencada | Automàtica amb Proxmox (`start_on_boot = true`) |
| Accés | `root` amb les claus `configs/ssh/vcorp_sysadmin.pub` i `vcorp_auditor.pub` |

Totes aquestes dades són a la variable `dhcp01` de `variables.tf`.

## 5. Cicle de treball

```bash
cd infrastructure/terraform/proxmox
terraform init
terraform fmt -recursive
terraform validate
terraform plan  -var-file=terraform.local.tfvars
terraform apply -var-file=terraform.local.tfvars
```

`make deploy_dhcp` (arrel del repositori) fa el mateix de manera no interactiva: `plan -out` i `apply` d'aquest pla, i després esborra el pla desat.

**Verificació:**

```bash
ssh root@10.9.0.136 'hostname; ip -brief address show eth0'
terraform plan -var-file=terraform.local.tfvars   # ha de dir "No changes"
```

`terraform destroy` esborra el contenidor: no l'executeu sense revisar-ne el pla.

## 6. Incidència: xarxa del contenidor

Després del primer `apply`, `dhcp01` arribava a `pve01` però no a la passarel·la. El contenidor surt pel bridge de Proxmox amb **la seva pròpia MAC**, i VirtualBox descarta les trames d'una NIC amb una MAC diferent si no està en mode promiscu. Solució: `--nicpromisc1 allow-all` a la NIC de `pve01` (afegit a `infrastructure/bash/proxmox_base.sh`). La política només s'aplica quan la VM arrenca: va caldre reiniciar `pve01`. `dhcp01` va tornar a arrencar sol (`start_on_boot`) i el segon `terraform plan` va mostrar **No changes**.
