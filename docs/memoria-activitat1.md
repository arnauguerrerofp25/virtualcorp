# Activitat 1 — Desplegament dels routers MikroTik

**Delegació:** 09 · **Rang assignat:** `10.9.0.0/16` · **Responsable:** Arnau Guerrero Asensio

**Entorn:** Debian 13 (kernel 6.12) · VirtualBox 7.2.20 · RouterOS CHR 7.21.4

## 1. Repositori

El projecte parteix del repositori inicial del professor, que s'ha mantingut com a remot `upstream`. El treball propi es desa al repositori personal (`origin`):

```
origin    git@github.com:arnauguerrerofp25/virtualcorp.git
upstream  git@github.com:cbarahon/VirtualCorp-student.git
```

## 2. Adreçament de la delegació

S'ha mantingut la topologia en cadena proporcionada (`mikrotik0` – `mikrotik1` – `mikrotik2` – `mikrotik3`), però s'ha substituït el rang de Serveis Centrals (`10.1.0.0/16`) pel de la delegació 09. Els enllaços /30 i les xarxes de planta coincideixen amb les especificacions del projecte.

| Router | Interfície (xarxa interna) | Adreça | Funció |
|---|---|---|---|
| mikrotik0 | ether1 (NAT VirtualBox) | DHCP (`10.0.2.15`) | Sortida a Internet |
| | ether2 (`r0-r1`) | `10.9.0.225/30` | Enllaç amb mikrotik1 |
| | ether3 (`dmz`) | `10.9.0.193/27` | DMZ |
| mikrotik1 | ether2 (`r0-r1`) | `10.9.0.226/30` | Enllaç amb mikrotik0 |
| | ether3 (`r1-r2`) | `10.9.0.229/30` | Enllaç amb mikrotik2 |
| | ether4 (`pl0`) | `10.9.0.1/25` | Zona general planta baixa |
| mikrotik2 | ether2 (`r1-r2`) | `10.9.0.230/30` | Enllaç amb mikrotik1 |
| | ether3 (`r2-r3`) | `10.9.0.233/30` | Enllaç amb mikrotik3 |
| | ether4 (`pl1`) | `10.9.1.1/24` | Planta 1 |
| | ether5 (`pl2`) | `10.9.2.1/24` | Planta 2 |
| mikrotik3 | ether2 (`r2-r3`) | `10.9.0.234/30` | Enllaç amb mikrotik2 |
| | ether3 (`pl3`) | `10.9.3.1/25` | Planta 3 |
| | ether4 (`pl3-direccio`) | `10.9.3.129/25` | Planta 3, xarxa aïllada de direcció |

- **Encaminament:** RIP entre els quatre routers, amb ruta per defecte cap al router anterior de la cadena. `mikrotik0` fa NAT (masquerade) cap a Internet.
- **Xarxa `10.0.0.0/16`:** només s'utilitza per al NAT de VirtualBox, tal com reserva l'enunciat.
- **Zona privada (`10.9.0.128/26`):** no s'ha assignat encara a cap router. Es definirà a la fase de disseny del CPD, perquè no intervé en les proves d'aquesta activitat.

## 3. Canvis fets al codi i per què

| Fitxer | Canvi | Motiu |
|---|---|---|
| `automation/scripts/bootstrap/create_ssh_keys.sh` | Es deixa de generar la clau `vcorp_auditor` | L'script original generava un parell nou i **sobreescrivia** `configs/ssh/vcorp_auditor.pub`, que és la clau del professor i no es pot modificar. |
| `infrastructure/bash/deploy_routers.sh` | Adreces `10.1.x.x` → `10.9.x.x` | Adaptar l'adreçament al rang de la delegació 09. |
| `infrastructure/bash/router_base.sh` | Creació de l'usuari `auditor` amb la clau pública del professor a cada router | Els scripts només creaven `sysadmin`; la clau del professor no s'instal·lava enlloc (requisit 6.1). |
| `infrastructure/bash/router_base.sh` | Reintents en importar `auditor.pub` | Vegeu el problema 2 de l'apartat 6. |
| `infrastructure/bash/router_base.sh` | `/ip ssh set forwarding-enabled=local` al router amb NAT | Permet utilitzar `mikrotik0` com a salt SSH per arribar a la resta de routers. |

**Decisions sobre l'usuari `auditor`:**
- Grup `full`, perquè l'enunciat demana accés administratiu.
- Contrasenya aleatòria de 24 caràcters que no es desa enlloc. RouterOS té `password-authentication: yes-if-no-key`, de manera que un usuari amb clau assignada només pot entrar amb la clau. El professor no necessita cap contrasenya.

## 4. Accés SSH

Només `mikrotik0` és accessible des de l'equip amfitrió (port `2200` redirigit pel NAT de VirtualBox). Els altres tres routers perden la redirecció quan la NIC1 passa a xarxa interna, i s'hi accedeix fent salt per `mikrotik0`.

| Usuari | Clau | Ús |
|---|---|---|
| `sysadmin` | `vcorp_sysadmin` (personal, privada a `~/.ssh`) | Administració |
| `auditor` | `vcorp_auditor.pub` (professor) | Revisió i avaluació |

**Accés per al professor** (amb la seva clau carregada a `ssh-agent`):

```bash
ssh -p 2200 auditor@127.0.0.1                         # mikrotik0
ssh -J auditor@127.0.0.1:2200 auditor@10.9.0.226      # mikrotik1
ssh -J auditor@127.0.0.1:2200 auditor@10.9.0.230      # mikrotik2
ssh -J auditor@127.0.0.1:2200 auditor@10.9.0.234      # mikrotik3
```

**Configuració de client utilitzada** (`~/.ssh/config`):

```
Host mikrotik0
    HostName 127.0.0.1
    Port 2200
Host mikrotik1
    HostName 10.9.0.226
    ProxyJump mikrotik0
Host mikrotik2
    HostName 10.9.0.230
    ProxyJump mikrotik0
Host mikrotik3
    HostName 10.9.0.234
    ProxyJump mikrotik0
Host mikrotik*
    User sysadmin
    IdentityFile ~/.ssh/vcorp_sysadmin
    IdentitiesOnly yes
    UserKnownHostsFile ~/.ssh/known_hosts_vcorp
    StrictHostKeyChecking accept-new
```

Tots els routers fan salt directament per `mikrotik0`: gràcies a RIP hi arriba sense passar per cada router intermedi, i així la fallada d'un router no bloqueja l'accés als altres.

## 5. Validació

Evidències completes a `docs/evidencies/validacio-routers.txt`.

| Prova | mikrotik0 | mikrotik1 | mikrotik2 | mikrotik3 |
|---|---|---|---|---|
| Ping als altres tres routers | ✅ 0% pèrdua | ✅ 0% pèrdua | ✅ 0% pèrdua | ✅ 0% pèrdua |
| Ping a `1.1.1.1` | ✅ | ✅ | ✅ | ✅ |
| Ping a `google.com` | ✅ | ❌ sense DNS | ❌ sense DNS | ❌ sense DNS |
| Accés SSH personal (`sysadmin`) | ✅ | ✅ | ✅ | ✅ |
| Clau del professor instal·lada | ✅ | ✅ | ✅ | ✅ |

- Les rutes de totes les xarxes `10.9.x.x` apareixen apreses per RIP a `mikrotik0`.
- El TTL de les respostes des de `mikrotik0` (64 → 63 → 62) confirma que els paquets travessen 1, 2 i 3 routers.
- Des de `mikrotik1`–`mikrotik3`, el ping a `google.com` retorna `failure: resolve failed`: no tenen cap servidor DNS configurat (vegeu l'apartat 7).
- **Persistència:** s'han reiniciat els quatre routers (`/system reboot`). Després del reinici (uptime de 21–29 s), tots conserven les adreces IP, la ruta de sortida i la connectivitat a Internet, i l'accés SSH per salt continua funcionant. Evidència a `docs/evidencies/persistencia.txt`.

## 6. Problemes trobats i solucions

1. **L'script de claus sobreescrivia la clau del professor.** Detectat en revisar el codi abans d'executar-lo. S'ha desactivat la generació de `vcorp_auditor`.
2. **Error en desplegar `mikrotik2`:** `input does not match any value of public-key-file`. El fitxer `auditor.pub` s'havia pujat correctament, però RouterOS triga uns segons a registrar els fitxers rebuts per SCP i la importació s'executava massa aviat (a `mikrotik0` i `mikrotik1` va funcionar per atzar). Solució: reintentar la importació fins a 5 vegades amb 2 s d'espera. S'ha esborrat el `mikrotik2` incomplet i s'ha tornat a executar el desplegament.
3. **Sense accés des de l'amfitrió a `mikrotik1`–`mikrotik3`.** S'ha habilitat el reenviament SSH a `mikrotik0` i s'ha incorporat a l'script perquè es conservi en cada desplegament.
4. **Primera prova de reinici incompleta.** En reiniciar els routers en ordre `mikrotik0` → `mikrotik3`, el primer a caure era el salt SSH i les ordres als altres tres fallaven (`Connection reset`). S'han reiniciat en ordre invers (`mikrotik3` → `mikrotik0`) i s'ha verificat amb l'uptime que tots s'havien reiniciat.
5. **Errors intermitents de DNS a l'equip amfitrió** en accedir a GitHub. Eren de la xarxa local i es van resoldre sols en tornar-ho a provar.

## 7. Pendent i millores

- **DNS a `mikrotik1`–`mikrotik3`:** no tenen servidor DNS. Es configurarà quan es desplegui el servei DNS de la delegació al CPD.
- **Zona privada `10.9.0.128/26`:** cal assignar-la a un router a la fase de disseny del CPD.
- **Usuari `admin` de fàbrica:** continua existint sense contrasenya. Cal deshabilitar-lo, ja que l'administració es fa amb `sysadmin`.
- **Errors menors dels scripts originals:** alguns missatges criden `log_error`, que no existeix (la funció és `log_err`), i `wait_ssh` només espera 60 s.
