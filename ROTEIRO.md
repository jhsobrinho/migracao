# Roteiro passo a passo — VPS Contabo `94.72.125.233`

Sites: **algoritmovivo.com.br** · **mavi-ai.com.br** · **mavix-ai.com.br**
E-mail: **mailcow** em `mail.algoritmovivo.com.br` (atende os três domínios)
Painéis: `traefik.` · `portainer.` · `pgadmin.` · `n8n.algoritmovivo.com.br`

Tempo total: ~1h de trabalho + espera de propagação de DNS.
Faça na ordem. Cada etapa tem um "como conferir" — não avance sem o OK.

---

## ETAPA 0 — Antes de tudo (5 min)

**0.1 — Sistema da VPS.** No painel da Contabo, a VPS precisa estar com **Debian 12** (ou
Ubuntu 22.04/24.04) e ser **KVM**. Se estiver em outro SO, reinstale agora — é destrutivo,
então faça antes de qualquer coisa.

**0.2 — Memória.** O mailcow sozinho pede 6 GB + swap. Se a VPS tiver 8 GB, deixe
`MAILCOW_SKIP_CLAMAV="y"` no `config.conf`. Confira depois de entrar:

```bash
free -h && nproc && df -h /
```

**0.3 — Acesso.** Teste o SSH do seu PC:

```bash
ssh root@94.72.125.233
```

---

## ETAPA 1 — PTR / rDNS no painel da Contabo (5 min, propaga em minutos/horas)

Hoje o PTR do IP é `vmi2753134.contaboserver.net`. **Precisa virar o hostname do mailcow**,
senão Gmail e Outlook rejeitam ou jogam tudo em spam.

1. Entre em https://my.contabo.com → **Your Services** → sua VPS.
2. Procure **IP Management / rDNS** (às vezes em *Manage → Networking*).
3. No IPv4 `94.72.125.233`, troque o valor para:

```
mail.algoritmovivo.com.br
```

4. Se tiver IPv6, faça o mesmo no IPv6.

**Como conferir** (pode demorar; siga adiante enquanto isso):

```bash
dig +short -x 94.72.125.233
# esperado: mail.algoritmovivo.com.br.
```

---

## ETAPA 2 — Porta 25 de saída (5 min)

A Contabo não bloqueia por padrão, mas restringe IPs com histórico ruim. Teste **de dentro da VPS**:

```bash
ssh root@94.72.125.233
timeout 10 bash -c 'cat </dev/null >/dev/tcp/gmail-smtp-in.l.google.com/25' && echo LIBERADA || echo BLOQUEADA
```

- **LIBERADA** → siga.
- **BLOQUEADA** → abra ticket na Contabo agora (demora algumas horas), texto sugerido:

> Hello, I need outbound SMTP (port 25) enabled on my VPS `94.72.125.233`. I will run a
> legitimate mail server (mailcow) for my own domains, with proper rDNS, SPF, DKIM and DMARC.
> If this IP has a bad reputation history, please also consider assigning a clean IP.

Você pode continuar todas as outras etapas enquanto o ticket anda. Só não rode o módulo 6.

---

## ETAPA 3 — DNS (15 min + propagação)

Onde editar: **algoritmovivo.com.br** e **mavix-ai.com.br** estão na HostGator
(`ns56/ns57.hostgator.com.br`); **mavi-ai.com.br** está no Registro.br (`a/b.auto.dns.br`).

**3.1 — Limpe o que sobrou do teste antigo:** A `192.185.213.181`, MX `mx1/mx2.titan.email`,
SPF `include:spf.titan.email` e o `MX 0 .` do mavi-ai.

**3.2 — algoritmovivo.com.br**

| Tipo  | Nome                 | Valor |
|-------|----------------------|-------|
| A     | `@`                  | `94.72.125.233` |
| A     | `www`                | `94.72.125.233` |
| A     | `mail`               | `94.72.125.233` |
| A     | `traefik`            | `94.72.125.233` |
| A     | `portainer`          | `94.72.125.233` |
| A     | `pgadmin`            | `94.72.125.233` |
| A     | `n8n`                | `94.72.125.233` |
| MX    | `@`                  | `mail.algoritmovivo.com.br.` prio **10** |
| TXT   | `@`                  | `v=spf1 mx a:mail.algoritmovivo.com.br -all` |
| TXT   | `_dmarc`             | `v=DMARC1; p=quarantine; rua=mailto:dmarc@algoritmovivo.com.br; adkim=s; aspf=s` |
| CNAME | `autoconfig`         | `mail.algoritmovivo.com.br.` |
| CNAME | `autodiscover`       | `mail.algoritmovivo.com.br.` |

**3.3 — mavi-ai.com.br e mavix-ai.com.br** (iguais entre si, trocando o domínio no DMARC)

| Tipo  | Nome           | Valor |
|-------|----------------|-------|
| A     | `@`            | `94.72.125.233` |
| A     | `www`          | `94.72.125.233` |
| MX    | `@`            | `mail.algoritmovivo.com.br.` prio **10** |
| TXT   | `@`            | `v=spf1 mx a:mail.algoritmovivo.com.br -all` |
| TXT   | `_dmarc`       | `v=DMARC1; p=quarantine; rua=mailto:dmarc@mavi-ai.com.br; adkim=s; aspf=s` |
| CNAME | `autoconfig`   | `mail.algoritmovivo.com.br.` |
| CNAME | `autodiscover` | `mail.algoritmovivo.com.br.` |

Não crie `mail`, `traefik`, `portainer`, `pgadmin` nem `n8n` nesses dois — eles usam o `mail.`
do algoritmovivo.

**DKIM fica para a ETAPA 8** — a chave só existe depois que o mailcow subir.

**Como conferir** (espere até responder certo, geralmente 15–60 min):

```bash
dig +short A algoritmovivo.com.br mavi-ai.com.br mavix-ai.com.br \
            mail.algoritmovivo.com.br n8n.algoritmovivo.com.br
# todos devem responder 94.72.125.233
```

> Se algum dia colocar Cloudflare na frente: `mail.`, `autoconfig.`, `autodiscover.`, MX, SPF,
> DKIM e DMARC têm que ficar **DNS only** (nuvem cinza).

---

## ETAPA 4 — Subir os scripts para a VPS (5 min)

Do **seu PC**, na pasta onde está o zip:

```bash
scp vps-setup-contabo.zip root@94.72.125.233:/root/
```

Na **VPS**:

```bash
ssh root@94.72.125.233
apt update && apt install -y unzip
unzip -o /root/vps-setup-contabo.zip -d /opt
cd /opt/vps-setup
chmod +x setup.sh
cat config.conf        # confira domínios, hostname do mailcow e ACME_EMAIL
```

O `config.conf` já vem preenchido com os seus domínios e `monitor.call@gmail.com`.
Se a VPS tiver 8 GB de RAM, mude `MAILCOW_SKIP_CLAMAV="y"`.

---

## ETAPA 5 — Base, Docker, Traefik, Postgres, sites e painéis (~20 min)

```bash
cd /opt/vps-setup
./setup.sh 1      # base: pacotes, swap, timezone, SSH, UFW, fail2ban  (~5 min)
./setup.sh 2      # docker + compose + redes                            (~3 min)
./setup.sh 3      # traefik (80/443 + Let's Encrypt)                    (~2 min)
./setup.sh 4      # postgres 16 + 1 banco por site                      (~2 min)
./setup.sh 5      # os 3 sites                                          (~2 min)
./setup.sh 9      # portainer + pgadmin + n8n                           (~3 min)
```

Ou tudo de uma vez: `./setup.sh 1 2 3 4 5 9`.

**Como conferir**, do seu PC:

```bash
curl -I https://algoritmovivo.com.br
curl -I https://mavi-ai.com.br
curl -I https://mavix-ai.com.br
```

Tem que vir `HTTP/2 200` com certificado válido (sem aviso do navegador). Se der erro de
certificado, veja o motivo:

```bash
docker logs traefik | grep -iE 'acme|error' | tail -20
```

> Erro comum: DNS ainda não propagado quando o Traefik pediu o certificado. Espere propagar e
> reinicie: `cd /opt/traefik && docker compose restart`.

**Guarde as senhas geradas:**

```bash
cat /opt/vps-setup/credenciais.txt
```

---

## ETAPA 6 — Primeiro acesso aos painéis (10 min) — faça logo

| URL | O que fazer |
|---|---|
| https://portainer.algoritmovivo.com.br | **Criar o admin nos primeiros minutos.** Passou do prazo, ele trava: `docker restart portainer` e refaça. |
| https://n8n.algoritmovivo.com.br | Criar a conta de owner. |
| https://pgadmin.algoritmovivo.com.br | Login com `monitor.call@gmail.com` e a senha do `credenciais.txt`. Ao adicionar o servidor: host `postgres`, porta `5432`. |
| https://traefik.algoritmovivo.com.br | Usuário `admin`, senha do `credenciais.txt`. |

---

## ETAPA 7 — Conteúdo dos sites

**Sites estáticos** (algoritmovivo e mavi-ai) — jogue os arquivos em:

```
/opt/stacks/algoritmovivo/public/
/opt/stacks/mavi/public/
```

Do seu PC: `scp -r ./meu-site/* root@94.72.125.233:/opt/stacks/algoritmovivo/public/`
Não precisa reiniciar nada.

**mavix-ai (app)** — hoje está com um placeholder. Edite
`/opt/stacks/mavix/docker-compose.yml`, troque `image: traefik/whoami` pela imagem da sua
aplicação (ou `build: .` com um Dockerfile na pasta), ajuste a porta se não for 3000, preencha
a `DATABASE_URL` em `/opt/stacks/mavix/.env` (senha em `credenciais.txt`) e:

```bash
cd /opt/stacks/mavix && docker compose up -d --build
```

---

## ETAPA 8 — Mailcow (~20 min) — só depois do PTR + porta 25 OK

**8.1 — Confira os pré-requisitos:**

```bash
cd /opt/vps-setup && ./setup.sh 8
```

Precisa estar OK: A do `mail.`, PTR, porta 25 de saída. Se algum falhar, **pare aqui**.

**8.2 — Instale:**

```bash
./setup.sh 6        # clone + config + up -d   (~15 min baixando imagens)
```

**8.3 — Painel** https://mail.algoritmovivo.com.br

1. Login `admin` / `moohoo` → **troque a senha imediatamente** e ative 2FA.
2. **E-mail → Domínios → Adicionar**: `algoritmovivo.com.br`, `mavi-ai.com.br`, `mavix-ai.com.br`.
3. **E-mail → Caixas de correio**: crie as contas.
4. **Configuração → Opções → DKIM**: para cada domínio, gere (2048 bits) e **copie a chave**.

**8.4 — Publique o DKIM no DNS** (um por domínio, valor diferente cada):

| Tipo | Nome              | Valor |
|------|-------------------|-------|
| TXT  | `dkim._domainkey` | *(cole exatamente o que o mailcow mostrou)* |

Cole em uma linha só — DKIM quebrado em várias linhas é o erro mais comum.

**8.5 — Valide:**

```bash
./setup.sh 8
dig +short TXT dkim._domainkey.algoritmovivo.com.br
```

E mande um e-mail de uma caixa nova para https://www.mail-tester.com — **meta: 10/10**.
Teste também receber, e o webmail em https://mail.algoritmovivo.com.br/SOGo/.

**8.6 — Aquecimento.** IP novo tem reputação zero: nas 2 primeiras semanas mande pouco volume
e crescente. Para disparo em massa, use relay externo (SES, Mailgun, Postmark).

---

## ETAPA 9 — Backup (5 min)

```bash
cd /opt/vps-setup && ./setup.sh 7
```

Cria `/usr/local/bin/vps-backup` + cron diário às 3h (Postgres, configs das stacks, volumes do
n8n/Portainer e o backup oficial do mailcow), com retenção de 14 dias.

**Backup local não é backup.** Mande para fora da VPS:

```bash
apt install -y rclone && rclone config          # S3, Backblaze, Google Drive...
( crontab -l; echo '30 4 * * * rclone sync /opt/backups remoto:vps-backups' ) | crontab -
```

**Teste a restauração pelo menos uma vez** — backup não testado não existe.

---

## ETAPA 10 — Checklist final

- [ ] `dig +short -x 94.72.125.233` responde `mail.algoritmovivo.com.br.`
- [ ] Os 3 sites abrem em HTTPS sem aviso de certificado
- [ ] `http://` redireciona para `https://`, e `www.` redireciona para o domínio raiz
- [ ] Portainer, pgAdmin, n8n e o dashboard do Traefik abrem e pedem senha
- [ ] Senha do painel do mailcow trocada e 2FA ativo
- [ ] DKIM publicado nos 3 domínios
- [ ] mail-tester deu 10/10
- [ ] `vps-backup` rodou e `/opt/backups` tem arquivos
- [ ] Sincronismo do backup para fora da VPS configurado
- [ ] `cat /opt/vps-setup/credenciais.txt` salvo em um gerenciador de senhas
- [ ] `ufw status` mostra só 22, 80, 443 e as portas de e-mail

---

## Comandos do dia a dia

```bash
cd /opt/vps-setup && ./setup.sh 8          # diagnóstico geral
docker ps                                   # o que está no ar
docker logs -f traefik                      # logs do proxy
cd /opt/mailcow-dockerized && docker compose logs -f postfix-mailcow
vps-backup                                  # backup manual
pgcreate meuapp                             # novo banco + usuário + senha
ssh -L 5432:127.0.0.1:5432 root@94.72.125.233   # Postgres no DBeaver do seu PC

# atualizações
cd /opt/mailcow-dockerized && ./update.sh   # faça backup antes
cd /opt/traefik && docker compose pull && docker compose up -d
```

## Se algo der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Certificado inválido | DNS não propagado quando o Traefik pediu | espere propagar, `cd /opt/traefik && docker compose restart`; Let's Encrypt limita 5 falhas/hora |
| 404 no site | container fora do ar ou label errada | `docker ps`, `docker logs <nome>`, confira o `Host()` no compose |
| 502 Bad Gateway | porta errada na label do Traefik | a porta do `loadbalancer.server.port` tem que ser a que o app escuta |
| E-mail cai em spam | PTR, SPF ou DKIM errado | `./setup.sh 8` e mail-tester |
| Não envia e-mail | porta 25 bloqueada | ticket na Contabo (ETAPA 2) |
| Mailcow lento / OOM | pouca RAM | `MAILCOW_SKIP_CLAMAV="y"` e reinstale o módulo 6, ou aumente a VPS |
