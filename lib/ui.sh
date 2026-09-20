#!/usr/bin/env bash
## // ## // ## // ## // ## // ## // ## // ## // ## // ## // ## // ## // ## //
##                    BIBLIOTECA DE UI / HELPERS                            ##
## // ## // ## // ## // ## // ## // ## // ## // ## // ## // ## // ## // ## //

## Cores
amarelo="\e[33m"
verde="\e[32m"
branco="\e[97m"
bege="\e[93m"
vermelho="\e[91m"
azul="\e[94m"
reset="\e[0m"

BASE_DIR="${BASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATE_DIR="/opt/vps-setup"
LOG_FILE="${STATE_DIR}/setup.log"

mkdir -p "$STATE_DIR"

log()      { echo -e "$(date '+%F %T') | $*" >> "$LOG_FILE"; }
info()     { echo -e "  ${azul}»${reset} $*"; log "INFO  $*"; }
ok()       { echo -e "  ${verde}[ OK ]${reset}   $*"; log "OK    $*"; }
falha()    { echo -e "  ${vermelho}[ FAIL ]${reset} $*"; log "FAIL  $*"; }
aviso()    { echo -e "  ${bege}[ !! ]${reset}   $*"; log "WARN  $*"; }
titulo()   { echo ""; echo -e "${amarelo}── $* ──────────────────────────────────────────${reset}"; echo ""; }

## Executa um comando silenciosamente e imprime OK/FAIL
run() {
    local desc="$1"; shift
    if "$@" >>"$LOG_FILE" 2>&1; then ok "$desc"; return 0
    else falha "$desc  (veja $LOG_FILE)"; return 1; fi
}

## Pergunta sim/não — padrão configurável
confirma() {
    local pergunta="$1" padrao="${2:-s}" resp
    read -rp "$(echo -e "  ${amarelo}?${reset} ${pergunta} [s/n] (${padrao}): ")" resp
    resp="${resp:-$padrao}"
    [[ "$resp" =~ ^[sSyY]$ ]]
}

senha_aleatoria() { head -c 256 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-"${1:-24}"; }

limpa() { clear 2>/dev/null || printf '\033[2J\033[H'; }

banner() {
limpa
echo ""
echo -e "$amarelo===================================================================================================$reset"
echo -e "$amarelo=                                                                                                 =$reset"
echo -e "$amarelo=   $branco ██╗   ██╗██████╗ ███████╗    ███████╗████████╗ █████╗  ██████╗██╗  ██╗                      $amarelo=$reset"
echo -e "$amarelo=   $branco ██║   ██║██╔══██╗██╔════╝    ██╔════╝╚══██╔══╝██╔══██╗██╔════╝██║ ██╔╝                      $amarelo=$reset"
echo -e "$amarelo=   $branco ██║   ██║██████╔╝███████╗    ███████╗   ██║   ███████║██║     █████╔╝                       $amarelo=$reset"
echo -e "$amarelo=   $branco ╚██╗ ██╔╝██╔═══╝ ╚════██║    ╚════██║   ██║   ██╔══██║██║     ██╔═██╗                       $amarelo=$reset"
echo -e "$amarelo=   $branco  ╚████╔╝ ██║     ███████║    ███████║   ██║   ██║  ██║╚██████╗██║  ██╗                      $amarelo=$reset"
echo -e "$amarelo=   $branco   ╚═══╝  ╚═╝     ╚══════╝    ╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝                      $amarelo=$reset"
echo -e "$amarelo=                                                                                                 =$reset"
echo -e "$amarelo=          $bege Traefik  ·  3 Sites  ·  PostgreSQL  ·  Mailcow   —   Contabo VPS  v1.0 $amarelo             =$reset"
echo -e "$amarelo===================================================================================================$reset"
echo ""
}

banner_secao() {
limpa
echo ""
echo -e "$amarelo===================================================================================================$reset"
echo -e "$amarelo=  $branco$(printf '%-93s' "$1")$amarelo=$reset"
echo -e "$amarelo===================================================================================================$reset"
echo ""
}

## Carrega config.conf (obrigatório)
carrega_config() {
    if [ ! -f "${BASE_DIR}/config.conf" ]; then
        falha "config.conf não encontrado. Rode: cp config.conf.example config.conf && nano config.conf"
        exit 1
    fi
    # shellcheck disable=SC1091
    source "${BASE_DIR}/config.conf"
}

## Salva um segredo gerado em /opt/vps-setup/credenciais.txt
guarda_credencial() {
    local arquivo="${STATE_DIR}/credenciais.txt"
    touch "$arquivo"; chmod 600 "$arquivo"
    echo "$(date '+%F %T') | $*" >> "$arquivo"
}

## Pré-requisitos mínimos: root + SO suportado
checa_root() {
    if [ "$(id -u)" -ne 0 ]; then
        falha "Este script precisa ser executado como root (use: sudo -i)"
        exit 1
    fi
}

checa_so() {
    local pretty
    pretty=$(grep -oP '(?<=^PRETTY_NAME=").*(?="$)' /etc/os-release || echo desconhecido)
    case "$pretty" in
        *"Debian GNU/Linux 12"*|*"Debian GNU/Linux 13"*|*"Ubuntu 22.04"*|*"Ubuntu 24.04"*)
            ok "Sistema suportado: $pretty" ;;
        *"Debian GNU/Linux 11"*)
            aviso "Debian 11 funciona, mas o recomendado para o mailcow hoje é Debian 12/13." ;;
        *)
            aviso "SO não testado ($pretty). Recomendado: Debian 12 ou Ubuntu 22.04/24.04." ;;
    esac
}
