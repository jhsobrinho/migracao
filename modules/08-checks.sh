#!/usr/bin/env bash
## Módulo 08 — Diagnóstico: DNS, portas, containers, certificados
set -uo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/lib/ui.sh"
carrega_config
checa_root

banner_secao "08 · DIAGNÓSTICO"

IP=$(curl -4 -s https://ifconfig.me || echo "?")
info "IP público: ${IP}"

titulo "DNS dos domínios"
checa_a() {
    local host="$1" got
    got=$(dig +short A "$host" | tail -1)
    if [ "$got" = "$IP" ]; then ok "A ${host} → ${got}"
    elif [ -z "$got" ]; then falha "A ${host} → não resolve"
    else aviso "A ${host} → ${got} (esperado ${IP}; ok se usar Cloudflare proxy)"; fi
}
for n in 1 2 3; do
    eval "d=\${SITE${n}_DOMAIN}"
    checa_a "$d"; checa_a "www.${d}"
done
checa_a "${TRAEFIK_DOMAIN}"
checa_a "${MAILCOW_HOSTNAME}"
for painel in "${INSTALL_PORTAINER:-n}:${PORTAINER_DOMAIN:-}" \
              "${INSTALL_PGADMIN:-n}:${PGADMIN_DOMAIN:-}" \
              "${INSTALL_N8N:-n}:${N8N_DOMAIN:-}"; do
    [ "${painel%%:*}" = "y" ] && [ -n "${painel#*:}" ] && checa_a "${painel#*:}"
done

titulo "Registros de e-mail"
for d in ${MAILCOW_EXTRA_DOMAINS}; do
    mx=$(dig +short MX "$d" | sort | head -2 | tr '\n' ' ')
    spf=$(dig +short TXT "$d" | grep -i 'v=spf1' | head -1)
    dmarc=$(dig +short TXT "_dmarc.${d}" | head -1)
    dkim=$(dig +short TXT "dkim._domainkey.${d}" | head -1)
    echo -e "  ${branco}${d}${reset}"
    [ -n "$mx" ]    && ok "MX    ${mx}"        || falha "MX    ausente"
    [ -n "$spf" ]   && ok "SPF   ${spf}"       || falha "SPF   ausente"
    [ -n "$dmarc" ] && ok "DMARC ${dmarc}"     || falha "DMARC ausente"
    [ -n "$dkim" ]  && ok "DKIM  publicado"    || falha "DKIM  ausente (pegue no painel do mailcow)"
done

titulo "rDNS / PTR"
ptr=$(dig +short -x "$IP" | sed 's/\.$//')
[ "$ptr" = "${MAILCOW_HOSTNAME}" ] && ok "PTR ${ptr}" || falha "PTR '${ptr:-vazio}' ≠ ${MAILCOW_HOSTNAME} (ajuste no painel da Contabo)"

titulo "Portas locais em escuta"
ss -tlpn | grep -E -w '25|80|110|143|443|465|587|993|995|4190|8080|8443|5432' | sed 's/^/     /'

titulo "Porta 25 de saída"
if timeout 10 bash -c 'cat < /dev/null > /dev/tcp/gmail-smtp-in.l.google.com/25' 2>/dev/null; then
    ok "Saída na 25 liberada"
else
    falha "Saída na 25 bloqueada — ticket na Contabo"
fi

titulo "Containers"
docker ps --format '     {{.Names}}\t{{.Status}}' | sed 's/\t/  /'
parados=$(docker ps -a --filter status=exited --format '{{.Names}}' | tr '\n' ' ')
[ -n "$parados" ] && aviso "Containers parados: ${parados}"

titulo "Certificados emitidos pelo Traefik"
if [ -s /opt/traefik/letsencrypt/acme.json ]; then
    jq -r '.le.Certificates[]?.domain.main' /opt/traefik/letsencrypt/acme.json 2>/dev/null | sed 's/^/     ✔ /'
else
    aviso "acme.json vazio — nenhum certificado emitido ainda"
fi

titulo "Blacklists do IP"
for bl in zen.spamhaus.org bl.spamcop.net b.barracudacentral.org; do
    rev=$(echo "$IP" | awk -F. '{print $4"."$3"."$2"."$1}')
    r=$(dig +short "${rev}.${bl}" | head -1)
    case "$r" in
        127.255.255.*) aviso "${bl}: resolver público bloqueado, consulte https://check.spamhaus.org/" ;;
        127.*)         falha "LISTADO em ${bl} (${r})" ;;
        *)             ok "limpo em ${bl}" ;;
    esac
done

titulo "Recursos"
free -h  | sed 's/^/     /'
df -h /  | sed 's/^/     /'
echo ""
ok "Diagnóstico concluído."
