#!/usr/bin/env bash

set -e

# Carregar les funcions d'ajuda
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/template_base.sh"

check_template_prerequisites

# Comprovacions de components de cada template
SERVER_CHECKS='
echo "--- components"
if dpkg -s xserver-xorg-core >/dev/null 2>&1; then echo "ERROR: hi ha entorn gràfic"; exit 1; fi
echo "Sense entorn gràfic: OK"
'

DESKTOP_CHECKS='
echo "--- components"
dpkg-query -W -f="\${Package} \${Version}\n" lxqt-core sddm falkon
for p in firefox-esr libreoffice-core; do
    if dpkg -s "$p" >/dev/null 2>&1; then echo "ERROR: $p instal·lat"; exit 1; fi
done
echo "Sense Firefox ni LibreOffice: OK"
echo "Arrencada per defecte: $(systemctl get-default)"
'

# Template Debian Server: servidors del CPD, DMZ i impressores
# 1 CPU, 1024 MB de RAM, 10 GB de disc (dinàmic)
create_debian_template "tpl-debian-server" \
  "$CONFIGS_DIR/preseed/debian-server.cfg" \
  1 1024 10240 \
  "$SERVER_CHECKS"

# Template Debian Desktop: usuaris de les plantes, consergeria i expositors
# 2 CPU, 2048 MB de RAM, 16 GB de disc (dinàmic)
create_debian_template "tpl-debian-desktop" \
  "$CONFIGS_DIR/preseed/debian-desktop.cfg" \
  2 2048 16384 \
  "$DESKTOP_CHECKS"

log_info "=========================================="
log_info "[+] Templates creats correctament."
log_info "=========================================="
