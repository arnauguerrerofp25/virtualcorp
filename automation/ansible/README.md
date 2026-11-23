# Activitat 3 — Ansible i VPN WireGuard

**Delegació:** 09 · **Rang:** `10.9.0.0/16` · **Node de control:** portàtil de l'alumne (Debian 13) amb VirtualBox 7.2

Automatització amb Ansible de dues tasques:

1. Iniciar i aturar els quatre routers MikroTik (rols `start_vm` i `stop_vm`).
2. Configurar un accés remot VPN WireGuard a `mikrotik0` i generar el fitxer del client.

Totes les ordres s'executen des d'aquest directori (`automation/ansible`), on `ansible.cfg` defineix l'inventari i els rols.

## 1. Requisits del node de control

| Eina | Versió provada | Instal·lació |
|---|---|---|
| ansible-core | 2.19.11 | `sudo apt install ansible` |
| `ansible.netcommon`, `community.routeros` | 8.1.0 · 3.10.0 | incloses al paquet `ansible` de Debian (o `ansible-galaxy collection install ansible.netcommon community.routeros`) |
| `wireguard-tools` | — | `sudo apt install wireguard-tools` |
| VirtualBox | 7.2.20 | `VBoxManage` al `PATH` |

**Clau de host de mikrotik0.** `ansible.cfg` té `host_key_checking = True` i `network_cli` (paramiko) llegeix `~/.ssh/known_hosts`. Cal que hi hagi l'entrada de `[127.0.0.1]:2200`. S'ha afegit després de comparar la clau que presenta el router (`ssh-keyscan -p 2200 127.0.0.1`) amb la que ja s'havia acceptat. No s'ha desactivat la comprovació.

## 2. Estructura

```
automation/ansible/
├── ansible.cfg
├── inventories/
│   ├── lab.yml                      # localhost (VirtualBox) i mikrotik0 (network_cli)
│   └── group_vars/all/wireguard.yml # variables no secretes de la VPN
├── playbooks/
│   ├── start_routers.yml
│   ├── stop_routers.yml
│   └── configure_wireguard.yml
└── roles/
    ├── start_vm/            # inicia una VM si no està en execució
    ├── stop_vm/             # aturada ACPI i espera fins a poweroff
    ├── wireguard_client/    # claus del client i fitxer .conf (node de control)
    ├── wireguard_server/    # interfície, peer i tallafoc a mikrotik0
    └── vbox_nat_forward/    # reenviament de port del NAT de VirtualBox
```

L'inventari no conté cap secret: per a mikrotik0 només hi ha el camí de la clau SSH privada (`~/.ssh/vcorp_sysadmin`). L'usuari és `sysadmin`, amb el sufix `+cet512w` que recomana la guia de `community.routeros` perquè RouterOS no talli les línies llargues de les ordres.

## 3. Primera part: iniciar i aturar els routers

```bash
ansible-inventory --list
ansible-playbook playbooks/start_routers.yml
ansible-playbook playbooks/stop_routers.yml
```

- `start_vm` consulta l'estat amb `showvminfo --machinereadable` i només executa `startvm --type headless` si la VM no és `running`.
- `stop_vm` només envia `acpipowerbutton` si la VM és `running` i espera, amb `until`, que arribi a `poweroff` (30 intents cada 2 s). No es fa cap aturada forçada.

**Idempotència comprovada:** la primera execució de cada playbook dona `changed=4`; la segona, `changed=0` (les tasques d'inici o d'aturada se salten). Evidència: `docs/evidencies/act3-ansible-routers.txt`.

## 4. Segona part: VPN WireGuard

### 4.1. Adreçament i variables

Tots els valors no secrets són a `inventories/group_vars/all/wireguard.yml`, separats de les tasques.

| Variable | Valor | Descripció |
|---|---|---|
| `wg_tunnel_network` | `10.9.10.0/24` | Rang del túnel. No es superposa amb cap xarxa de la delegació (10.9.0–3.x), ni amb el NAT de VirtualBox (10.0.2.0/24), ni amb la xarxa del client (Wi-Fi 10.112.153.0/24) |
| `wg_server_address` | `10.9.10.1/24` | Adreça de `mikrotik0` al túnel |
| `wg_client` | `arnau-portatil` · `10.9.10.2/32` | Client autoritzat |
| `wg_interface` | `wg-vpn` | Interfície WireGuard de RouterOS |
| `wg_listen_port` | `51820/udp` | Port d'escolta del servidor |
| `wg_wan_interface` | `ether1` | NIC1 de mikrotik0 (NAT de VirtualBox) |
| `wg_endpoint_host` | `127.0.0.1` | Endpoint del client (el client és al mateix ordinador). No revela cap adreça pública |

### 4.2. Xarxes autoritzades (`AllowedIPs`)

La VPN és d'**administració del CPD**, amb túnel dividit:

| Xarxa | Contingut | Motiu |
|---|---|---|
| `10.9.10.0/24` | Túnel | Arribar al router pel túnel |
| `10.9.0.128/26` | Zona privada: pve01, dbsrv, infosrv | Administració dels servidors interns |
| `10.9.0.192/27` | DMZ: websrv | Administració del servidor web |
| `10.9.0.224/28` | Enllaços entre routers | Administració dels routers |

**Excloses:** les xarxes d'usuaris (`pl0`–`pl3`) i la de direcció (`pl3_direccio`), que ha d'estar aïllada. No s'utilitza `0.0.0.0/0`: el trànsit d'Internet del client surt per la seva connexió.

### 4.3. Configuració a mikrotik0 (rol `wireguard_server`)

Cada objecte es compta abans de crear-lo (`:put [:len [... find where ...]]`) i només s'afegeix si no existeix. Tots porten el comentari `vcorp-wg`.

- Interfície `wg-vpn` amb `listen-port=51820`. RouterOS genera la clau privada; només se'n llegeix la pública per al fitxer del client.
- Adreça `10.9.10.1/24` a `wg-vpn`.
- Peer del client amb la seva clau pública i `allowed-address=10.9.10.2/32`. Si les claus del client es regeneren, el peer antic se substitueix.
- Llista d'adreces `vcorp-wg-permeses` amb les tres xarxes autoritzades.

**Regles de tallafoc afegides:**

| # | Cadena | Regla | Funció |
|---|---|---|---|
| 0 | `input` | `accept udp dst-port=51820 in-interface=ether1` | Entrada de WireGuard. Es col·loca **abans de la primera regla existent** perquè cap regla de descart l'aturi |
| 1 | `forward` | `accept connection-state=established,related` | Respostes |
| 2 | `forward` | `accept in-interface=wg-vpn dst-address-list=vcorp-wg-permeses` | VPN cap a les xarxes autoritzades |
| 3 | `forward` | `drop in-interface=wg-vpn` | La resta del trànsit de la VPN es descarta |

**Encaminament de retorn:** no s'afegeix NAT entre el túnel i les xarxes internes. La instància RIP dels routers té `redistribute=connected`, de manera que `mikrotik0` anuncia `10.9.10.0/24` i `mikrotik1`–`mikrotik3` l'aprenen per RIP (gateway: el router anterior de la cadena). No ha calgut cap ruta estàtica.

### 4.4. Reenviament UDP de VirtualBox (rol `vbox_nat_forward`)

Regla `wireguard,udp,127.0.0.1,51820,,51820` a la NIC1 (NAT) de mikrotik0. Escolta a `127.0.0.1`: només hi pot connectar un client del mateix ordinador. Per a un client extern caldria una adreça accessible del node de control, obrir el port al seu tallafoc i, si escau, un reenviament a la xarxa de l'aula. El rol comprova si la regla existeix abans de crear-la i fa servir `controlvm` si la VM està en marxa o `modifyvm` si està aturada.

### 4.5. Claus i fitxer del client (rol `wireguard_client`)

- Clau privada generada amb `wg genkey` (només si no existeix) i pública amb `wg pubkey`.
- Fitxer `<client>.conf` generat amb la plantilla `templates/client.conf.j2`.
- Tot es desa a `artifacts/vpn/` (directori `0700`, fitxers `0600`), **ignorat per Git**. Les tasques que llegeixen o escriuen claus privades tenen `no_log: true`.

### 4.6. Ús

```bash
ansible-playbook playbooks/start_routers.yml          # els routers han d'estar en marxa
ansible-playbook playbooks/configure_wireguard.yml
sudo wg-quick up   ../../artifacts/vpn/arnau-portatil.conf
sudo wg show
sudo wg-quick down ../../artifacts/vpn/arnau-portatil.conf
```

Ordre del playbook: (1) claus del client, (2) servidor a mikrotik0, (3) reenviament UDP i fitxer del client. Per afegir un altre client, cal canviar `wg_client` (nom i adreça del túnel) i tornar a executar el playbook.

## 5. Proves realitzades

| Prova (apartat 3.4) | Resultat |
|---|---|
| Playbook dues vegades | 1a: `changed` a mikrotik0 i al node; 2a: **`changed=0`**. Al router: 1 interfície, 1 peer, 1 adreça, 3 xarxes i 4 regles, sense duplicats |
| Handshake | Peer amb `last-handshake` recent i trànsit en els dos sentits |
| Xarxes autoritzades | Responen `10.9.10.1`, `10.9.0.129`, `10.9.0.193`, `10.9.0.225`, `.226`, `.230` i `.234` |
| Accés administratiu | Ping i **SSH a pve01** (`10.9.0.133`) pel túnel. pve01 veu l'origen `10.9.10.2` (sense NAT) |
| Xarxes no autoritzades | El client no les envia pel túnel. Amb el client modificat a propòsit per enviar `pl0` i direcció pel túnel, mikrotik0 les **descarta** (comptador de la regla 3: de 0 a 6 paquets) |
| Túnel dividit | `1.1.1.1` surt per la Wi-Fi del client; Internet i DNS funcionen |
| Desactivar i reactivar | `wg-quick down`/`up`: tornen les 4 rutes i hi ha handshake nou |
| Persistència | Després de reiniciar mikrotik0 es conserven interfície, adreça, peer, llista i regles; el túnel es reconnecta sol i RIP torna a anunciar `10.9.10.0/24` |

Evidències: `docs/evidencies/act3-ansible-routers.txt`, `act3-wireguard-playbook.txt` i `act3-wireguard-proves.txt`. No contenen cap clau.

## 6. Incidències

- **Actualització del kernel de l'amfitrió:** el mòdul `vboxdrv` no estava compilat per al kernel nou i VirtualBox no podia iniciar VMs. Solució: `linux-headers` del kernel actual i `sudo /sbin/vboxconfig`.
- **Clau de host per a `network_cli`:** l'accés SSH habitual als routers fa servir `~/.ssh/known_hosts_vcorp`, però Ansible (paramiko) llegeix `~/.ssh/known_hosts`. S'hi ha afegit la clau de mikrotik0 després de verificar-la.
- **Accents a la sortida de RouterOS:** les ordres `:put` eliminen els caràcters no ASCII. S'han corregit a mà dues paraules a les evidències.
