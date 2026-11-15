# Activitat 2 — Templates Debian, desplegament d'equips i Proxmox VE

**Delegació:** 09 · **Rang assignat:** `10.9.0.0/16` · **Responsable:** Arnau Guerrero Asensio

**Entorn:** Debian 13 (kernel 6.12) · VirtualBox 7.2.20 · 18 fils de CPU · 30 GB de RAM · Debian 13.7.0 · Proxmox VE 9.2-1

## 1. Objectiu i abast

En aquesta activitat es construeix la resta de la infraestructura de la delegació a partir dels routers de l'activitat 1:

- Dos **templates Debian** reutilitzables (Server i Desktop), creats amb instal·lació desatesa: `make create_templates`.
- Els **servidors, impressores i equips d'escriptori** de la delegació, desplegats com a clons enllaçats dels templates, i el servidor **pve01** amb Proxmox VE i virtualització anidada: `make deploy_equipment`.

Encara no hi ha serveis DHCP ni DNS. Totes les màquines (excepte pve01) queden configurades per obtenir la IP per DHCP quan aquests serveis existeixin.

## 2. Disseny de xarxa actualitzat

### 2.1. Xarxes internes de VirtualBox

Tots els segments són xarxes internes de VirtualBox amb els noms exactes que fixa l'enunciat. L'única interfície en mode NAT de tota la infraestructura és la NIC1 de `mikrotik0` (router0), que és la sortida a Internet.

| Xarxa interna | Subxarxa | Passarel·la | Router |
|---|---|---|---|
| `rt0_1` | `10.9.0.224/30` | — | mikrotik0 `.225` · mikrotik1 `.226` |
| `rt1_2` | `10.9.0.228/30` | — | mikrotik1 `.229` · mikrotik2 `.230` |
| `rt2_3` | `10.9.0.232/30` | — | mikrotik2 `.233` · mikrotik3 `.234` |
| `privada` | `10.9.0.128/26` | `10.9.0.129` | mikrotik0 |
| `dmz` | `10.9.0.192/27` | `10.9.0.193` | mikrotik0 |
| `pl0` | `10.9.0.0/25` | `10.9.0.1` | mikrotik1 |
| `pl1` | `10.9.1.0/24` | `10.9.1.1` | mikrotik2 |
| `pl2` | `10.9.2.0/24` | `10.9.2.1` | mikrotik2 |
| `pl3` | `10.9.3.0/25` | `10.9.3.1` | mikrotik3 |
| `pl3_direccio` | `10.9.3.128/25` | `10.9.3.129` | mikrotik3 |

Encaminament: RIP entre els quatre routers. `mikrotik0` fa NAT (masquerade) cap a Internet per la NIC1.

### 2.2. Inventari d'equips

| Màquina | Base | Xarxa | IP prevista | vCPU | RAM | Rol |
|---|---|---|---|---|---|---|
| pve01 | ISO Proxmox | `privada` | **10.9.0.133 (fixa)** | 4 | 8192 MB | Node Proxmox VE del CPD |
| dbsrv | Server | `privada` | 10.9.0.134 | 1 | 512 MB | Bases de dades |
| infosrv | Server | `privada` | 10.9.0.135 | 1 | 512 MB | Fitxers i documentació |
| websrv | Server | `dmz` | 10.9.0.197 | 1 | 512 MB | Web pública |
| printer0 | Server | `pl0` | 10.9.0.65 | 1 | 512 MB | Impressió, planta baixa |
| printer1 | Server | `pl1` | 10.9.1.65 | 1 | 512 MB | Impressió, planta 1 |
| printer2 | Server | `pl2` | 10.9.2.65 | 1 | 512 MB | Impressió, planta 2 |
| printer3 | Server | `pl3` | 10.9.3.65 | 1 | 512 MB | Impressió, planta 3 |
| expo1–expo4 | Desktop | `pl0` | 10.9.0.33–.36 | 1 | 768 MB | Expositors |
| conserge1–conserge2 | Desktop | `pl0` | 10.9.0.37–.38 | 1 | 768 MB | Consergeria |
| pl1-pc01 | Desktop | `pl1` | dinàmica | 1 | 768 MB | Desenvolupament, planta 1 |
| pl2-pc01 | Desktop | `pl2` | dinàmica | 1 | 768 MB | Desenvolupament, planta 2 |
| pl3-pc01 | Desktop | `pl3` | dinàmica | 1 | 768 MB | Departaments, planta 3 |
| dir-pc01 | Desktop | `pl3_direccio` | dinàmica | 1 | 768 MB | Direcció (xarxa aïllada) |

La columna «IP prevista» és la reserva que es configurarà al servei DHCP. Ara totes les màquines (excepte pve01) usen DHCP. L'inventari dels equips basats en templates és a `configs/equipment.csv`.

**Dimensionament:** amb tota la infraestructura engegada (routers, pve01 i els 17 clons) es fan servir uns 20 GB de RAM dels 30 GB de l'amfitrió, i en queden prou per al sistema. Els clons enllaçats ocupen entre 28 i 40 MB de disc cadascun.

### 2.3. Decisions de disseny

- **Zona privada a mikrotik0.** pve01 necessita una passarel·la a `10.9.0.128/26`. S'ha posat a mikrotik0, el router de sortida, que ja té la DMZ: queda un esquema de tres zones (WAN, DMZ i privada) a la planta baixa, on hi ha el CPD.
- **Noms dels routers.** L'enunciat els anomena `router0`–`router3`; l'script del professor, `mikrotik0`–`mikrotik3`. S'han mantingut els noms de l'script per no modificar-lo ni trencar l'accés SSH configurat. `mikrotik0` és el router0.
- **Planta 3.** Es divideix en `pl3` (`10.9.3.0/25`, departaments) i `pl3_direccio` (`10.9.3.128/25`, direcció aïllada), com fa l'script del professor i com indicava l'enunciat d'anys anteriors.
- **Dotació de servidors.** Els dos servidors «orientats a processos» de la dotació són websrv (DMZ) i pve01 (zona privada). Amb dbsrv i infosrv quadren amb les quatre IP reservades del CPD.
- **Un equip per segment.** Els usuaris de les plantes 1 a 3 treballen amb portàtils i IP dinàmica. Es desplega un equip representatiu per segment (i un de direcció). Se n'afegeixen més amb una línia a `configs/equipment.csv`.
- **Servidors de projecte.** Els 6 servidors (web i dades de 3 projectes) no es despleguen a VirtualBox: s'allotjaran a pve01, que és el node de virtualització del CPD.
- **Servidors de l'enunciat antic.** `intrasrv`, `filesrv` i `datasrv` tenien les IP `.133`–`.135`, que ara corresponen a pve01, dbsrv i infosrv. `coresrv` (`.198`) i `streamingsrv` (`.199`) no formen part de la dotació actual: DNS, DHCP i streaming es decidiran a les activitats de serveis. Les adreces `.198` i `.199` de la DMZ queden reservades.
- **IP de consergeria.** L'enunciat no les fixa. S'han reservat `10.9.0.37` i `10.9.0.38`, al costat dels expositors.

## 3. Versions fixades

Les versions, els noms de fitxer, les URL i els SHA256 són a **`configs/iso_versions.conf`**, que carrega `infrastructure/bash/common.sh`. Són assignacions fixes: cap variable d'entorn ni el `.env` les pot canviar.

| Imatge | Fitxer | URL | SHA256 |
|---|---|---|---|
| Debian 13.7.0 amd64 | `debian-13.7.0-amd64-netinst.iso` | `https://cdimage.debian.org/debian-cd/13.7.0/amd64/iso-cd/` | `a7ef94ac…6167e355` |
| Proxmox VE 9.2-1 | `proxmox-ve_9.2-1.iso` | `http://download.proxmox.com/iso/` | `4e88fe41…3ef2c6c` |
| Eina d'instal·lació desatesa de Proxmox 9.2.8 | `proxmox-auto-install-assistant_9.2.8_amd64.deb` | repositori oficial `pve-no-subscription` (trixie) | `94b562ac…0bcbdc2e2` |

La funció `download_iso` (`common.sh`) descarrega cada fitxer a `artifacts/images/iso/` (ignorat per Git), en verifica el SHA256 i atura el procés si no coincideix o si la URL falla. Mai busca una altra versió ni una altra URL.

**Actualització controlada** (apartat 3.2): branca pròpia → modificar versió i SHA256 a `configs/iso_versions.conf` → provar `make create_templates` i `make deploy_equipment` → verificar → fusionar a `main`.

## 4. Templates Debian

### 4.1. Procediment (`make create_templates`)

Implementat a `infrastructure/bash/template_base.sh` i `create_templates.sh`:

1. Es descarrega i verifica la ISO de Debian.
2. Amb `xorriso` es genera una còpia de la ISO amb el fitxer de respostes (preseed), un menú d'arrencada automàtic i els fitxers de `/vcorp` (claus SSH i scripts). La ISO oficial no es modifica.
3. Es crea la VM al grup `/VirtualCorp/templates` amb la NIC1 en NAT, només durant la instal·lació (la ISO netinst descarrega paquets d'Internet).
4. La instal·lació és completament desatesa. El preseed acaba apagant la VM, que és el senyal de final.
5. **Segellat:** la NIC1 passa a xarxa interna desconnectada (cap clon hereta NAT) i es crea el snapshot `base`, origen dels clons enllaçats.
6. **Prova:** es crea un clon enllaçat temporal amb NAT, s'hi entra per SSH amb la clau personal i es comproven l'usuari, sudo, les 2 claus, la IP per DHCP i els components. El clon s'esborra sempre.

Si un template ja existeix amb el snapshot `base`, s'omet.

### 4.2. Característiques

| | tpl-debian-server | tpl-debian-desktop |
|---|---|---|
| Ús | Servidors del CPD, DMZ i impressores | Usuaris, consergeria i expositors |
| Preseed | `configs/preseed/debian-server.cfg` | `configs/preseed/debian-desktop.cfg` |
| Paquets | Base + `ssh-server` + `sudo` | El mateix + `lxqt-core`, `sddm`, `sddm-theme-debian-maui`, `libpam-systemd`, `xserver-xorg`, `falkon` |
| Sense | Entorn gràfic | Firefox, LibreOffice ni altres aplicacions |
| Arrencada | Consola (no hi ha cap gestor gràfic) | `graphical.target` (SDDM) |
| Recursos del template | 1 vCPU, 1024 MB, 10 GB | 2 vCPU, 2048 MB, 16 GB |

Comú als dos:

- **Xarxa:** DHCP a la primera interfície.
- **Usuari `sysadmin`:** contrasenya bloquejada (només clau SSH), `sudo` sense contrasenya, root desactivat.
- **Claus SSH autoritzades:** la personal (`configs/ssh/vcorp_sysadmin.pub`) i la del professor (`configs/ssh/vcorp_auditor.pub`), instal·lades pel `late_command` durant la instal·lació.
- **Preparació per clonar:** es buida `/etc/machine-id` i s'esborren les claus de host SSH. La unitat `regen-ssh-host-keys.service` les regenera a la primera arrencada de cada clon.
- Idioma `ca_ES.UTF-8`, teclat `es`, zona horària `Europe/Madrid`, disc ext4.

L'entorn gràfic s'instal·la **sense paquets recomanats**: amb els recomanats, `lxqt` arrossega part de KDE Plasma (uns 1650 paquets). Sense, en són uns 400.

## 5. Desplegament d'equips (`make deploy_equipment`)

Implementat a `infrastructure/bash/deploy_equipment.sh`, `equipment_base.sh` i `proxmox_base.sh`:

1. Es llegeix `configs/equipment.csv` i, per a cada línia, es crea un **clon enllaçat** (`clonevm --options link`) del snapshot `base` del template indicat.
2. A cada clon s'assignen CPU, RAM, grup de VirtualBox (`Servidors`, `Impressores` o `Escriptori`) i una única interfície a la seva xarxa interna. La IP prevista i el rol queden a la descripció de la VM.
3. **Prova d'arrencada:** s'engeguen tots els clons, s'espera 90 s i es prem el botó d'apagada ACPI. Una màquina només s'apaga sola si el sistema operatiu ha arrencat. En acabar, queden apagades.
4. S'instal·la pve01 (apartat 6).

Les màquines que ja existeixen s'ometen, de manera que el target es pot tornar a executar.

## 6. pve01 (Proxmox VE)

### 6.1. Instal·lació desatesa

pve01 no parteix de cap template. Es fa servir el mecanisme oficial de Proxmox VE:

1. Es descarrega i verifica la ISO de Proxmox i l'eina `proxmox-auto-install-assistant`, que s'extreu a `artifacts/tools/` sense instal·lar res al sistema.
2. A partir de la plantilla `configs/proxmox/answer.toml.tpl` es genera l'answer file real amb:
   - una **contrasenya de root aleatòria**, que només es desa a l'equip local (`~/.config/virtualcorp/pve01-root-password`, permisos 600). Mai va al repositori. Cal per a la interfície web.
   - les **claus SSH** personal i del professor a `root-ssh-keys`.
3. L'eina valida l'answer file (`validate-answer`) i l'integra a la ISO (`prepare-iso --fetch-from iso`).
4. Es crea la VM, s'instal·la sense intervenció i s'apaga en acabar (`reboot-mode = "power-off"`).

Paràmetres de l'answer file: FQDN `pve01.virtualcorp.lan`, IP `10.9.0.133/26`, passarel·la `10.9.0.129`, DNS `1.1.1.1` (provisional fins que hi hagi DNS a la delegació), sistema de fitxers ext4.

### 6.2. Recursos i virtualització anidada

| Paràmetre | Valor |
|---|---|
| vCPU | 4 |
| RAM | 8192 MB |
| Disc | 64 GB (dinàmic) |
| Xarxa | NIC1 a `privada`, sense NAT (bridge `vmbr0` a Proxmox) |
| Virtualització anidada | `--nested-hw-virt on`, aplicat per l'script abans de la primera arrencada |
| Emmagatzematge | `local` (directori) i `local-lvm` (**LVM-thin**). Sense ZFS |

L'amfitrió té VT-x activat i cap mòdul KVM carregat (VirtualBox el necessita en exclusiva).

### 6.3. Accés administratiu

- **SSH:** `root` amb la clau personal o la del professor. pve01 no té NAT: s'hi arriba fent salt per `mikrotik0`, que té `forwarding-enabled=local`.

  ```bash
  # Alumne (clau vcorp_sysadmin; salt amb l'usuari sysadmin dels routers)
  ssh -J sysadmin@127.0.0.1:2200 root@10.9.0.133
  # Professor (clau vcorp_auditor; salt amb l'usuari auditor dels routers)
  ssh -J auditor@127.0.0.1:2200 root@10.9.0.133
  ```

  `-J` no aplica l'opció `-i` al salt: si la clau no és la predeterminada, cal tenir-la carregada a `ssh-agent` o definida a `~/.ssh/config`.

- **Web:** `https://10.9.0.133:8006`, usuari `root`, amb la contrasenya del fitxer local. Cal una ruta o un túnel SSH a través de mikrotik0.

## 7. Targets del Makefile

| Target | Què fa | Requisits previs |
|---|---|---|
| `make create_templates` | Descarrega la ISO de Debian, crea i prova `tpl-debian-server` i `tpl-debian-desktop` | VirtualBox, `xorriso`, claus de `make ssh-keys` |
| `make deploy_equipment` | Crea els 17 clons de l'inventari, en prova l'arrencada i instal·la i verifica pve01 | Templates creats; routers desplegats (si estan aturats, s'engeguen per verificar pve01) |

Ordre per reproduir el desplegament des de zero:

```bash
cp .env.example .env
make ssh-keys
make deploy-routers
make create_templates
make deploy_equipment
```

## 8. Validació

Les evidències completes són a `docs/evidencies/`: `act2-templates.txt`, `act2-desplegament.txt` i `act2-validacio.txt`.

| Comprovació (apartat 8) | Resultat |
|---|---|
| Templates creats amb els components previstos | ✅ Server sense entorn gràfic. Desktop amb `lxqt-core 33.2`, `sddm`, `falkon 25.04.1`, sense Firefox ni LibreOffice, arrencada gràfica |
| Totes les màquines existeixen amb el nom i el rol correctes | ✅ 17/17 coincideixen amb `configs/equipment.csv` (nom, grup, xarxa, CPU, RAM), més pve01 |
| Clonació enllaçada | ✅ Els 17 clons tenen un disc diferencial (28–40 MB) sobre el disc del seu template |
| Xarxes i NAT | ✅ Cada interfície és a la xarxa interna prevista. Només `mikrotik0` té una interfície NAT |
| Arrencada | ✅ Els 17 clons arrenquen i responen a l'apagada ACPI |
| Instal·lació desatesa | ✅ Cap intervenció manual en templates ni en pve01 |
| Accés SSH | ✅ `sysadmin` amb les 2 claus als templates (heretades pels clons). `root` amb les 2 claus a pve01 |
| pve01 | ✅ Proxmox VE 9.2.2, `10.9.0.133/26` a `vmbr0`, passarel·la `10.9.0.129` |
| Virtualització anidada | ✅ `/dev/kvm` present, extensions `vmx` visibles i mòdul `kvm_intel` carregat dins de pve01 |
| Connectivitat de pve01 | ✅ Ping als 4 routers (`.129`, `.226`, `.230`, `.234`) i a `1.1.1.1` |

Les claus dels clons no es poden comprovar entrant-hi, perquè sense DHCP no tenen IP. L'evidència és la prova de cada template i el fet que els clons enllaçats comparteixen el seu disc.

## 9. Incidències i solucions

1. **Certificat TLS de `download.proxmox.com`.** El servidor presenta un certificat del CDN de Proxmox que no inclou aquest nom. No s'ha desactivat la verificació TLS ni s'ha canviat de versió: s'ha comprovat que el mateix servidor oficial serveix la ISO per HTTP i s'ha canviat l'esquema de la URL de manera conscient. La integritat la garanteix el SHA256 fixat, obtingut per TLS al CDN i a la pàgina oficial.
2. **Instal·lació del template Desktop bloquejada.** El primer intent es va aturar sense trànsit de xarxa ni ús de CPU. A la consola de l'instal·lador es va veure que `apt-get` (del `late_command`) tenia actiu el mètode `cdrom` i esperava que s'inserís el CD: l'instal·lador desactiva la font `cdrom` *després* del `late_command`. Solució: desactivar-la abans d'instal·lar l'entorn gràfic.
3. **Validació de l'answer file.** `proxmox-auto-install-assistant validate-answer` retorna el codi 0 fins i tot quan el fitxer és invàlid. L'script comprova el missatge d'èxit en lloc del codi de sortida. Es va detectar amb una prova en sec abans de la primera instal·lació.
4. **Comentari de la plantilla de pve01.** La capçalera de la plantilla esmentava els marcadors literals i l'script també els substituïa dins del comentari, cosa que trencava el TOML. Es va corregir el comentari.
5. **Nom de la clau del professor.** L'enunciat diu `configs/ssh/vcorp-auditor.pub` (amb guió) i el repositori té `vcorp_auditor.pub` (amb guió baix). S'ha fet servir el fitxer existent sense reanomenar-lo, perquè la clau del professor no s'ha de modificar.
6. **Errors transitoris de VBoxManage.** Durant la prova d'arrencada, consultar l'estat d'una VM mentre canviava d'estat mostrava errors («The object is not ready») sense efecte. S'han ocultat a la funció `vm_state`.
7. **Redesplegament dels routers.** Els noms de les xarxes internes de l'activitat 1 (`r0-r1`, `pl3-direccio`…) no coincidien amb els exigits (`rt0_1`, `pl3_direccio`…) i faltava la zona privada. Es van canviar a `deploy_routers.sh` i es van redesplegar els routers amb `make reset-routers`.

## 10. Pendent per a properes activitats

- **DHCP i DNS:** configurar les reserves de la taula de l'apartat 2.2 i substituir el DNS provisional de pve01.
- **Hostname dels clons:** tots els clons tenen el hostname del seu template (`debian-server` o `debian-desktop`). El nom de la VM sí que és el definitiu. S'assignarà amb el DHCP/DNS o en la configuració de cada servei.
- **Servidors de projecte:** desplegar-los a pve01.
- **Consergeria:** l'enunciat general indica equips Windows, però aquesta activitat els demana amb el template Desktop. S'ha seguit l'activitat.
