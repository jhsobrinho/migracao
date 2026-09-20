#!/usr/bin/env bash
## Módulo 01 — Base do sistema: pacotes, timezone, swap, SSH, firewall, updates
set -uo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/lib/ui.sh"
carrega_config
checa_root

banner_secao "01 · BASE DO SISTEMA"
checa_so

titulo "Pacotes"
export DEBIAN_FRONTEND=noninteractive
run "apt update"                       apt-get update
run "apt upgrade"                      apt-get upgrade -y
run "Pacotes essenciais"               apt-get install -y \
    sudo curl wget git jq nano htop ca-certificates gnupg lsb-release \
    apt-transport-https software-properties-common apache2-utils \
    unzip tar cron rsync dnsutils net-tools ufw fail2ban unattended-upgrades \
    python3 python3-pip tzdata

titulo "Fuso horário e relógio"
run "Timezone ${TZ}"                   timedatectl set-timezone "$TZ"
run "NTP ativo"                        timedatectl set-ntp true

titulo "Swap (mailcow exige RAM + swap)"
mem_gb=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
info "RAM detectada: ${mem_gb} GB"
if [ "$mem_gb" -lt 6 ]; then
    aviso "O mailcow pede no mínimo 6 GB de RAM. Considere um plano maior na Contabo."
fi
if ! swapon --show | grep -q .; then
    run "Criando swapfile de 4G"       bash -c 'fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile'
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    ok "Swap habilitado e persistente em /etc/fstab"
else
    ok "Swap já existe: $(swapon --show --noheadings --bytes | awk '{print $3}' | head -1) bytes"
fi
sysctl -w vm.swappiness=10 >/dev/null
grep -q 'vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf

titulo "Hostname"
info "Hostname atual: $(hostname -f 2>/dev/null || hostname)"
aviso "O hostname do servidor NÃO precisa ser o do mailcow, mas mantenha um FQDN válido."

titulo "SSH"
if confirma "Desabilitar login por senha no SSH (só chave)? Só faça se sua chave JÁ funciona" "n"; then
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    run "Reiniciando SSH"              systemctl restart ssh || systemctl restart sshd
fi

titulo "Fail2ban (host) e updates automáticos"
cat > /etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled  = true
port     = ${SSH_PORT}
maxretry = 5
bantime  = 1h
findtime = 10m
EOF
run "fail2ban habilitado"              systemctl enable --now fail2ban
run "Updates de segurança automáticos" bash -c 'echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections && dpkg-reconfigure -f noninteractive unattended-upgrades'

titulo "Firewall (UFW)"
aviso "Atenção: o Docker publica portas direto no iptables e IGNORA o UFW."
aviso "Por isso usamos UFW para o host + regras na chain DOCKER-USER (módulo do Traefik/mailcow)."
ufw --force reset >/dev/null 2>&1
ufw default deny incoming  >/dev/null
ufw default allow outgoing >/dev/null
for p in "${SSH_PORT}/tcp" 80/tcp 443/tcp 25/tcp 465/tcp 587/tcp 143/tcp 993/tcp 110/tcp 995/tcp 4190/tcp; do
    ufw allow "$p" >/dev/null
done
run "Ativando UFW"                     bash -c 'ufw --force enable'
ufw status numbered | sed 's/^/     /'

titulo "Teste de saída na porta 25 (obrigatório para enviar e-mail)"
if timeout 10 bash -c 'cat < /dev/null > /dev/tcp/gmail-smtp-in.l.google.com/25' 2>/dev/null; then
    ok "Porta 25 de SAÍDA liberada — o mailcow vai conseguir entregar e-mails"
else
    falha "Porta 25 de SAÍDA bloqueada"
    aviso "Abra um ticket na Contabo pedindo a liberação da porta 25 (outbound) e, se o IP tiver"
    aviso "reputação ruim, peça a troca do IP. Sem isso o mailcow recebe, mas NÃO envia."
fi

echo ""
ok "Módulo 01 concluído."
