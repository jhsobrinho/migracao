#!/usr/bin/env bash
## Módulo 03 — Traefik v3 como proxy reverso único (80/443) + Let's Encrypt
set -uo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/lib/ui.sh"
carrega_config
checa_root

banner_secao "03 · TRAEFIK (PROXY REVERSO + TLS)"

TRAEFIK_DIR="/opt/traefik"
mkdir -p "${TRAEFIK_DIR}/dynamic" "${TRAEFIK_DIR}/letsencrypt" "${TRAEFIK_DIR}/logs"
touch "${TRAEFIK_DIR}/letsencrypt/acme.json"
chmod 600 "${TRAEFIK_DIR}/letsencrypt/acme.json"

## ---- senha do dashboard -------------------------------------------------
if [ -z "${TRAEFIK_PASS}" ] && [ -f "${STATE_DIR}/credenciais.txt" ]; then
    TRAEFIK_PASS=$(grep 'Traefik dashboard' "${STATE_DIR}/credenciais.txt" | tail -1 | awk '{print $NF}')
    [ -n "${TRAEFIK_PASS}" ] && ok "Reaproveitando a senha do dashboard já registrada"
fi
if [ -z "${TRAEFIK_PASS}" ]; then
    TRAEFIK_PASS="$(senha_aleatoria 20)"
    guarda_credencial "Traefik dashboard — https://${TRAEFIK_DOMAIN} — ${TRAEFIK_USER} / ${TRAEFIK_PASS}"
    aviso "Senha do dashboard gerada e salva em ${STATE_DIR}/credenciais.txt"
fi
HASH=$(htpasswd -nbB "${TRAEFIK_USER}" "${TRAEFIK_PASS}")

## ---- configuração estática ----------------------------------------------
cat > "${TRAEFIK_DIR}/traefik.yml" <<EOF
global:
  checkNewVersion: true
  sendAnonymousUsage: false

log:
  level: INFO
  filePath: /logs/traefik.log

accessLog:
  filePath: /logs/access.log
  bufferingSize: 100

api:
  dashboard: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"
    http:
      middlewares:
        - seguranca@file
        - compressao@file
      tls:
        certResolver: le

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: proxy
  file:
    directory: /dynamic
    watch: true

certificatesResolvers:
  le:
    acme:
      email: "${ACME_EMAIL}"
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
EOF

## ---- middlewares reutilizáveis ------------------------------------------
cat > "${TRAEFIK_DIR}/dynamic/middlewares.yml" <<'EOF'
http:
  middlewares:
    seguranca:
      headers:
        frameDeny: true
        contentTypeNosniff: true
        browserXssFilter: true
        referrerPolicy: "strict-origin-when-cross-origin"
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
    compressao:
      compress: {}
    redirect-www:
      redirectRegex:
        regex: "^https?://www\\.(.+)"
        replacement: "https://${1}"
        permanent: true
EOF

## ---- TLS options (desabilita TLS antigo) --------------------------------
cat > "${TRAEFIK_DIR}/dynamic/tls.yml" <<'EOF'
tls:
  options:
    default:
      minVersion: VersionTLS12
      sniStrict: false
EOF

## ---- stack --------------------------------------------------------------
cat > "${TRAEFIK_DIR}/docker-compose.yml" <<EOF
services:
  traefik:
    image: traefik:v3.6
    container_name: traefik
    restart: always
    command: --configFile=/traefik.yml
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/traefik.yml:ro
      - ./dynamic:/dynamic:ro
      - ./letsencrypt:/letsencrypt
      - ./logs:/logs
    networks:
      - proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(\`${TRAEFIK_DOMAIN}\`)"
      - "traefik.http.routers.dashboard.entrypoints=websecure"
      - "traefik.http.routers.dashboard.service=api@internal"
      - "traefik.http.routers.dashboard.tls.certresolver=le"
      - "traefik.http.routers.dashboard.middlewares=dash-auth"
      - "traefik.http.middlewares.dash-auth.basicauth.users=${HASH//$/\$\$}"

networks:
  proxy:
    external: true
EOF

titulo "Subindo o Traefik"
run "docker compose up -d" docker compose -f "${TRAEFIK_DIR}/docker-compose.yml" up -d
sleep 5
docker ps --filter name=traefik --format '     {{.Names}}  {{.Status}}'

echo ""
info "Dashboard: https://${TRAEFIK_DOMAIN}  (usuário: ${TRAEFIK_USER})"
aviso "O DNS de ${TRAEFIK_DOMAIN} precisa apontar para este IP ANTES do certificado ser emitido."
info "Logs do ACME:  docker logs -f traefik | grep -i acme"
ok "Módulo 03 concluído."
