#!/usr/bin/env bash
## Módulo 04 — PostgreSQL 16 (container) + criação de bancos por site
set -uo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/lib/ui.sh"
carrega_config
checa_root

banner_secao "04 · POSTGRESQL ${PG_VERSION}"

PG_DIR="/opt/postgres"
mkdir -p "${PG_DIR}"

if [ -z "${PG_PASSWORD}" ]; then
    if [ -f "${PG_DIR}/.env" ]; then
        PG_PASSWORD=$(grep '^POSTGRES_PASSWORD=' "${PG_DIR}/.env" | cut -d= -f2-)
        ok "Reaproveitando senha existente do Postgres"
    else
        PG_PASSWORD="$(senha_aleatoria 28)"
        guarda_credencial "PostgreSQL superuser — ${PG_SUPERUSER} / ${PG_PASSWORD}"
        aviso "Senha do Postgres gerada e salva em ${STATE_DIR}/credenciais.txt"
    fi
fi

cat > "${PG_DIR}/.env" <<EOF
POSTGRES_USER=${PG_SUPERUSER}
POSTGRES_PASSWORD=${PG_PASSWORD}
POSTGRES_DB=postgres
TZ=${TZ}
EOF
chmod 600 "${PG_DIR}/.env"

## Rede 'internal' é --internal: container nela não consegue publicar porta no host.
## Quando o acesso via localhost é pedido, anexamos também uma bridge local.
PORTAS=""
REDES="      - internal"
REDE_EXTRA=""
if [ "${PG_EXPOSE_LOCALHOST}" = "y" ]; then
PORTAS=$(cat <<'EOF'
    ports:
      - "127.0.0.1:5432:5432"
EOF
)
REDES="      - internal
      - dbadmin"
REDE_EXTRA="  dbadmin:
    driver: bridge"
fi

cat > "${PG_DIR}/docker-compose.yml" <<EOF
services:
  postgres:
    image: postgres:${PG_VERSION}-alpine
    container_name: postgres
    restart: always
    env_file: .env
    command:
      - "postgres"
      - "-c" 
      - "max_connections=200"
      - "-c"
      - "shared_buffers=512MB"
      - "-c"
      - "work_mem=8MB"
      - "-c"
      - "log_min_duration_statement=2000"
    volumes:
      - pgdata:/var/lib/postgresql/data
${PORTAS}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${PG_SUPERUSER}"]
      interval: 10s
      timeout: 5s
      retries: 10
    networks:
${REDES}

volumes:
  pgdata:

networks:
  internal:
    external: true
${REDE_EXTRA}
EOF

titulo "Subindo o PostgreSQL"
run "docker compose up -d" docker compose -f "${PG_DIR}/docker-compose.yml" up -d
info "Aguardando healthcheck..."
for _ in $(seq 1 30); do
    docker exec postgres pg_isready -U "${PG_SUPERUSER}" >/dev/null 2>&1 && break
    sleep 2
done
docker exec postgres pg_isready -U "${PG_SUPERUSER}" >/dev/null 2>&1 && ok "Postgres pronto" || falha "Postgres não respondeu"

## ---- helper global: criar banco+usuário ---------------------------------
cat > /usr/local/bin/pgcreate <<'EOF'
#!/usr/bin/env bash
## pgcreate <nome_do_banco> [usuario]  — cria banco + usuário com senha aleatória
set -euo pipefail
DB="$1"; USER="${2:-$1}"
PASS="$(head -c 256 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-24)"
docker exec -i postgres psql -U postgres -v ON_ERROR_STOP=1 <<SQL
SELECT 'CREATE ROLE "${USER}" LOGIN PASSWORD ''${PASS}'''
 WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname='${USER}')\gexec
SELECT 'CREATE DATABASE "${DB}" OWNER "${USER}"'
 WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='${DB}')\gexec
SQL
docker exec -i postgres psql -U postgres -d "${DB}" -c "GRANT ALL ON SCHEMA public TO \"${USER}\";" >/dev/null
echo "Banco: ${DB} | Usuário: ${USER} | Senha: ${PASS}"
echo "DATABASE_URL=postgresql://${USER}:${PASS}@postgres:5432/${DB}"
echo "$(date '+%F %T') | Postgres ${DB} — ${USER} / ${PASS}" >> /opt/vps-setup/credenciais.txt
EOF
chmod +x /usr/local/bin/pgcreate
ok "Helper 'pgcreate <banco> [usuario]' instalado"

titulo "Criando um banco por site"
for n in 1 2 3; do
    eval "nome=\${SITE${n}_NAME}"
    if docker exec postgres psql -U "${PG_SUPERUSER}" -tAc "SELECT 1 FROM pg_database WHERE datname='${nome}'" | grep -q 1; then
        ok "Banco '${nome}' já existe"
    else
        /usr/local/bin/pgcreate "${nome}" | sed 's/^/     /'
    fi
done

echo ""
info "Conexão a partir dos containers:  host=postgres  porta=5432  (rede docker 'internal')"
info "Conexão administrativa do seu PC:  ssh -L 5432:127.0.0.1:5432 root@SEU_IP"
info "Credenciais em ${STATE_DIR}/credenciais.txt"
ok "Módulo 04 concluído."
