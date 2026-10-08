#!/usr/bin/env bash
## Módulo 06 — mailcow-dockerized atrás do Traefik (docs: reverse-proxy/r_p-traefik3)
set -uo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/lib/ui.sh"
carrega_config
checa_root

banner_secao "06 · MAILCOW (SERVIDOR DE E-MAIL)"

## ---- pré-checagens ------------------------------------------------------
titulo "Pré-checagens"
mem_gb=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
[ "$mem_gb" -ge 6 ] && ok "RAM: ${mem_gb} GB" || aviso "RAM: ${mem_gb} GB — mailcow pede 6 GB+ (use SKIP_CLAMD=y / SKIP_FTS=y)"

ip_publico=$(curl -4 -s https://ifconfig.me || echo "?")
ip_dns=$(dig +short A "${MAILCOW_HOSTNAME}" | tail -1)
info "IP público da VPS : ${ip_publico}"
info "A de ${MAILCOW_HOSTNAME} : ${ip_dns:-<não resolve>}"
[ "$ip_publico" = "$ip_dns" ] && ok "DNS do hostname do mailcow OK" || aviso "Aponte ${MAILCOW_HOSTNAME} (registro A) para ${ip_publico} antes de continuar"

ptr=$(dig +short -x "${ip_publico}" | sed 's/\.$//')
[ "$ptr" = "${MAILCOW_HOSTNAME}" ] && ok "rDNS/PTR correto (${ptr})" \
    || aviso "rDNS atual: '${ptr:-vazio}'. Configure no painel da Contabo para '${MAILCOW_HOSTNAME}' — sem isso seus e-mails caem em spam/são recusados."

if timeout 10 bash -c 'cat < /dev/null > /dev/tcp/gmail-smtp-in.l.google.com/25' 2>/dev/null; then
    ok "Porta 25 de saída liberada"
else
    falha "Porta 25 de saída BLOQUEADA — abra ticket na Contabo antes de seguir"
    confirma "Continuar mesmo assim?" "n" || exit 1
fi

if ss -tlpn | grep -E ':(25|465|587|143|993|110|995|4190) ' | grep -qv docker; then
    aviso "Há serviços ocupando portas de e-mail no host (exim4/postfix)"
    if confirma "Remover exim4/postfix do host agora?" "s"; then
        systemctl disable --now exim4 postfix >/dev/null 2>&1 || true
        DEBIAN_FRONTEND=noninteractive apt-get purge -y exim4 exim4-base exim4-config exim4-daemon-light postfix >/dev/null 2>&1 || true
        ss -tlpn | grep -qE ':25 ' && falha "Porta 25 ainda ocupada" && exit 1
        ok "Portas de e-mail liberadas"
    fi
fi

## ---- clone --------------------------------------------------------------
titulo "Instalando o mailcow"
umask 0022
if [ ! -d "${MAILCOW_PATH}" ]; then
    run "git clone mailcow-dockerized" git clone https://github.com/mailcow/mailcow-dockerized "${MAILCOW_PATH}"
else
    ok "Diretório ${MAILCOW_PATH} já existe"
fi
cd "${MAILCOW_PATH}" || exit 1

if [ ! -f mailcow.conf ]; then
    info "Gerando mailcow.conf (hostname=${MAILCOW_HOSTNAME}, tz=${TZ})"
    MAILCOW_HOSTNAME="${MAILCOW_HOSTNAME}" MAILCOW_TZ="${TZ}" MAILCOW_BRANCH="master" ./generate_config.sh
else
    ok "mailcow.conf já existe — apenas ajustando parâmetros"
fi

## ---- ajustes para rodar atrás do Traefik --------------------------------
titulo "Ajustando mailcow.conf para proxy reverso"
set_conf() {  # set_conf CHAVE valor
    if grep -q "^${1}=" mailcow.conf; then
        sed -i "s|^${1}=.*|${1}=${2}|" mailcow.conf
    else
        echo "${1}=${2}" >> mailcow.conf
    fi
    ok "${1}=${2}"
}
## Bind VAZIO: o nginx do mailcow precisa escutar em todas as interfaces do
## container para o Traefik alcançá-lo pela rede docker 'proxy'.
set_conf HTTP_PORT 8080
set_conf HTTP_BIND ""
set_conf HTTPS_PORT 8443
set_conf HTTPS_BIND ""
set_conf SKIP_LETS_ENCRYPT y      # quem emite o certificado é o Traefik
set_conf HTTP_REDIRECT n          # TLS termina no Traefik; sem redirect interno
set_conf AUTODISCOVER_SAN n
set_conf SKIP_CLAMD "${MAILCOW_SKIP_CLAMAV}"
set_conf SKIP_SOGO  "${MAILCOW_SKIP_SOGO}"

## nomes extras atendidos pela UI (autoconfig/autodiscover dos outros domínios)
extras=""
for d in ${MAILCOW_EXTRA_DOMAINS}; do
    extras="${extras}autoconfig.${d},autodiscover.${d},"
done
set_conf ADDITIONAL_SERVER_NAMES "${extras%,}"

COMPOSE_PROJECT=$(grep '^COMPOSE_PROJECT_NAME=' mailcow.conf | cut -d= -f2)
COMPOSE_PROJECT="${COMPOSE_PROJECT:-mailcowdockerized}"
info "COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT}"

## ---- regras do Traefik (labels) + certdumper ----------------------------
titulo "docker-compose.override.yml (Traefik + certs-dumper)"
regra_autoconf=""
for d in ${MAILCOW_EXTRA_DOMAINS}; do
    regra_autoconf="${regra_autoconf}Host(\`autoconfig.${d}\`) || Host(\`autodiscover.${d}\`) || "
done
regra_autoconf="${regra_autoconf%" || "}"

cat > docker-compose.override.yml <<EOF
services:
  nginx-mailcow:
    networks:
      mailcow-network:
        aliases: [nginx]
      proxy:
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=proxy"
      - "traefik.http.routers.mailcow.rule=Host(\`${MAILCOW_HOSTNAME}\`)"
      - "traefik.http.routers.mailcow.entrypoints=websecure"
      - "traefik.http.routers.mailcow.tls.certresolver=le"
      - "traefik.http.routers.mailcow.service=mailcow-svc"
      - "traefik.http.routers.mailcow-autoconfig.rule=${regra_autoconf}"
      - "traefik.http.routers.mailcow-autoconfig.entrypoints=websecure"
      - "traefik.http.routers.mailcow-autoconfig.tls.certresolver=le"
      - "traefik.http.routers.mailcow-autoconfig.service=mailcow-svc"
      - "traefik.http.services.mailcow-svc.loadbalancer.server.port=8080"

  ## Copia o certificado emitido pelo Traefik para o postfix/dovecot
  certdumper:
    image: ghcr.io/kereis/traefik-certs-dumper:latest
    container_name: traefik_certdumper
    restart: unless-stopped
    network_mode: none
    command: --restart-containers ${COMPOSE_PROJECT}-postfix-mailcow-1,${COMPOSE_PROJECT}-dovecot-mailcow-1,${COMPOSE_PROJECT}-nginx-mailcow-1
    volumes:
      - /opt/traefik/letsencrypt:/traefik:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./data/assets/ssl:/output:rw
    environment:
      - DOMAIN=${MAILCOW_HOSTNAME}
      - ACME_FILE_PATH=/traefik/acme.json

networks:
  proxy:
    external: true
EOF
ok "override criado em ${MAILCOW_PATH}/docker-compose.override.yml"

titulo "Subindo o mailcow (a primeira vez baixa ~2 GB de imagens)"
run "docker compose pull" docker compose pull
run "docker compose up -d" docker compose up -d
sleep 10
docker compose ps --format '     {{.Name}}  {{.Status}}' 2>/dev/null | head -25

echo ""
titulo "Próximos passos (manuais, no painel)"
cat <<EOF
     1. Acesse  https://${MAILCOW_HOSTNAME}   → login: admin / moohoo  (TROQUE A SENHA)
     2. E-mail → Domínios → adicione: ${MAILCOW_EXTRA_DOMAINS}
     3. Em cada domínio, copie a chave DKIM e publique no DNS
     4. Publique MX, SPF, DMARC e os CNAMEs de autoconfig/autodiscover (veja dns/DNS.md)
     5. Teste em https://www.mail-tester.com e https://mxtoolbox.com/deliverability
EOF
info "Se o container 'traefik_certdumper' reclamar de nomes, confira:  docker ps --format '{{.Names}}'"
ok "Módulo 06 concluído."
