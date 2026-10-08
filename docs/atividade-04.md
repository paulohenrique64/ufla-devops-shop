# Atividade 4 — Containerizar a aplicação

Imagem `ufla-shop:1.0`: *build* multi-stage sobre `python:3.12-alpine`, usuário
não-root, `CMD` na forma *exec* e `HEALTHCHECK` em `/health`. O container roda no
modo autônomo (SQLite + cache em memória), com o banco em `/dados/loja.db`.

```bash
docker build -t ufla-shop:1.0 .
docker run -d --name loja -p 8000:8000 ufla-shop:1.0
```

## 1. Antes e depois: `docker images`

Primeira versão que funcionou (`ufla-shop:v1`) e a final (`ufla-shop:1.0`):

```console
$ docker images ufla-shop
IMAGE           ID             DISK USAGE   CONTENT SIZE   EXTRA
ufla-shop:1.0   1654cd57f36e        125MB         29.2MB
ufla-shop:v1    01fc8f2773ed        511MB          110MB
```

| | Primeira (`v1`) | Final (`1.0`) |
|---|---|---|
| Descompactado (`du -sxm /` no container) | **379 MB** | **85 MB** |
| Soma das camadas (`docker history`) | **401 MB** | **96 MB** |
| `docker image inspect --format '{{.Size}}'` | 111M | 30M |

Este Docker (29.5) usa o *containerd image store*: `DISK USAGE` soma os blobs
comprimidos e a cópia descompactada, e `{{.Size}}` devolve o tamanho comprimido.
Num Docker com o armazenamento clássico, `{{.Size}}` é o tamanho descompactado,
a soma das camadas — 96 MB nesta imagem. Por isso a meta foi perseguida pelo
número descompactado, que fica abaixo de 150 MB nas duas formas de medir.

A primeira versão:

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
EXPOSE 8000
CMD ["uvicorn", "app:api", "--host", "0.0.0.0", "--port", "8000"]
```

## 2. O que mudou e quanto cada mudança economizou

Cada passo foi construído e medido separadamente (descompactado, `du -sxm /`
dentro do container):

| # | Mudança | Tamanho | Economia |
|---|---------|--------:|---------:|
| 0 | `v1`: um estágio, `python:3.12-slim`, `COPY . .`, sem `.dockerignore` | 379 MB | — |
| 1 | `.dockerignore` | 190 MB | −189 MB |
| 2 | multi-stage: dependências num *venv* no estágio `build`; o final copia só o *venv*, `app/` e `static/` | 181 MB | −9 MB |
| 3 | sem cache do `pip`, `pip` desinstalado do *venv*, `__pycache__` apagados | 158 MB | −23 MB |
| 4 | base `python:3.12-alpine` nos dois estágios | **85 MB** | −73 MB |

**1. `.dockerignore` (−189 MB).** O `COPY . .` levava para a imagem o `.venv`
local (102 MB), o `dados/` da Atividade 2 (87 MB de `access.log`), o `.git`, os
testes e o `loja.db`. Pior que o peso: `.git` e `.env` dentro da imagem vazam
histórico e segredos. O `.dockerignore` exclui `.git`, `.venv`, `__pycache__`,
`tests`, `*.db` e `.env`, além de tudo o que não roda em produção (docs,
scripts, `dados/`, configuração de lint e de testes).

**2. Multi-stage (−9 MB).** O `pip install` roda no estágio `build`, dentro de
`/opt/venv`; o estágio final recebe só o *venv* pronto e o código. O ganho aqui
é pequeno porque as dependências têm *wheels* (não há compilador para deixar
para trás), mas o estágio final passa a ter só o que executa — e, com
`COPY app/` e `COPY static/` no lugar de `COPY . .`, nada entra por engano.

**3. Cortes no *venv* (−23 MB).** `PIP_NO_CACHE_DIR=1` não grava o cache de
download; o `pip` (13 MB) sai do *venv*, porque em produção ninguém instala
pacote; os `__pycache__` (~10 MB) são apagados. Com `PYTHONDONTWRITEBYTECODE=1`
o Python não tenta regravá-los — o custo é compilar os módulos na subida: do
`docker run` até o `/health` responder leva cerca de 2 s. Mesmo com todos os cortes, o slim fica em 158 MB: a
base sozinha já passa de 120 MB.

**4. Alpine (−73 MB).** A base `python:3.12-alpine` usa `musl` e BusyBox no
lugar de `glibc` e do userland do Debian. Todas as dependências têm *wheels*
`musllinux`, então nada é compilado. O `docker history` da final mostra o que
sobrou — Alpine (9 MB), Python (50 MB), *venv* (33 MB) e o código (77 kB):

```console
$ docker history ufla-shop:1.0 --format 'table {{.Size}}\t{{.CreatedBy}}'
SIZE      CREATED BY
0B        CMD ["uvicorn" "app:api" "--host" "0.0.0.0" …
0B        HEALTHCHECK {Test:[CMD python -c import urll…
0B        EXPOSE [8000/tcp]
0B        USER 10001:10001
24.6kB    COPY static/ static/ # buildkit
53.2kB    COPY app/ app/ # buildkit
33.4MB    COPY /opt/venv /opt/venv # buildkit
8.19kB    WORKDIR /app
36.9kB    RUN /bin/sh -c addgroup -S -g 10001 loja  &&…
0B        ENV PATH=/opt/venv/bin:/usr/local/bin:/usr/l…
0B        CMD ["python3"]
16.4kB    RUN /bin/sh -c set -eux;  for src in idle3 p…
50.4MB    RUN /bin/sh -c set -eux;   apk add --no-cach…
0B        ENV PYTHON_SHA256=c2c4321961fab0fb999d66e0ce…
0B        ENV PYTHON_VERSION=3.12.15
0B        ENV GPG_KEY=7169605F62C751356D054A26A821E680…
2.83MB    RUN /bin/sh -c set -eux;  apk add --no-cache…
0B        ENV LANG=C.UTF-8
0B        ENV PATH=/usr/local/bin:/usr/local/sbin:/usr…
0B        CMD ["/bin/sh"]
9.08MB    ADD alpine-minirootfs-3.24.2-x86_64.tar.gz /…
```

Outras decisões do `Dockerfile`:

- **Usuário não-root:** `loja`, UID/GID 10001, declarado por número
  (`USER 10001:10001`) para que o Kubernetes consiga checar `runAsNonRoot`.
- **SQLite gravável:** o código em `/app` é do root; o banco vai para `/dados`
  (`SQLITE_PATH=/dados/loja.db`), único diretório do usuário `loja`.
- **`CMD` na forma *exec*:** o `uvicorn` é o PID 1 e recebe o `SIGTERM` direto
  — `docker stop` leva 0,4 s em vez de 10 s e um `SIGKILL`.
- **`HEALTHCHECK` sem `curl`:** usa `urllib.request` do próprio Python contra
  `127.0.0.1:8000/health` (dentro do container); `urlopen` levanta exceção em
  erro HTTP ou de conexão, e o código de saída 1 marca a falha. Intervalo de
  5 s, então o container está `healthy` antes dos 10 s da verificação.

## 3. Verificação

```console
$ docker image inspect --format '{{.Size}}' ufla-shop:1.0 | numfmt --to=si
30M
$ docker run -d --name loja -p 8000:8000 ufla-shop:1.0
66daf14b464895db8903a37655806d3df450d56adfdd8e057bd0e58f0bd92e15
$ docker run --rm ufla-shop:1.0 id -u
10001
$ sleep 10 && docker inspect --format '{{.State.Health.Status}}' loja
healthy
$ curl -s localhost:8000/health && curl -s localhost:8000/api/produtos | head -c 200
{"status":"ok","versao":"1.0.0"}[{"id":1,"nome":"Caneca DevOps na Prática","descricao":"Cerâmica, 350 ml: 'funciona na minha máquina'","preco":39.9,"estoque":25,"criado_em":"2026-10-08 04:12:11"},{"id":2,"nome":"Camiseta UFLA Com
$ curl -s localhost:8000/api/produtos | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))'
12
$ docker run --rm ufla-shop:1.0 ls -a
.
..
app
static
$ time docker stop loja
loja

real	0m0.409s
user	0m0.009s
sys	0m0.008s
```

Evidências extras dos critérios:

```console
$ docker exec loja cat /proc/1/cmdline | tr '\0' ' '
/opt/venv/bin/python /opt/venv/bin/uvicorn app:api --host 0.0.0.0 --port 8000
$ docker inspect --format 'ExitCode={{.State.ExitCode}}' loja     # depois do docker stop
ExitCode=0
$ docker exec loja ls -la /dados
-rw-r--r--    1 loja     loja         16384 Oct  8 04:18 loja.db
$ docker exec loja touch /app/x
touch: /app/x: Permission denied
```

O `uvicorn` é o PID 1 e sai com código 0: recebeu o `SIGTERM` e encerrou
limpo, sem precisar de `SIGKILL` (que daria 137). O SQLite é gravado em
`/dados`, do usuário `loja`; o código em `/app` é só leitura para ele.

O *healthcheck* também detecta falha: com a API subindo em outra porta
(`docker run ufla-shop:1.0 uvicorn app:api --host 0.0.0.0 --port 9000`), o
`/health` em `127.0.0.1:8000` não responde e o container vira `unhealthy`.

Observação sobre o "erro caro": testei o mesmo `CMD` na forma *shell*
(`CMD uvicorn app:api ...`) e, no Alpine, o `docker stop` também levou 0,5 s — o
`sh` do BusyBox faz `exec` quando recebe um comando só, e o `uvicorn` acaba como
PID 1. Isso é detalhe da imagem base e não é garantido: no `python:3.12-slim`
(`dash`), o mesmo teste deixou `sh -c ...` como PID 1 e o `docker stop` levou
10,2 s. Por isso o `CMD` usa a forma *exec*, que não depende do *shell*.

## 4. Por que o `HEALTHCHECK` consulta `/health` e não `/ready`?

O `HEALTHCHECK` responde "o processo está vivo?", e `/health` responde
exatamente isso sem tocar em banco nem cache, então só falha quando reiniciar o
container de fato resolve. Se ele consultasse `/ready`, uma queda do PostgreSQL
ou do Redis deixaria todos os containers `unhealthy` e o orquestrador os
reiniciaria em cascata sem consertar nada — dependência fora é caso de parar de
receber tráfego (*readiness*), não de matar o processo (*liveness*).
