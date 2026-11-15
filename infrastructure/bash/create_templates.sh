#!/usr/bin/env bash

set -e

# Carregar les funcions d'ajuda
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/template_base.sh"

check_template_prerequisites

# Template Debian Server: servidors del CPD, DMZ i impressores
# 1 CPU, 1024 MB de RAM, 10 GB de disc (dinàmic)
create_debian_template "tpl-debian-server" \
  "$CONFIGS_DIR/preseed/debian-server.cfg" \
  1 1024 10240

log_info "=========================================="
log_info "[+] Templates creats correctament."
log_info "=========================================="
