# Checklist de DNS

Substitua `IP_DA_VPS` pelo IPv4 da Contabo, `exemploN.com.br` pelos seus domínios
e `mail.exemplo1.com.br` pelo hostname do mailcow.

> Se usar **Cloudflare**: os registros dos **sites** podem ficar com proxy (nuvem laranja).
> Os registros de **e-mail** (`mail.`, `autoconfig.`, `autodiscover.`, MX, SPF, DKIM, DMARC)
> precisam ficar **DNS only** (nuvem cinza), senão SMTP/IMAP quebram.

## 1. Sites (um bloco por domínio)

| Tipo  | Nome            | Valor           | TTL  |
|-------|-----------------|-----------------|------|
| A     | `@`             | `IP_DA_VPS`     | 300  |
| A     | `www`           | `IP_DA_VPS`     | 300  |
| AAAA  | `@` / `www`     | IPv6 da VPS     | 300  |

Painéis (só no domínio principal):

| Tipo | Nome        | Valor       |
|------|-------------|-------------|
| A    | `traefik`   | `IP_DA_VPS` |
| A    | `portainer` | `IP_DA_VPS` |
| A    | `pgadmin`   | `IP_DA_VPS` |
| A    | `n8n`       | `IP_DA_VPS` |

## 2. Servidor de e-mail — hostname

Só **um** hostname para o mailcow, mesmo atendendo os 3 domínios:

| Tipo | Nome   | Valor       |
|------|--------|-------------|
| A    | `mail` | `IP_DA_VPS` |

E no **painel da Contabo**: configure o **rDNS / PTR** do IP para `mail.exemplo1.com.br`.
Sem PTR batendo com o hostname, Gmail/Outlook rejeitam ou marcam como spam.

## 3. Para CADA domínio que vai receber e-mail

| Tipo  | Nome                  | Valor                                                                 |
|-------|-----------------------|-----------------------------------------------------------------------|
| MX    | `@`                   | `mail.exemplo1.com.br` (prioridade 10)                                 |
| TXT   | `@`                   | `v=spf1 mx a:mail.exemplo1.com.br -all`                                |
| TXT   | `dkim._domainkey`     | *(copie do painel do mailcow: E-mail → Configurações → DKIM)*           |
| TXT   | `_dmarc`              | `v=DMARC1; p=quarantine; rua=mailto:dmarc@exemplo1.com.br; adkim=s; aspf=s` |
| CNAME | `autoconfig`          | `mail.exemplo1.com.br`                                                 |
| CNAME | `autodiscover`        | `mail.exemplo1.com.br`                                                 |
| SRV   | `_autodiscover._tcp`  | `0 0 443 mail.exemplo1.com.br`                                         |

Opcional (MTA-STS / TLS reporting):

| Tipo | Nome        | Valor                                                     |
|------|-------------|-----------------------------------------------------------|
| TXT  | `_mta-sts`  | `v=STSv1; id=20250101000000`                               |
| TXT  | `_smtp._tls`| `v=TLSRPTv1; rua=mailto:tlsrpt@exemplo1.com.br`            |

## 4. Ordem correta

1. Publique os **A** dos sites, do `traefik.` e do `mail.` → espere propagar (`dig +short A dominio`).
2. Só então suba Traefik/sites/mailcow — o Let's Encrypt valida via HTTP na porta 80.
3. Configure o **PTR** na Contabo.
4. Adicione os domínios no painel do mailcow → copie o **DKIM** → publique.
5. Publique **MX, SPF, DMARC**.
6. Valide: `./setup.sh 8`, https://www.mail-tester.com (meta: 10/10) e https://internet.nl/mail/.

## 5. Erros clássicos

- SPF com `~all` e `-all` duplicados, ou **dois registros SPF** no mesmo domínio (só pode existir um).
- DKIM copiado quebrado em várias linhas — cole exatamente como o mailcow mostra.
- MX apontando para o domínio raiz em vez de `mail.`.
- Cloudflare com proxy ligado no `mail.` (quebra porta 25/465/993).
- PTR faltando — é a causa nº 1 de e-mail indo para spam em VPS.
