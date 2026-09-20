#!/usr/bin/env bash
## // ## // ## // ## // ## // ## // ## // ## // ## // ## // ## // ## // ## //
##   VPS STACK — Contabo · Traefik · 3 Sites · PostgreSQL · Mailcow         ##
##   Uso:  sudo ./setup.sh            (menu)                                ##
##         sudo ./setup.sh 1 2 3      (roda módulos em sequência)           ##
##         sudo ./setup.sh all        (tudo, na ordem)                      ##
## // ## // ## // ## // ## // ## // ## // ## // ## // ## // ## // ## // ## //
set -uo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${BASE_DIR}/lib/ui.sh"
checa_root

if [ ! -f "${BASE_DIR}/config.conf" ]; then
    banner
    falha "config.conf não encontrado."
    info  "Rode:  cp config.conf.example config.conf && nano config.conf"
    exit 1
fi
carrega_config
chmod +x "${BASE_DIR}"/modules/*.sh

roda() {
    local m
    case "$1" in
        1) m=01-base ;;    2) m=02-docker ;;  3) m=03-traefik ;;
        4) m=04-postgres ;; 5) m=05-sites ;;  6) m=06-mailcow ;;
        7) m=07-backup ;;  8) m=08-checks ;;  9) m=09-paineis ;;
        *) falha "Módulo inválido: $1"; return 1 ;;
    esac
    bash "${BASE_DIR}/modules/${m}.sh"
    echo ""
    read -rp "  Pressione ENTER para voltar ao menu..."
}

menu() {
while true; do
    banner
    cat <<EOF
     Servidor: $(hostname)   |   IP: $(hostname -I | awk '{print $1}')   |   $(date '+%d/%m/%Y %H:%M')

     ${amarelo}ORDEM RECOMENDADA${reset}

      1) Base do sistema        pacotes, swap, timezone, SSH, UFW, fail2ban
      2) Docker                 engine + compose + redes + DOCKER-USER
      3) Traefik                proxy reverso 80/443 + Let's Encrypt
      4) PostgreSQL ${PG_VERSION}          container + 1 banco por site
      5) Sites (3 stacks)       ${SITE1_DOMAIN}, ${SITE2_DOMAIN}, ${SITE3_DOMAIN}
      6) Mailcow                ${MAILCOW_HOSTNAME} atrás do Traefik
      7) Backup                 cron diário (Postgres + stacks + mailcow)
      9) Painéis                Portainer, pgAdmin e n8n

      8) ${verde}Diagnóstico${reset}           DNS, PTR, portas, certificados, blacklist
      c) Ver credenciais geradas
      0) Sair

EOF
    read -rp "  Escolha uma opção: " op
    case "$op" in
        [1-9]) roda "$op" ;;
        c|C) clear; cat "${STATE_DIR}/credenciais.txt" 2>/dev/null || aviso "Nenhuma credencial gerada ainda";
           echo ""; read -rp "  ENTER para voltar..." ;;
        0) clear; exit 0 ;;
        *) ;;
    esac
done
}

if [ $# -eq 0 ]; then
    menu
elif [ "$1" = "all" ]; then
    for i in 1 2 3 4 5 6 9 7 8; do bash "${BASE_DIR}/modules/$(printf '%02d' "$i")-"*.sh || exit 1; done
else
    for arg in "$@"; do roda "$arg"; done
fi
