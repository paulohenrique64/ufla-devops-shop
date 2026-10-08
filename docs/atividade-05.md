# Atividade 5 — A stack completa

A aplicação no modo completo: API, PostgreSQL, Redis e Nginx, cada um no seu
container, subindo com um único `docker compose up` e mantendo os dados depois
de um `down` seguido de `up`.

| Serviço | Imagem | O que tem |
|---------|--------|-----------|
| `banco` | `postgres:16-alpine` | `POSTGRES_DB`, `POSTGRES_USER` e `POSTGRES_PASSWORD` do `.env`; volume nomeado `dados-banco` em `/var/lib/postgresql/data`; *healthcheck* com `pg_isready` |
| `cache` | `redis:7-alpine` | *healthcheck* com `redis-cli ping` |
| `api` | `ghcr.io/paulohenrique64/ufla-shop:1.0.0` | `DATABASE_URL` e `REDIS_URL` apontando para `banco` e `cache` pelo nome do serviço; `depends_on` com `condition: service_healthy` nos dois; nenhuma porta publicada |
| `nginx` | `nginx:1.27-alpine` | `nginx/default.conf` montado como volume; `proxy_pass http://api:8000`; a única porta publicada (`80:80`) |

Os quatro têm `restart: unless-stopped`. A senha do banco aparece uma vez, no
`.env` (não versionado); a `DATABASE_URL` é montada a partir dela com
`${POSTGRES_PASSWORD:?defina no .env}`, e sem o `.env` o compose se recusa a
subir:

```console
$ docker compose up -d
error while interpolating services.banco.environment.POSTGRES_DB: required variable POSTGRES_DB is missing a value: defina no .env
```

E com um `.env` que tem tudo menos a senha:

```console
$ grep -v '^POSTGRES_PASSWORD' .env > sem-senha.env
$ docker compose --env-file sem-senha.env up -d
error while interpolating services.banco.environment.POSTGRES_PASSWORD: required variable POSTGRES_PASSWORD is missing a value: defina no .env
```

O PostgreSQL só lê `POSTGRES_PASSWORD` quando o volume é criado. Trocar a senha
no `.env` depois disso faz o `/ready` acusar `"banco":"falha"`: é preciso recriar
o volume (`docker compose down -v`, que apaga os dados) ou alterar a senha dentro
do banco com `ALTER USER`.

Como subir:

```bash
cp .env.example .env    # e troque a senha
docker compose up -d --wait
```

## (a) `docker compose ps` com tudo *healthy*

```console
$ docker compose ps
NAME                IMAGE                                     COMMAND                  SERVICE   CREATED          STATUS                    PORTS
ufla-shop-api-1     ghcr.io/paulohenrique64/ufla-shop:1.0.0   "uvicorn app:api --h…"   api       17 seconds ago   Up 11 seconds (healthy)   8000/tcp
ufla-shop-banco-1   postgres:16-alpine                        "docker-entrypoint.s…"   banco     17 seconds ago   Up 16 seconds (healthy)   5432/tcp
ufla-shop-cache-1   redis:7-alpine                            "docker-entrypoint.s…"   cache     17 seconds ago   Up 16 seconds (healthy)   6379/tcp
ufla-shop-nginx-1   nginx:1.27-alpine                         "/docker-entrypoint.…"   nginx     17 seconds ago   Up 5 seconds (healthy)    0.0.0.0:80->80/tcp, [::]:80->80/tcp
```

Só o `nginx` publica porta (`0.0.0.0:80->80/tcp`); `api`, `banco` e `cache`
ficam acessíveis apenas na rede interna do compose.

## (b) Roteiro de persistência

```console
$ docker compose up -d --wait
 Network ufla-shop_default Creating 
 Network ufla-shop_default Created 
 Volume ufla-shop_dados-banco Creating 
 Volume ufla-shop_dados-banco Created 
 Container ufla-shop-cache-1 Creating 
 Container ufla-shop-banco-1 Creating 
 Container ufla-shop-cache-1 Created 
 Container ufla-shop-banco-1 Created 
 Container ufla-shop-api-1 Creating 
 Container ufla-shop-api-1 Created 
 Container ufla-shop-nginx-1 Creating 
 Container ufla-shop-nginx-1 Created 
 Container ufla-shop-banco-1 Starting 
 Container ufla-shop-cache-1 Starting 
 Container ufla-shop-banco-1 Started 
 Container ufla-shop-cache-1 Started 
 Container ufla-shop-banco-1 Waiting 
 Container ufla-shop-cache-1 Waiting 
 Container ufla-shop-cache-1 Healthy 
 Container ufla-shop-banco-1 Healthy 
 Container ufla-shop-api-1 Starting 
 Container ufla-shop-api-1 Started 
 Container ufla-shop-api-1 Waiting 
 Container ufla-shop-api-1 Healthy 
 Container ufla-shop-nginx-1 Starting 
 Container ufla-shop-nginx-1 Started 
 Container ufla-shop-api-1 Waiting 
 Container ufla-shop-nginx-1 Waiting 
 Container ufla-shop-banco-1 Waiting 
 Container ufla-shop-cache-1 Waiting 
 Container ufla-shop-api-1 Healthy 
 Container ufla-shop-banco-1 Healthy 
 Container ufla-shop-cache-1 Healthy 
 Container ufla-shop-nginx-1 Healthy 
$ curl -sI http://localhost
HTTP/1.1 200 OK
Server: nginx/1.27.5
Date: Thu, 08 Oct 2026 04:36:34 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 1262
Connection: keep-alive
accept-ranges: bytes
last-modified: Thu, 08 Oct 2026 04:35:12 GMT
etag: "b29f68810537fb02bf5d854c01adc010"

$ curl -s http://localhost/api/info
{"aplicacao":"ufla-devops-shop","versao":"1.0.0","banco":"postgresql","cache":"redis","instancia":"35eb6de44b3a"}
$ curl -s -X POST http://localhost/api/produtos -H 'Content-Type: application/json' -d '{"nome":"Prova de persistencia","preco":9.9,"estoque":1}'
{"id":13,"nome":"Prova de persistencia","descricao":"","preco":9.9,"estoque":1,"criado_em":"2026-10-08T04:36:34.409445+00:00"}
$ docker compose down
 Container ufla-shop-nginx-1 Stopping 
 Container ufla-shop-nginx-1 Stopped 
 Container ufla-shop-nginx-1 Removing 
 Container ufla-shop-nginx-1 Removed 
 Container ufla-shop-api-1 Stopping 
 Container ufla-shop-api-1 Stopped 
 Container ufla-shop-api-1 Removing 
 Container ufla-shop-api-1 Removed 
 Container ufla-shop-banco-1 Stopping 
 Container ufla-shop-cache-1 Stopping 
 Container ufla-shop-banco-1 Stopped 
 Container ufla-shop-banco-1 Removing 
 Container ufla-shop-cache-1 Stopped 
 Container ufla-shop-cache-1 Removing 
 Container ufla-shop-banco-1 Removed 
 Container ufla-shop-cache-1 Removed 
 Network ufla-shop_default Removing 
 Network ufla-shop_default Removed 
$ docker compose up -d --wait
 Network ufla-shop_default Creating 
 Network ufla-shop_default Created 
 Container ufla-shop-banco-1 Creating 
 Container ufla-shop-cache-1 Creating 
 Container ufla-shop-cache-1 Created 
 Container ufla-shop-banco-1 Created 
 Container ufla-shop-api-1 Creating 
 Container ufla-shop-api-1 Created 
 Container ufla-shop-nginx-1 Creating 
 Container ufla-shop-nginx-1 Created 
 Container ufla-shop-cache-1 Starting 
 Container ufla-shop-banco-1 Starting 
 Container ufla-shop-banco-1 Started 
 Container ufla-shop-cache-1 Started 
 Container ufla-shop-banco-1 Waiting 
 Container ufla-shop-cache-1 Waiting 
 Container ufla-shop-cache-1 Healthy 
 Container ufla-shop-banco-1 Healthy 
 Container ufla-shop-api-1 Starting 
 Container ufla-shop-api-1 Started 
 Container ufla-shop-api-1 Waiting 
 Container ufla-shop-api-1 Healthy 
 Container ufla-shop-nginx-1 Starting 
 Container ufla-shop-nginx-1 Started 
 Container ufla-shop-banco-1 Waiting 
 Container ufla-shop-cache-1 Waiting 
 Container ufla-shop-api-1 Waiting 
 Container ufla-shop-nginx-1 Waiting 
 Container ufla-shop-banco-1 Healthy 
 Container ufla-shop-api-1 Healthy 
 Container ufla-shop-cache-1 Healthy 
 Container ufla-shop-nginx-1 Healthy 
$ curl -s 'http://localhost/api/busca?q=persistencia'
{"termo":"persistencia","total":1,"resultados":[{"id":13,"nome":"Prova de persistencia","descricao":"","preco":9.9,"estoque":1,"criado_em":"2026-10-08T04:36:34.409445+00:00"}]}
```

O produto criado antes do `down` continua lá depois do `up`: os dados ficam no
volume nomeado, que o `down` sem `-v` preserva.

```console
$ docker volume ls --filter name=ufla-shop
DRIVER    VOLUME NAME
local     ufla-shop_dados-banco
```

## (c) A imagem no GHCR

Endereço público: **`ghcr.io/paulohenrique64/ufla-shop:1.0.0`**

Página do pacote: <https://github.com/users/paulohenrique64/packages/container/package/ufla-shop>

A imagem é construída a partir do `Dockerfile` da Atividade 4 e publicada com a
*tag* SemVer `1.0.0` — nunca `latest`, para que o `compose.yaml` diga
exatamente qual versão roda e o *rollback* tenha para onde voltar. O `pull`
abaixo é feito sem credencial nenhuma (configuração do Docker vazia), o que
prova que o pacote é público:

```console
$ DOCKER_CONFIG=$(mktemp -d) docker pull ghcr.io/paulohenrique64/ufla-shop:1.0.0
1.0.0: Pulling from paulohenrique64/ufla-shop
35a0962b20a0: Already exists
1136bd3fbd92: Already exists
Digest: sha256:fbf88b05846d15a1d97ddfd886d7c0731af94be834da2b7f35277e23d4d825e9
ghcr.io/paulohenrique64/ufla-shop:1.0.0
```

## (d) Por que `depends_on` sozinho não resolve a ordem de subida?

`depends_on` sozinho só garante que o container do banco seja *iniciado* antes
do da API, mas o PostgreSQL ainda leva alguns segundos para aceitar conexões
depois que o processo começa — e a API sobe nesse intervalo e recebe
`connection refused`. O `condition: service_healthy` faz o compose esperar o
*healthcheck* do serviço (`pg_isready`, `redis-cli ping`) passar antes de criar
a API, então ela só sobe quando banco e cache já estão de fato prontos para
responder.
