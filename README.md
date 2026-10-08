# Roteiro de Setup/Deploy — VPS Contabo
### 3 sites + PostgreSQL + Mailcow, tudo atrás de um Traefik

Scripts no mesmo estilo do seu SetupOrion (menu, banners, `[ OK ] / [ FAIL ]`),
mas divididos em módulos idempotentes — dá para rodar de novo sem quebrar nada.

---

## 1. Arquitetura

```
                    Internet
                       │
        ┌──────────────┴───────────────┐
        │  80/443                      │  25 · 465 · 587 · 143 · 993 · 110 · 995 · 4190
        ▼                              ▼
   ┌─────────────┐              ┌──────────────────┐
   │  TRAEFIK v3 │              │  postfix/dovecot │
   │  TLS (LE)   │              │   (mailcow)      │
   └──┬───┬───┬──┘              └────────┬─────────┘
      │   │   │  rede docker "proxy"     │
      │   │   └──────────────────────────┘  (nginx-mailcow :8080  →  mail.dominio)
      │   │
      ▼   ▼
  site1  site2  site3        rede docker "internal" (sem rota p/ internet)
      │     │     │                       │
      └─────┴─────┴───────────────────────┴──►  PostgreSQL 16 (sem porta pública)
```

Decisões-chave:

| Ponto | Escolha | Por quê |
|---|---|---|
| Proxy | **Traefik v3** dono do 80/443 | um só lugar emite/renova certificados dos 3 sites + painel do mailcow |
| Certificado do mailcow | `SKIP_LETS_ENCRYPT=y` + **certdumper** | o mailcow não pode disputar a porta 80 com o Traefik; o certdumper copia o cert do Traefik para postfix/dovecot ([doc oficial, Traefik v3](https://docs.mailcow.email/post_installation/reverse-proxy/r_p-traefik3/)) |
| Bind do mailcow | `HTTP_PORT=8080`, `HTTP_BIND=` **vazio** | com bind em `127.0.0.1` o nginx do mailcow escuta só no loopback *dentro do container* e o Traefik não alcança ([doc](https://docs.mailcow.email/post_installation/reverse-proxy/r_p/)) |
| Postgres | container único, rede `internal`, sem porta pública | acesso administrativo só por túnel SSH |
| Firewall | UFW + chain `DOCKER-USER` | o Docker publica portas direto no iptables e **ignora o UFW** |
| Versão do Traefik | **v3.6** (não 3.3) | o Docker Engine 29 recusa a API 1.24 usada pelo Traefik antigo — é exatamente o problema que o `DOCKER_MIN_API_VERSION=1.24` do SetupOrion contorna. Com o Traefik 3.6 não é preciso afrouxar o daemon |

---

## 2. Pré-requisitos

**VPS (Contabo)**
- Mailcow sozinho pede **6 GB de RAM + 1 GB de swap**. Com 3 sites + Postgres, vá de
  **VPS 2 (8 GB) no mínimo**; **VPS 3 (16 GB)** se for usar ClamAV + SOGo + apps Node/PHP.
  Em 8 GB, deixe `MAILCOW_SKIP_CLAMAV="y"`.
- Disco: 20 GB só para o mailcow sem e-mails. Considere 200 GB+.
- SO: **Debian 12** (recomendado) ou Ubuntu 22.04/24.04. Nada de LXC/OpenVZ — o mailcow
  não roda; na Contabo peça/escolha KVM.

**Rede — checar ANTES de tudo**
1. Porta **25 de saída** aberta. A Contabo não bloqueia por padrão, mas clampa IPs com
   histórico de abuso. Teste: `nc -zv gmail-smtp-in.l.google.com 25` (ou `./setup.sh 8`).
   Bloqueado → ticket pedindo liberação da 25 e, se o IP estiver sujo, troca de IP.
2. **rDNS/PTR** do IP apontando para `mail.seudominio.com.br` (painel da Contabo).
3. IP fora de blacklists — o módulo 8 checa Spamhaus/SpamCop/Barracuda.

**DNS** — veja [`dns/DNS.md`](dns/DNS.md). Os registros A precisam estar propagados
**antes** de subir o Traefik, senão o Let's Encrypt falha (e tem rate limit: 5 falhas/hora).

---

## 3. Instalação

```bash
# na VPS, como root
apt update && apt install -y git
git clone <seu-repo> /opt/vps-setup-src   # ou envie a pasta via scp
cd /opt/vps-setup-src

# o config.conf já vem preenchido com algoritmovivo.com.br / mavi-ai.com.br / mavix-ai.com.br,
# mail.algoritmovivo.com.br e ACME monitor.call@gmail.com — só confira:
nano config.conf

chmod +x setup.sh
./setup.sh                  # menu interativo
```

Também dá para rodar direto: `./setup.sh 1 2 3 4 5` ou `./setup.sh all`.

### Ordem dos módulos

| # | Módulo | O que faz | Tempo |
|---|---|---|---|
| 1 | `01-base` | apt upgrade, pacotes, timezone, **swap 4G**, SSH, UFW, fail2ban, unattended-upgrades, teste da porta 25 | ~5 min |
| 2 | `02-docker` | Docker + compose, log rotation, redes `proxy` e `internal`, regras `DOCKER-USER` | ~3 min |
| 3 | `03-traefik` | Traefik v3, redirect 80→443, HSTS, gzip, dashboard com senha | ~2 min |
| 4 | `04-postgres` | Postgres 16 + healthcheck + helper `pgcreate` + 1 banco por site | ~2 min |
| 5 | `05-sites` | 3 stacks em `/opt/stacks/<nome>` com labels do Traefik e redirect www | ~2 min |
| 6 | `06-mailcow` | clone, `mailcow.conf` ajustado p/ proxy, override com labels + certdumper, `up -d` | ~15 min |
| 9 | `09-paineis` | Portainer, pgAdmin e n8n atrás do Traefik (n8n já no Postgres) | ~3 min |
| 7 | `07-backup` | `/usr/local/bin/vps-backup` + cron diário + retenção | ~2 min |
| 8 | `08-checks` | DNS, PTR, SPF/DKIM/DMARC, portas, certificados, blacklists, recursos | ~1 min |

Tudo que é gerado (senhas do Traefik, Postgres, bancos, pgAdmin, chave do n8n) vai para
`/opt/vps-setup/credenciais.txt` (chmod 600) — opção **c** do menu mostra o arquivo.

### Subdomínios criados

| Subdomínio | Serviço | Login |
|---|---|---|
| `mail.algoritmovivo.com.br` | mailcow (painel + SMTP/IMAP dos 3 domínios) | `admin` / `moohoo` — trocar no 1º acesso |
| `traefik.algoritmovivo.com.br` | dashboard do Traefik | Basic Auth, senha em `credenciais.txt` |
| `portainer.algoritmovivo.com.br` | Portainer CE | admin criado no 1º acesso |
| `pgadmin.algoritmovivo.com.br` | pgAdmin 4 | `monitor.call@gmail.com` + senha gerada |
| `n8n.algoritmovivo.com.br` | n8n | owner criado no 1º acesso |
| `autoconfig.` / `autodiscover.` | CNAME p/ o `mail.` (nos 3 domínios) | — |

---

## 4. Depois de rodar

### Sites
- Estático: jogue os arquivos em `/opt/stacks/algoritmovivo/public` (e `/opt/stacks/mavi/public`).
- App próprio: edite `/opt/stacks/mavix/docker-compose.yml` (troque a imagem ou use
  `build: .`), preencha `.env` com a `DATABASE_URL` que o `pgcreate` imprimiu e
  `docker compose up -d --build`.
- Novo site depois: copie uma pasta de `/opt/stacks`, troque nome/domínio nas labels,
  rode `pgcreate novosite` e suba. O Traefik detecta sozinho.

### Mailcow
1. `https://mail.seudominio.com.br` → `admin` / `moohoo` → **troque a senha e ative 2FA**.
2. E-mail → Domínios → adicione os 3 domínios → crie as caixas.
3. Copie o **DKIM** de cada domínio e publique no DNS.
4. Publique MX/SPF/DMARC (`dns/DNS.md`).
5. Valide em https://www.mail-tester.com — meta 10/10 — e https://mxtoolbox.com/deliverability.

### Painéis
- **Portainer**: crie o admin nos primeiros minutos — depois disso ele trava o cadastro por
  segurança e exige `docker restart portainer`.
- **pgAdmin**: ao cadastrar o servidor use host `postgres`, porta `5432`, usuário/senha do
  `credenciais.txt`. Nada de expor o 5432 para fora.
- **n8n**: usa o banco `n8n` no Postgres e a `N8N_ENCRYPTION_KEY` de `/opt/stacks/n8n/.env`.
  **Nunca troque essa chave** depois de salvar credenciais — todas ficam ilegíveis. Ela e o
  volume `n8n_n8n_data` entram no backup.

### Aquecimento do IP
IP novo = reputação zero. Nas primeiras 2 semanas mande volume baixo e crescente
(dezenas/dia), evite listas grandes e monitore bounces. Para disparo em massa
(newsletter/transacional alto), use relay externo (Amazon SES, Mailgun, Postmark)
— a Contabo limita na prática algo em torno de 25 msg/min.

---

## 5. Operação do dia a dia

```bash
# status geral
./setup.sh 8

# logs
docker logs -f traefik
cd /opt/mailcow-dockerized && docker compose logs -f postfix-mailcow

# atualizar mailcow (faça backup antes)
cd /opt/mailcow-dockerized && ./update.sh

# atualizar Traefik / sites
cd /opt/traefik && docker compose pull && docker compose up -d

# backup manual
vps-backup && ls -lh /opt/backups/*

# restaurar mailcow
/opt/mailcow-dockerized/helper-scripts/backup_and_restore.sh restore

# restaurar Postgres
gunzip -c /opt/backups/postgres/pgdumpall_AAAA-MM-DD_HHMM.sql.gz | docker exec -i postgres psql -U postgres

# banco novo
pgcreate meuapp
```

Túnel para abrir o Postgres no DBeaver/pgAdmin do seu PC:
`ssh -L 5432:127.0.0.1:5432 root@IP_DA_VPS`

---

## 6. Troubleshooting

| Sintoma | Causa provável | Ação |
|---|---|---|
| Certificado não emite | DNS ainda não propagou, ou porta 80 fechada | `dig +short A dominio`; `docker logs traefik \| grep -i acme`; cuidado com o rate limit do LE |
| Site dá 404 no Traefik | container não está na rede `proxy` ou faltou `traefik.enable=true` | `docker inspect <ct> \| grep -A5 Networks` |
| Painel do mailcow 502 | `HTTP_BIND` não ficou vazio, ou nginx-mailcow fora da rede `proxy` | conferir `mailcow.conf` + `docker-compose.override.yml`, depois `docker compose up -d` |
| Webmail abre mas IMAP/SMTP dá erro de certificado | certdumper não copiou o cert | `docker logs traefik_certdumper`; confira os nomes em `--restart-containers` com `docker ps --format '{{.Names}}'` |
| E-mail sai mas cai em spam | PTR/SPF/DKIM/DMARC | `./setup.sh 8` + mail-tester |
| Não envia nada para fora | porta 25 de saída clampada | ticket na Contabo |
| Porta interna exposta | regra `DOCKER-USER` sumiu | `systemctl restart docker-user-rules` |
| `apt` reclama de postfix no host | MTA nativo instalado | `apt purge postfix exim4` |
| Painel do mailcow em loop de redirect | `HTTP_REDIRECT=y` atrás do Traefik | `HTTP_REDIRECT=n` no `mailcow.conf` + `docker compose up -d nginx-mailcow` |
| "Falha no login" com admin/moohoo | a tela inicial é só para caixas de e-mail | entrar em `/admin`; senha perdida: `helper-scripts/mailcow-reset-admin.sh` |
| Gmail recusa com 5.7.25 "no PTR" | postfix saiu pelo IPv6 da VPS (sem PTR) | `ENABLE_IPV6=false` no `mailcow.conf` + `docker compose down && up -d` |
| Módulo 8 diz "LISTADO em Spamhaus" com 127.255.255.x | resolver público bloqueado, não é listagem | confira em https://check.spamhaus.org/ |

---

## 7. Estrutura de arquivos na VPS

```
/opt/traefik/            traefik.yml, dynamic/, letsencrypt/acme.json, logs/
/opt/postgres/           docker-compose.yml, .env  (volume pgdata)
/opt/stacks/site1|2|3/   docker-compose.yml, public/ ou .env
/opt/mailcow-dockerized/ mailcow.conf, docker-compose.override.yml, data/
/opt/backups/            postgres/ stacks/ mailcow/ backup.log
/opt/vps-setup/          setup.log, credenciais.txt
```

---

## 8. O que já foi testado

Os módulos 3, 4, 5, 7 e 8 foram executados de ponta a ponta numa máquina Linux com Docker 29:
Traefik no ar roteando os 3 hosts, redirect 80→443 e `www`, HSTS/`X-Frame-Options` aplicados,
dashboard exigindo Basic Auth (401 sem senha / 200 com senha), Postgres com os 3 bancos criados
pelo `pgcreate`, acesso em `127.0.0.1:5432`, dump `pg_dumpall` gerado e diagnóstico completo.
O que **não** dá para testar fora da VPS real: emissão de certificado Let's Encrypt, porta 25,
PTR e o mailcow completo (o módulo 6 foi validado só na geração de `mailcow.conf` e do override).

Dois problemas reais foram encontrados e já corrigidos nos scripts:
- Traefik 3.3 não fala com o Docker 29 (erro `client version 1.24 is too old`) → fixado em 3.6.
- Container em rede `--internal` não consegue publicar porta no host → o Postgres ganhou uma
  bridge extra (`dbadmin`) quando `PG_EXPOSE_LOCALHOST="y"`.

---

## 9. Referências

- mailcow — [pré-requisitos](https://docs.mailcow.email/getstarted/prerequisite-system/) ·
  [proxy reverso](https://docs.mailcow.email/post_installation/reverse-proxy/r_p/) ·
  [Traefik v3](https://docs.mailcow.email/post_installation/reverse-proxy/r_p-traefik3/)
- Traefik v3 — https://doc.traefik.io/traefik/
- Contabo — [portas e firewall](https://help.contabo.com/en/support/solutions/articles/103000406861-managing-port-access-and-os-level-firewall-on-your-server)
