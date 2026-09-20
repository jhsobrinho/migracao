#!/usr/bin/env bash
## Módulo 07 — Rotina de backup diária (Postgres + stacks + mailcow)
set -uo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/lib/ui.sh"
carrega_config
checa_root

banner_secao "07 · BACKUP AUTOMÁTICO"

mkdir -p "${BACKUP_DIR}"/{postgres,stacks,mailcow,volumes}

cat > /usr/local/bin/vps-backup <<EOF
#!/usr/bin/env bash
## Backup diário — gerado pelo vps-setup
set -uo pipefail
DATA=\$(date +%F_%H%M)
BACKUP_DIR="${BACKUP_DIR}"
RET=${BACKUP_RETENTION_DAYS}
MAILCOW_PATH="${MAILCOW_PATH}"
log() { echo "\$(date '+%F %T') | \$*" >> \${BACKUP_DIR}/backup.log; }

## 1) PostgreSQL — dump lógico completo
if docker ps --format '{{.Names}}' | grep -qx postgres; then
  docker exec postgres pg_dumpall -U ${PG_SUPERUSER} | gzip > "\${BACKUP_DIR}/postgres/pgdumpall_\${DATA}.sql.gz" \\
    && log "postgres OK" || log "postgres FALHOU"
fi

## 2) Configurações das stacks, do Traefik e credenciais
tar czf "\${BACKUP_DIR}/stacks/config_\${DATA}.tar.gz" \\
  --exclude='*/node_modules' \\
  /opt/stacks /opt/traefik /opt/postgres/.env /opt/vps-setup 2>/dev/null \\
  && log "stacks OK" || log "stacks FALHOU"

## 3) Volumes dos painéis (n8n guarda a encryption key e arquivos binários aqui)
for VOL in n8n_n8n_data portainer_portainer_data; do
  docker volume inspect "\${VOL}" >/dev/null 2>&1 || continue
  docker run --rm -v "\${VOL}":/v:ro -v "\${BACKUP_DIR}/volumes":/out alpine \\
    tar czf "/out/\${VOL}_\${DATA}.tar.gz" -C /v . >/dev/null 2>&1 \\
    && log "volume \${VOL} OK" || log "volume \${VOL} FALHOU"
done

## 4) mailcow (script oficial: mysql, maildir, redis, crypt, rspamd)
if [ -x "\${MAILCOW_PATH}/helper-scripts/backup_and_restore.sh" ]; then
  BACKUP_LOCATION="\${BACKUP_DIR}/mailcow" \\
    "\${MAILCOW_PATH}/helper-scripts/backup_and_restore.sh" backup all --delete-days \${RET} >/dev/null 2>&1 \\
    && log "mailcow OK" || log "mailcow FALHOU"
fi

## 5) Retenção
find "\${BACKUP_DIR}/postgres" -name '*.gz'     -mtime +\${RET} -delete
find "\${BACKUP_DIR}/stacks"   -name '*.tar.gz' -mtime +\${RET} -delete
find "\${BACKUP_DIR}/volumes"  -name '*.tar.gz' -mtime +\${RET} -delete
log "backup finalizado"
EOF
chmod +x /usr/local/bin/vps-backup
ok "Script /usr/local/bin/vps-backup criado"

cron_line="0 ${BACKUP_HOUR} * * * /usr/local/bin/vps-backup"
( crontab -l 2>/dev/null | grep -v 'vps-backup' ; echo "$cron_line" ) | crontab -
ok "Cron diário às ${BACKUP_HOUR}h instalado"

titulo "Executando um backup de teste"
run "vps-backup" /usr/local/bin/vps-backup
du -sh "${BACKUP_DIR}"/* 2>/dev/null | sed 's/^/     /'

echo ""
aviso "Backup local NÃO é backup. Envie ${BACKUP_DIR} para fora da VPS:"
cat <<'EOF'
     # exemplo com rclone (S3/Backblaze/Google Drive):
     apt install -y rclone && rclone config
     echo '30 4 * * * rclone sync /opt/backups remoto:vps-backups' | crontab -
EOF
ok "Módulo 07 concluído."
