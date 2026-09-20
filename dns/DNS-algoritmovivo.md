# DNS preenchido — algoritmovivo.com.br · mavi-ai.com.br · mavix-ai.com.br

> ## Onde editar a zona (situação atual consultada agora)
>
> | Domínio | NS hoje | Onde editar |
> |---|---|---|
> | algoritmovivo.com.br | `ns56/ns57.hostgator.com.br` | painel da **HostGator** (ou mude os NS no Registro.br) |
> | mavix-ai.com.br | `ns56/ns57.hostgator.com.br` | painel da **HostGator** (idem) |
> | mavi-ai.com.br | `a/b.auto.dns.br` (Registro.br) | painel do **Registro.br** |
>
> Instalação limpa — os registros que sobraram do teste antigo (A `192.185.213.181` da
> HostGator, MX do Titan e o SPF `include:spf.titan.email`) devem ser **apagados/substituídos**
> pelos valores abaixo. O `MX 0 .` do mavi-ai também sai. Deixe o TTL em 300 durante a troca.

IP da VPS (Contabo): **`94.72.125.233`** — já preenchido em todos os registros abaixo.
Hostname único do servidor de e-mail para os três domínios: **`mail.algoritmovivo.com.br`**.

**Estado do IP hoje:** PTR ainda é o padrão da Contabo (`vmi2753134.contaboserver.net`) —
**precisa ser trocado** para `mail.algoritmovivo.com.br` no painel da Contabo. Portas 80/443/25
ainda fechadas (nada rodando), só a 22 responde. A consulta à Spamhaus via resolver público
não é conclusiva; confira em https://check.spamhaus.org depois de subir.

> Os três domínios estão no **Registro.br**. Se deixar o DNS no próprio Registro.br, edite em
> *Painel → domínio → DNS → Editar zona*. Se apontar para a **Cloudflare**, tudo que é e-mail
> (`mail.`, `autoconfig.`, `autodiscover.`, MX, SPF, DKIM, DMARC) precisa ficar **DNS only**
> (nuvem cinza) — com proxy ligado as portas 25/465/993 quebram.

---

## 1. algoritmovivo.com.br (domínio principal — hospeda mail e painel)

| Tipo  | Nome                 | Valor                                                                        |
|-------|----------------------|------------------------------------------------------------------------------|
| A     | `@`                  | `94.72.125.233`                                                                    |
| A     | `www`                | `94.72.125.233`                                                                    |
| A     | `mail`               | `94.72.125.233`                                                                    |
| A     | `traefik`            | `94.72.125.233`  — dashboard do Traefik                                            |
| A     | `portainer`          | `94.72.125.233`  — Portainer                                                       |
| A     | `pgadmin`            | `94.72.125.233`  — pgAdmin                                                         |
| A     | `n8n`                | `94.72.125.233`  — n8n                                                             |
| MX    | `@`                  | `mail.algoritmovivo.com.br.` — prioridade **10**                               |
| TXT   | `@`                  | `v=spf1 mx a:mail.algoritmovivo.com.br -all`                                   |
| TXT   | `dkim._domainkey`    | *(copiar do mailcow: E-mail → Configurações → DKIM, depois de criar o domínio)* |
| TXT   | `_dmarc`             | `v=DMARC1; p=quarantine; rua=mailto:dmarc@algoritmovivo.com.br; adkim=s; aspf=s` |
| CNAME | `autoconfig`         | `mail.algoritmovivo.com.br.`                                                   |
| CNAME | `autodiscover`       | `mail.algoritmovivo.com.br.`                                                   |
| SRV   | `_autodiscover._tcp` | `0 0 443 mail.algoritmovivo.com.br.`                                           |

## 2. mavi-ai.com.br

| Tipo  | Nome                 | Valor                                                                    |
|-------|----------------------|--------------------------------------------------------------------------|
| A     | `@`                  | `94.72.125.233`                                                                |
| A     | `www`                | `94.72.125.233`                                                                |
| MX    | `@`                  | `mail.algoritmovivo.com.br.` — prioridade **10**                           |
| TXT   | `@`                  | `v=spf1 mx a:mail.algoritmovivo.com.br -all`                               |
| TXT   | `dkim._domainkey`    | *(copiar do mailcow — é uma chave DKIM diferente, por domínio)*             |
| TXT   | `_dmarc`             | `v=DMARC1; p=quarantine; rua=mailto:dmarc@mavi-ai.com.br; adkim=s; aspf=s` |
| CNAME | `autoconfig`         | `mail.algoritmovivo.com.br.`                                               |
| CNAME | `autodiscover`       | `mail.algoritmovivo.com.br.`                                               |
| SRV   | `_autodiscover._tcp` | `0 0 443 mail.algoritmovivo.com.br.`                                       |

**Não** crie `A mail` aqui — o MX aponta para o hostname do outro domínio, e é assim que deve ser.

## 3. mavix-ai.com.br

| Tipo  | Nome                 | Valor                                                                     |
|-------|----------------------|---------------------------------------------------------------------------|
| A     | `@`                  | `94.72.125.233`                                                                 |
| A     | `www`                | `94.72.125.233`                                                                 |
| MX    | `@`                  | `mail.algoritmovivo.com.br.` — prioridade **10**                            |
| TXT   | `@`                  | `v=spf1 mx a:mail.algoritmovivo.com.br -all`                                |
| TXT   | `dkim._domainkey`    | *(copiar do mailcow)*                                                       |
| TXT   | `_dmarc`             | `v=DMARC1; p=quarantine; rua=mailto:dmarc@mavix-ai.com.br; adkim=s; aspf=s` |
| CNAME | `autoconfig`         | `mail.algoritmovivo.com.br.`                                                |
| CNAME | `autodiscover`       | `mail.algoritmovivo.com.br.`                                                |
| SRV   | `_autodiscover._tcp` | `0 0 443 mail.algoritmovivo.com.br.`                                        |

---

## 4. PTR / rDNS (painel da Contabo, não é DNS do domínio)

IP da VPS → `mail.algoritmovivo.com.br`

Sem isso, Gmail e Outlook rejeitam ou mandam para spam. É a causa nº 1 de e-mail não entregue em VPS.

## 5. Ordem de execução

1. Publique os **A** (`@`, `www` nos três; `mail`, `traefik`, `portainer`, `pgadmin`, `n8n`
   só em algoritmovivo.com.br) e espere propagar:
   ```bash
   dig +short A algoritmovivo.com.br mavi-ai.com.br mavix-ai.com.br mail.algoritmovivo.com.br
   ```
2. Configure o **PTR** na Contabo e teste a **porta 25 de saída** (`./setup.sh 8`).
3. Rode `./setup.sh 1 2 3 4 5 9` — o Let's Encrypt valida pela porta 80, por isso o DNS vem antes.
4. Rode `./setup.sh 6` (mailcow), adicione os 3 domínios no painel e **copie o DKIM de cada um**.
5. Publique **MX, SPF, DKIM, DMARC** dos três.
6. Valide: `./setup.sh 8`, https://www.mail-tester.com (meta 10/10) e https://internet.nl/mail/.

## 6. Conferência rápida depois de publicar

```bash
dig +short MX  mavi-ai.com.br
dig +short TXT algoritmovivo.com.br
dig +short TXT dkim._domainkey.mavix-ai.com.br
dig +short -x 94.72.125.233          # tem que responder mail.algoritmovivo.com.br.
```
