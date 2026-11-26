# Activitat 4 — Servei DHCP (Terraform, Kea i relays RouterOS)

**Delegació:** 09 · **Rang:** `10.9.0.0/16` · **Node de control:** portàtil de l'alumne (Debian 13)

Servei DHCP centralitzat de la delegació 09. **Terraform** (apartats 1–6, `infrastructure/terraform/proxmox/`) crea el contenidor LXC `dhcp01` a Proxmox, amb la xarxa i l'accés inicial. **Ansible** (apartats 7–11, `automation/ansible/`) hi instal·la i configura Kea DHCPv4 i configura els relays DHCP dels routers.

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

## Part Ansible: Kea i relays

Ansible instal·la Kea DHCPv4 a `dhcp01` (10.9.0.136, creat amb Terraform als apartats 1–6) i configura un relay DHCP a cada interfície de router connectada a una LAN amb clients. Les ordres s'executen des de `automation/ansible`:

```bash
ansible-galaxy collection install -r requirements.yml
ansible-inventory --graph
ansible-playbook --syntax-check playbooks/configure_dhcp_dns.yml
ansible-playbook playbooks/configure_dhcp_dns.yml
```

O, des de l'arrel del repositori, `make deploy_dhcp` (Terraform + aquest playbook).

## 7. Pla d'adreçament i àmbits

- **`configs/address-plan.tsv`** és la font única de les IP i MAC dels equips (tipus `fixa`, `reserva` o `dinamica`). Les MAC són les de VirtualBox i, per a `dhcp01`, la que assigna Proxmox.
- **`inventories/group_vars/dhcp/kea.yml`** conté els àmbits: xarxa, passarel·la i pool. Les reserves no es repeteixen aquí.
- IP fixes, sense DHCP: `pve01` .133, `dhcp01` .136 i el futur `dns01` .137.
- Opcions per a tots els àmbits: DNS `10.9.0.137` (dns01, activitat següent) i domini `virtualcorp.lan`. Lease de 3600 s.

| Àmbit | Xarxa | Passarel·la | Pool | Reserves |
|---|---|---|---|---|
| dmz | 10.9.0.192/27 | .193 | .210 – .222 | websrv .197 |
| privada | 10.9.0.128/26 | .129 | .160 – .190 | dbsrv .134, infosrv .135 |
| planta00 | 10.9.0.0/25 | .1 | .100 – .126 | printer0 .65, expo1–4 .33–.36, conserge1–2 .37–.38 |
| planta01 | 10.9.1.0/24 | .1 | .100 – .250 | printer1 .65 |
| planta02 | 10.9.2.0/24 | .1 | .100 – .250 | printer2 .65 |
| planta03 | 10.9.3.0/25 | .1 | .70 – .126 | printer3 .65 |
| direccio | 10.9.3.128/25 | .129 | .140 – .150 | — |

Sense DHCP: enllaços entre routers (`rt*`), túnel WireGuard i NAT de VirtualBox.

## 8. Rol `kea_dhcp`

1. Instal·la `kea-dhcp4-server` (2.6.3, paquets de Debian 13).
2. Llegeix les reserves del TSV al node de control (filtre `community.general.from_csv`).
3. Comprova, abans de configurar res, que hi ha reserves, que no hi ha IP ni MAC repetides i que cada reserva és dins de la seva xarxa i fora del pool (`ansible.utils.ipaddr`).
4. Genera `/etc/kea/kea-dhcp4.conf` amb `validate: kea-dhcp4 -t %s`: un fitxer invàlid no substitueix mai el que hi ha en servei.
5. Kea escolta explícitament a `eth0`. El handler només el reinicia si la configuració ha canviat.
6. Habilita i inicia `kea-dhcp4-server`.

## 9. Rol `dhcp_relay` (grup `routeros`)

Per a cada relay de `host_vars/<router>.yml` llegeix l'estat actual (`interface|dhcp-server|local-address|disabled`) i només escriu si cal: `add` si no existeix, `set ... disabled=no` si té valors diferents o està desactivat. Un relay correcte i actiu no es toca. Servidor comú: `dhcp_relay_server: 10.9.0.136`.

| Router | Relay | Interfície | `local-address` |
|---|---|---|---|
| mikrotik0 | vcorp-dmz · vcorp-privada | ether3 · ether4 | 10.9.0.193 · 10.9.0.129 |
| mikrotik1 | vcorp-planta00 | ether4 | 10.9.0.1 |
| mikrotik2 | vcorp-planta01 · vcorp-planta02 | ether4 · ether5 | 10.9.1.1 · 10.9.2.1 |
| mikrotik3 | vcorp-planta03 · vcorp-direccio | ether3 · ether4 | 10.9.3.1 · 10.9.3.129 |

Propietats comprovades a RouterOS 7.21.4 amb `/console/inspect`. `mikrotik1`–`mikrotik3` s'administren a través del túnel WireGuard (enllaços `10.9.0.224/28` autoritzats). Les seves claus de host es van afegir a `~/.ssh/known_hosts` després de comparar-les amb les ja acceptades. Kea respon als relays per la ruta per defecte de `dhcp01` (mikrotik0) i RIP.

## 10. Proves (activitat 4)

| Prova | Resultat |
|---|---|
| Kea | `active` i `enabled`, escolta a `eth0:67`, 7 àmbits i 13 reserves, sense errors al log |
| Playbook repetit | 2a execució: `changed=0` a `dhcp01` i als 4 routers |
| Relays | 7 relays actius cap a `10.9.0.136`. Un relay desactivat i un altre amb `local-address` incorrecta es corregeixen sense tocar la resta |
| Clients amb reserva | websrv .197, dbsrv .134, printer0 .65; websrv manté la .197 després de reiniciar |
| Clients del pool | pl1-pc01 10.9.1.100, pl2-pc01 10.9.2.100, pl3-pc01 10.9.3.70, dir-pc01 10.9.3.140 i clons temporals a dmz (.210), privada (.160) i planta00 (.100) |
| Opcions | Tots els clients reben la passarel·la del seu segment, DNS `10.9.0.137` i domini `virtualcorp.lan` |
| `make deploy_dhcp` | Sobre el desplegament existent: Terraform «No changes» i Ansible `changed=0` |

Les proves es van fer amb un client cada vegada, aturat abans del següent. Evidències: `docs/evidencies/act4-*.txt`.

## 11. Incidències (activitat 4)

- **Reserves buides a la primera execució:** la lectura del TSV era en un escalar YAML plegat (`>-`), on `'\n'` no és un salt de línia. Tot el fitxer quedava en una sola fila i Kea es va configurar sense reserves. Es va corregir amb un escalar entre cometes dobles i una comprovació que atura el rol si no hi ha cap reserva.
- **Avisos `WARN` de Kea:** el mode multifil de Kea 2.6 desactiva el control de cua i consulta primer les reserves. Són informatius.
- **Hostname dels clons:** Kea registra el nom de les reserves al lease, però dins dels clons el hostname continua sent el del template. Queda pendent per a l'activitat de DNS.
- **Descàrrega lenta de la plantilla LXC** (~120 KB/s): es va reiniciar la descàrrega i `pveam` en va verificar la suma.
