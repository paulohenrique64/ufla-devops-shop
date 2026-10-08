# Atividade 3 — Automatizar de verdade

O `ufla-devops-shop` rodando como serviço Linux: instalado por um script
idempotente, gerenciado pelo `systemd`, com backup diário agendado e o Nginx à
frente fazendo TLS.

| Artefato | O que faz |
|----------|-----------|
| [`scripts/deploy.sh`](../scripts/deploy.sh) | instala pacotes, usuário, banco, código, *venv*, *units*, certificado e Nginx; termina com *healthcheck* em `/ready` |
| [`scripts/backup.sh`](../scripts/backup.sh) | `pg_dump` comprimido e datado, rotação de 7, falha se o `pg_dump` falhar, registra no *journal* |
| [`systemd/ufla-shop.service`](../systemd/ufla-shop.service) | a API como serviço, usuário `ufla-shop` (não-root), `Restart=on-failure` |
| [`systemd/ufla-shop-backup.service`](../systemd/ufla-shop-backup.service) + [`.timer`](../systemd/ufla-shop-backup.timer) | backup `oneshot` todo dia às 3h, `Persistent=true` |
| [`systemd/ufla-shop.env.example`](../systemd/ufla-shop.env.example) | modelo do `/etc/ufla-shop.env` (sem senha real) |
| [`nginx/loja.conf`](../nginx/loja.conf) | 80 → 301 para HTTPS; 443 com TLS e `proxy_pass` para `127.0.0.1:8000` com `X-Real-IP`, `X-Forwarded-For` e `X-Forwarded-Proto` |

## (a) Como rodar o `deploy.sh` numa máquina limpa

Requisitos: Linux com `systemd` (Ubuntu/Debian; Fedora também é suportado),
acesso a `sudo` e as portas 80, 443 e 8000 livres.

```bash
git clone https://github.com/paulohenrique64/ufla-devops-shop.git
cd ufla-devops-shop
git switch atividade-03
sudo ./scripts/deploy.sh
```

Só isso. O script, em ordem:

1. instala só os pacotes que faltam (`python3-venv`, `postgresql`, `redis-server`,
   `nginx`, `openssl`, `rsync`, `curl`);
2. cria o usuário de sistema `ufla-shop` se ele não existir
   (`id ufla-shop &>/dev/null || useradd ...`);
3. instala `/etc/ufla-shop.env.example` e, **só se ainda não existir**, cria
   `/etc/ufla-shop.env` com uma senha aleatória (`openssl rand`), dono
   `root:ufla-shop`, modo `640`. A senha nunca aparece no script nem no git;
4. sobe PostgreSQL e Redis, cria o papel `loja` (ou só realinha a senha dele com
   o `.env`) e cria o banco `loja` se ele não existir;
5. sincroniza `app/`, `static/`, `requirements.txt` e `backup.sh` em
   `/opt/ufla-shop` com `rsync --delete` (código do root, só leitura para o
   serviço), cria o *venv* se faltar e instala o `requirements.txt`;
6. instala as três *units* em `/etc/systemd/system/`, `daemon-reload`, habilita
   o serviço e o *timer* e reinicia o serviço;
7. gera o certificado autoassinado com `openssl req -x509` em
   `/etc/ssl/ufla-shop/` se ele ainda não existir, instala o `loja.conf`,
   valida com `nginx -t` e recarrega o Nginx;
8. *healthcheck*: consulta `http://localhost:8000/ready` até 10 vezes, com 1 s
   de intervalo, e sai com `exit 1` se nunca vier `200`.

Para trocar a senha do banco: edite `/etc/ufla-shop.env` e rode o `deploy.sh`
de novo — ele aplica a senha do arquivo no PostgreSQL.

Backup manual (o mesmo que o *timer* dispara às 3h):

```bash
sudo systemctl start ufla-shop-backup.service
journalctl -t backup -n 5
```

## (b) `systemctl status ufla-shop` depois do `kill -9`

Uso `pidof -x uvicorn`: o `uvicorn` do *venv* é um *script* Python, então o
nome do processo é o do interpretador e `pidof uvicorn` (sem `-x`) não acha
nada. Repare no PID novo e no `NRestarts` aumentando em 1: foi o
`Restart=on-failure` que trouxe o serviço de volta.

```console
$ systemctl show -p MainPID -p NRestarts ufla-shop
MainPID=43770
NRestarts=0
$ sudo kill -9 $(pidof -x uvicorn)   # PID 43770
$ sleep 5
$ systemctl status ufla-shop --no-pager -n 8
● ufla-shop.service - ufla-devops-shop (API FastAPI servida pelo uvicorn)
     Loaded: loaded (/etc/systemd/system/ufla-shop.service; enabled; preset: enabled)
     Active: active (running) since Thu 2026-10-08 00:55:08 -03; 2s ago
 Invocation: b4c9d03b09dd4a92b1ef67affd4522e1
   Main PID: 44280 (uvicorn)
      Tasks: 1 (limit: 12250)
     Memory: 48.5M (peak: 49M)
        CPU: 413ms
     CGroup: /system.slice/ufla-shop.service
             └─44280 /opt/ufla-shop/.venv/bin/python3 /opt/ufla-shop/.venv/bin/uvicorn app:api --port 8000 --host 127.0.0.1

Oct 08 00:55:08 laptop systemd[1]: ufla-shop.service: Scheduled restart job, restart counter is at 1.
Oct 08 00:55:08 laptop systemd[1]: Started ufla-shop.service - ufla-devops-shop (API FastAPI servida pelo uvicorn).
Oct 08 00:55:08 laptop uvicorn[44280]: INFO:     Started server process [44280]
Oct 08 00:55:08 laptop uvicorn[44280]: INFO:     Waiting for application startup.
Oct 08 00:55:08 laptop uvicorn[44280]: 2026-10-08 00:55:08,940 INFO loja: ufla-devops-shop 1.0.0 subindo (banco=postgresql, cache=redis, instancia=laptop)
Oct 08 00:55:09 laptop uvicorn[44280]: 2026-10-08 00:55:09,002 INFO loja.banco: banco pronto (modo postgresql)
Oct 08 00:55:09 laptop uvicorn[44280]: INFO:     Application startup complete.
Oct 08 00:55:09 laptop uvicorn[44280]: INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)

$ systemctl show -p MainPID -p NRestarts ufla-shop
MainPID=44280
NRestarts=1
```

## (c) Nginx: HTTPS e redirecionamento de HTTP

O `-s` só esconde a barra de progresso do `curl`. O `curl -I` faz `HEAD`, e a
API só aceita `GET` em `/`; o `loja.conf` repassa o `HEAD` como `GET`
(`proxy_method`), e o Nginx devolve só os cabeçalhos.

```console
$ curl -skI https://localhost
HTTP/1.1 200 OK
Server: nginx/1.28.3 (Ubuntu)
Date: Thu, 08 Oct 2026 03:55:14 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 1262
Connection: keep-alive
accept-ranges: bytes
last-modified: Thu, 08 Oct 2026 03:31:13 GMT
etag: "ce21749ef87e4f32011bef04871955dc"

$ curl -sI http://localhost
HTTP/1.1 301 Moved Permanently
Server: nginx/1.28.3 (Ubuntu)
Date: Thu, 08 Oct 2026 03:55:14 GMT
Content-Type: text/html
Content-Length: 178
Connection: keep-alive
Location: https://localhost/
```

A API escuta só em `127.0.0.1:8000`; de fora, apenas o Nginx (80 e 443):

```console
$ ss -ltn | grep -E ':(80|443|8000)\b'
LISTEN 0      2048                                            127.0.0.1:8000       0.0.0.0:*
LISTEN 0      511                                               0.0.0.0:80         0.0.0.0:*
LISTEN 0      511                                               0.0.0.0:443        0.0.0.0:*
```

## (d) `ls -la /var/backups/ufla-shop` depois de três backups

```console
$ ls -la /var/backups/ufla-shop
total 20
drwxr-x--- 2 ufla-shop ufla-shop 4096 Oct  8 00:57 .
drwxr-xr-x 3 root      root      4096 Oct  8 00:51 ..
-rw------- 1 ufla-shop ufla-shop 1623 Oct  8 00:55 loja-2026-10-08-0055.sql.gz
-rw------- 1 ufla-shop ufla-shop 1624 Oct  8 00:56 loja-2026-10-08-0056.sql.gz
-rw------- 1 ufla-shop ufla-shop 1622 Oct  8 00:57 loja-2026-10-08-0057.sql.gz

$ journalctl -t backup -n 3 --no-pager
Oct 08 00:55:14 laptop backup[44316]: backup gerado: /var/backups/ufla-shop/loja-2026-10-08-0055.sql.gz (1.6K); mantidos os 7 mais recentes
Oct 08 00:56:15 laptop backup[44459]: backup gerado: /var/backups/ufla-shop/loja-2026-10-08-0056.sql.gz (1.6K); mantidos os 7 mais recentes
Oct 08 00:57:17 laptop backup[44624]: backup gerado: /var/backups/ufla-shop/loja-2026-10-08-0057.sql.gz (1.6K); mantidos os 7 mais recentes
```

O *timer* diário instalado e ativo:

```console
$ systemctl list-timers ufla-shop-backup.timer --no-pager
NEXT                           LEFT LAST PASSED UNIT                   ACTIVATES
Thu 2026-10-08 03:00:00 -03 2h 2min -         - ufla-shop-backup.timer ufla-shop-backup.service

1 timers listed.
Pass --all to see loaded but inactive timers, too.
```

## (e) Prova da idempotência: duas execuções seguidas do `deploy.sh`

Primeira execução (últimas linhas):

```console
$ sudo ./scripts/deploy.sh
[deploy] usuario ufla-shop: ja existe
[deploy] /etc/ufla-shop.env: ja existe, mantido
[deploy] banco loja: ja existe
[deploy] sincronizando o codigo em /opt/ufla-shop
[deploy] venv: ja existe
[deploy] instalando requirements.txt
[deploy] instalando as units do systemd
[deploy] (re)iniciando ufla-shop.service
[deploy] certificado TLS: ja existe
[deploy] recarregando o nginx
[deploy] healthcheck OK: http://localhost:8000/ready respondeu 200 (tentativa 1/10)
[deploy] {"status":"ok","banco":"ok","cache":"ok"}
```

Segunda execução, logo em seguida (últimas linhas): nada é recriado e o
*healthcheck* passa de novo.

```console
$ sudo ./scripts/deploy.sh
[deploy] usuario ufla-shop: ja existe
[deploy] /etc/ufla-shop.env: ja existe, mantido
[deploy] banco loja: ja existe
[deploy] sincronizando o codigo em /opt/ufla-shop
[deploy] venv: ja existe
[deploy] instalando requirements.txt
[deploy] instalando as units do systemd
[deploy] (re)iniciando ufla-shop.service
[deploy] certificado TLS: ja existe
[deploy] recarregando o nginx
[deploy] healthcheck OK: http://localhost:8000/ready respondeu 200 (tentativa 1/10)
[deploy] {"status":"ok","banco":"ok","cache":"ok"}
```

## Serviço sem root

```console
$ ps -o user,pid,cmd -C uvicorn
USER         PID CMD
ufla-sh+   44280 /opt/ufla-shop/.venv/bin/python3 /opt/ufla-shop/.venv/bin/uvicorn app:api --port 8000 --host 127.0.0.1
$ systemctl show -p User ufla-shop
User=ufla-shop
```
