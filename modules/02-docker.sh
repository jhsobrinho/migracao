#!/usr/bin/env bash
## Módulo 02 — Docker Engine + Compose plugin + redes
set -uo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/lib/ui.sh"
carrega_config
checa_root

banner_secao "02 · DOCKER"

if command -v docker >/dev/null 2>&1; then
    ok "Docker já instalado: $(docker --version)"
else
    titulo "Instalando Docker (repositório oficial)"
    run "Baixando e executando get.docker.com" bash -c 'curl -fsSL https://get.docker.com | sh'
fi

if docker compose version >/dev/null 2>&1; then
    ok "Compose plugin: $(docker compose version | head -1)"
else
    run "Instalando docker-compose-plugin" apt-get install -y docker-compose-plugin
fi

titulo "Configuração do daemon (log rotation + live-restore)"
mkdir -p /etc/docker
if [ ! -f /etc/docker/daemon.json ]; then
cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true
}
EOF
    run "Reiniciando Docker" systemctl restart docker
else
    aviso "/etc/docker/daemon.json já existe — não foi alterado. Confira log rotation manualmente."
fi
run "Docker no boot" systemctl enable docker

titulo "Redes Docker"
docker network inspect proxy    >/dev/null 2>&1 || run "Criando rede 'proxy' (borda/Traefik)" docker network create proxy
docker network inspect internal >/dev/null 2>&1 || run "Criando rede 'internal' (apps ↔ Postgres)" docker network create --internal internal

titulo "Regras DOCKER-USER (bloqueia portas publicadas que não são públicas)"
## O Docker fura o UFW. Portas internas (8080/8443 do mailcow, 5432 do Postgres)
## são fechadas para a internet aqui, na chain DOCKER-USER (não é limpa em restart).
cat > /usr/local/sbin/docker-user-rules.sh <<'EOF'
#!/usr/bin/env bash
## Recria as regras da chain DOCKER-USER (idempotente)
iptables -F DOCKER-USER 2>/dev/null || iptables -N DOCKER-USER
for porta in 8080 8443 5432 8081; do
  iptables -A DOCKER-USER -p tcp --dport "$porta" ! -s 127.0.0.1 -m conntrack --ctstate NEW -j DROP
done
iptables -A DOCKER-USER -j RETURN
EOF
chmod +x /usr/local/sbin/docker-user-rules.sh
cat > /etc/systemd/system/docker-user-rules.service <<'EOF'
[Unit]
Description=Regras DOCKER-USER
After=docker.service
Requires=docker.service
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/docker-user-rules.sh
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
run "Aplicando regras DOCKER-USER" bash -c 'systemctl daemon-reload && systemctl enable --now docker-user-rules.service'

echo ""
docker --version | sed 's/^/     /'
ok "Módulo 02 concluído."
