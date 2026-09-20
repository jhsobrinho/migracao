#!/usr/bin/env bash
## Módulo 05 — Cria as stacks dos 3 sites atrás do Traefik
set -uo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/lib/ui.sh"
carrega_config
checa_root

banner_secao "05 · SITES (3 STACKS ATRÁS DO TRAEFIK)"

cria_site() {
    local nome="$1" dominio="$2" tipo="$3" porta="$4"
    local dir="/opt/stacks/${nome}"
    mkdir -p "${dir}"

    titulo "Site: ${nome} → ${dominio} (${tipo})"

    if [ "$tipo" = "static" ]; then
        mkdir -p "${dir}/public"
        [ -f "${dir}/public/index.html" ] || cat > "${dir}/public/index.html" <<HTML
<!doctype html><html lang="pt-br"><meta charset="utf-8">
<title>${dominio}</title>
<body style="font-family:system-ui;display:grid;place-items:center;height:100vh;margin:0">
<div><h1>${dominio}</h1><p>Stack no ar. Publique seus arquivos em ${dir}/public</p></div>
</body></html>
HTML
        cat > "${dir}/docker-compose.yml" <<EOF
services:
  app:
    image: nginx:1.27-alpine
    container_name: ${nome}
    restart: always
    volumes:
      - ./public:/usr/share/nginx/html:ro
    networks: [proxy, internal]
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=proxy"
      - "traefik.http.routers.${nome}.rule=Host(\`${dominio}\`) || Host(\`www.${dominio}\`)"
      - "traefik.http.routers.${nome}.entrypoints=websecure"
      - "traefik.http.routers.${nome}.tls.certresolver=le"
      - "traefik.http.routers.${nome}.middlewares=redirect-www@file"
      - "traefik.http.services.${nome}.loadbalancer.server.port=80"

networks:
  proxy:    { external: true }
  internal: { external: true }
EOF
    else
        cat > "${dir}/.env" <<EOF
## Preencha com a connection string gerada pelo 'pgcreate ${nome}'
DATABASE_URL=postgresql://${nome}:TROQUE_A_SENHA@postgres:5432/${nome}
NODE_ENV=production
PORT=${porta}
EOF
        chmod 600 "${dir}/.env"
        cat > "${dir}/docker-compose.yml" <<EOF
services:
  app:
    ## TROQUE pela imagem da sua aplicação (ou use 'build: .' com um Dockerfile aqui).
    ## O whoami abaixo é só um placeholder que responde na porta ${porta}.
    image: traefik/whoami
    command: ["--port", "${porta}"]
    container_name: ${nome}
    restart: always
    env_file: .env
    networks: [proxy, internal]
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=proxy"
      - "traefik.http.routers.${nome}.rule=Host(\`${dominio}\`) || Host(\`www.${dominio}\`)"
      - "traefik.http.routers.${nome}.entrypoints=websecure"
      - "traefik.http.routers.${nome}.tls.certresolver=le"
      - "traefik.http.routers.${nome}.middlewares=redirect-www@file"
      - "traefik.http.services.${nome}.loadbalancer.server.port=${porta}"

networks:
  proxy:    { external: true }
  internal: { external: true }
EOF
        aviso "Stack '${nome}' criada com imagem de exemplo. Edite ${dir}/docker-compose.yml"
        aviso "e ${dir}/.env com a senha real do banco antes de colocar em produção."
    fi

    run "Subindo ${nome}" docker compose -f "${dir}/docker-compose.yml" up -d
    info "Arquivos em: ${dir}"
}

for n in 1 2 3; do
    eval "nome=\${SITE${n}_NAME}; dominio=\${SITE${n}_DOMAIN}; tipo=\${SITE${n}_TYPE}; porta=\${SITE${n}_PORT}"
    cria_site "$nome" "$dominio" "$tipo" "$porta"
done

echo ""
docker ps --format '     {{.Names}}\t{{.Status}}' | sed 's/\t/  /'
echo ""
info "Certificados são emitidos no primeiro acesso HTTPS — o DNS precisa estar apontado."
info "Acompanhe:  docker logs -f traefik | grep -iE 'acme|error'"
ok "Módulo 05 concluído."
