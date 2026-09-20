#!/usr/bin/env bash
## Módulo 09 — Painéis: Portainer, pgAdmin e n8n (todos atrás do Traefik)
set -uo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/lib/ui.sh"
carrega_config
checa_root

banner_secao "09 · PAINÉIS (PORTAINER · PGADMIN · N8N)"

INSTALL_PORTAINER="${INSTALL_PORTAINER:-y}"
INSTALL_PGADMIN="${INSTALL_PGADMIN:-y}"
INSTALL_N8N="${INSTALL_N8N:-y}"

## Recupera uma senha já registrada em credenciais.txt (evita trocar a cada rerun)
senha_registrada() {
    [ -f "${STATE_DIR}/credenciais.txt" ] || return 1
    grep -F "$1" "${STATE_DIR}/credenciais.txt" 2>/dev/null | tail -1 | awk '{print $NF}'
}

sobe() {
    local dir="$1" nome="$2"
    run "Subindo ${nome}" docker compose -f "${dir}/docker-compose.yml" up -d
    info "Arquivos em: ${dir}"
}

## ---- Portainer -----------------------------------------------------------
if [ "${INSTALL_PORTAINER}" = "y" ]; then
    titulo "Portainer → ${PORTAINER_DOMAIN}"
    DIR="/opt/stacks/portainer"; mkdir -p "${DIR}"
    cat > "${DIR}/docker-compose.yml" <<EOF
services:
  portainer:
    image: portainer/portainer-ce:2.21.5
    container_name: portainer
    restart: always
    command: -H unix:///var/run/docker.sock
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks: [proxy]
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=proxy"
      - "traefik.http.routers.portainer.rule=Host(\`${PORTAINER_DOMAIN}\`)"
      - "traefik.http.routers.portainer.entrypoints=websecure"
      - "traefik.http.routers.portainer.tls.certresolver=le"
      - "traefik.http.services.portainer.loadbalancer.server.port=9000"

volumes:
  portainer_data:

networks:
  proxy: { external: true }
EOF
    sobe "${DIR}" portainer
    aviso "Crie o usuário admin em https://${PORTAINER_DOMAIN} nos primeiros minutos —"
    aviso "depois disso o Portainer bloqueia o cadastro e exige reiniciar o container."
fi

## ---- pgAdmin -------------------------------------------------------------
if [ "${INSTALL_PGADMIN}" = "y" ]; then
    titulo "pgAdmin → ${PGADMIN_DOMAIN}"
    DIR="/opt/stacks/pgadmin"; mkdir -p "${DIR}"

    PGADMIN_PASSWORD="$(senha_registrada 'pgAdmin' || true)"
    if [ -z "${PGADMIN_PASSWORD}" ]; then
        PGADMIN_PASSWORD="$(senha_aleatoria 20)"
        guarda_credencial "pgAdmin — ${PGADMIN_EMAIL} / ${PGADMIN_PASSWORD}"
    else
        ok "Reaproveitando a senha do pgAdmin já registrada"
    fi

    cat > "${DIR}/.env" <<EOF
PGADMIN_DEFAULT_EMAIL=${PGADMIN_EMAIL}
PGADMIN_DEFAULT_PASSWORD=${PGADMIN_PASSWORD}
PGADMIN_CONFIG_ENHANCED_COOKIE_PROTECTION=True
PGADMIN_LISTEN_PORT=80
EOF
    chmod 600 "${DIR}/.env"

    cat > "${DIR}/docker-compose.yml" <<EOF
services:
  pgadmin:
    image: dpage/pgadmin4:8.12
    container_name: pgadmin
    restart: always
    env_file: .env
    user: "5050:5050"
    volumes:
      - pgadmin_data:/var/lib/pgadmin
    networks: [proxy, internal]
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=proxy"
      - "traefik.http.routers.pgadmin.rule=Host(\`${PGADMIN_DOMAIN}\`)"
      - "traefik.http.routers.pgadmin.entrypoints=websecure"
      - "traefik.http.routers.pgadmin.tls.certresolver=le"
      - "traefik.http.services.pgadmin.loadbalancer.server.port=80"

volumes:
  pgadmin_data:

networks:
  proxy:    { external: true }
  internal: { external: true }
EOF
    sobe "${DIR}" pgadmin
    info "Login: ${PGADMIN_EMAIL} — senha em ${STATE_DIR}/credenciais.txt"
    info "Ao adicionar o servidor no pgAdmin use host 'postgres', porta 5432."
fi

## ---- n8n -----------------------------------------------------------------
if [ "${INSTALL_N8N}" = "y" ]; then
    titulo "n8n → ${N8N_DOMAIN}"
    DIR="/opt/stacks/n8n"; mkdir -p "${DIR}"

    ## Banco dedicado no Postgres já existente
    if docker exec postgres psql -U "${PG_SUPERUSER}" -tAc \
         "SELECT 1 FROM pg_database WHERE datname='n8n'" 2>/dev/null | grep -q 1; then
        ok "Banco 'n8n' já existe"
        N8N_DB_PASS="$(senha_registrada 'Postgres n8n' || true)"
    else
        /usr/local/bin/pgcreate n8n | sed 's/^/     /'
        N8N_DB_PASS="$(senha_registrada 'Postgres n8n' || true)"
    fi
    if [ -z "${N8N_DB_PASS}" ]; then
        falha "Não encontrei a senha do banco n8n — rode 'pgcreate n8n' e edite ${DIR}/.env"
        N8N_DB_PASS="TROQUE_A_SENHA"
    fi

    ## Chave de criptografia das credenciais do n8n: NUNCA pode mudar depois
    N8N_KEY="$(senha_registrada 'n8n encryption key' || true)"
    if [ -z "${N8N_KEY}" ]; then
        N8N_KEY="$(senha_aleatoria 40)"
        guarda_credencial "n8n encryption key — ${N8N_KEY}"
    else
        ok "Reaproveitando a encryption key do n8n"
    fi

    cat > "${DIR}/.env" <<EOF
## Trocar N8N_ENCRYPTION_KEY depois de criar credenciais TORNA TODAS ELAS ILEGÍVEIS.
N8N_ENCRYPTION_KEY=${N8N_KEY}
N8N_HOST=${N8N_DOMAIN}
N8N_PORT=5678
N8N_PROTOCOL=https
WEBHOOK_URL=https://${N8N_DOMAIN}/
N8N_EDITOR_BASE_URL=https://${N8N_DOMAIN}/
GENERIC_TIMEZONE=${TZ}
TZ=${TZ}
N8N_PROXY_HOPS=1
N8N_RUNNERS_ENABLED=true
N8N_DIAGNOSTICS_ENABLED=false
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_PASSWORD=${N8N_DB_PASS}
EOF
    chmod 600 "${DIR}/.env"

    cat > "${DIR}/docker-compose.yml" <<EOF
services:
  n8n:
    image: n8nio/n8n:1.68.0
    container_name: n8n
    restart: always
    env_file: .env
    volumes:
      - n8n_data:/home/node/.n8n
      - ./files:/files
    networks: [proxy, internal]
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=proxy"
      - "traefik.http.routers.n8n.rule=Host(\`${N8N_DOMAIN}\`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls.certresolver=le"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"

volumes:
  n8n_data:

networks:
  proxy:    { external: true }
  internal: { external: true }
EOF
    mkdir -p "${DIR}/files"
    sobe "${DIR}" n8n
    aviso "O primeiro acesso a https://${N8N_DOMAIN} cria a conta de owner — faça isso logo."
fi

echo ""
docker ps --format '     {{.Names}}\t{{.Status}}' | sed 's/\t/  /'
echo ""
info "Registros DNS necessários (A → IP da VPS): ${PORTAINER_DOMAIN}, ${PGADMIN_DOMAIN}, ${N8N_DOMAIN}"
info "Credenciais em ${STATE_DIR}/credenciais.txt"
ok "Módulo 09 concluído."
