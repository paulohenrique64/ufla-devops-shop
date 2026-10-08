#!/usr/bin/env bash
# Instala ou atualiza o ufla-devops-shop como servico systemd. Uso: sudo ./scripts/deploy.sh
set -euo pipefail

APP_USER=ufla-shop
APP_DIR=/opt/ufla-shop
ENV_FILE=/etc/ufla-shop.env
ENV_EXAMPLE=/etc/ufla-shop.env.example
BACKUP_DIR=/var/backups/ufla-shop
TLS_DIR=/etc/ssl/ufla-shop
UNIT_DIR=/etc/systemd/system
DB_NAME=loja
DB_USER=loja
READY_URL=http://localhost:8000/ready

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '[deploy] %s\n' "$*"; }
falha() { printf '[deploy] ERRO: %s\n' "$*" >&2; exit 1; }

como_postgres() { (cd / && runuser -u postgres -- "$@"); }

[[ $EUID -eq 0 ]] || exec sudo -- "$0" "$@"

# --- 0. Distribuicao ---------------------------------------------------------
if command -v apt-get &>/dev/null; then
    DISTRO=debian
    PACOTES=(python3-venv postgresql redis-server nginx openssl rsync curl)
    REDIS_SERVICE=redis-server
    NGINX_CONF=/etc/nginx/conf.d/loja.conf
elif command -v dnf &>/dev/null; then
    DISTRO=fedora
    PACOTES=(python3 postgresql-server postgresql redis nginx openssl rsync curl)
    REDIS_SERVICE=redis
    NGINX_CONF=/etc/nginx/conf.d/loja.conf
else
    falha "distribuicao nao suportada (precisa de apt-get ou dnf)"
fi

# --- 1. Pacotes do sistema (so instala o que falta) ---------------------------
faltando=()
for p in "${PACOTES[@]}"; do
    if [[ $DISTRO == debian ]]; then
        [[ "$(dpkg-query -W -f='${Status}' "$p" 2>/dev/null)" == "install ok installed" ]] || faltando+=("$p")
    else
        rpm -q "$p" &>/dev/null || faltando+=("$p")
    fi
done
if ((${#faltando[@]})); then
    log "instalando pacotes: ${faltando[*]}"
    if [[ $DISTRO == debian ]]; then
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${faltando[@]}"
    else
        dnf install -y -q "${faltando[@]}"
    fi
else
    log "pacotes do sistema: ja instalados"
fi

# --- 2. Usuario de sistema da aplicacao --------------------------------------
if id "$APP_USER" &>/dev/null; then
    log "usuario $APP_USER: ja existe"
else
    log "criando usuario de sistema $APP_USER"
    useradd --system --user-group --home-dir "$APP_DIR" --no-create-home \
        --shell /usr/sbin/nologin "$APP_USER"
fi

# --- 3. Arquivo de segredos --------------------------------------------------
install -m 644 -o root -g root "$REPO_DIR/systemd/ufla-shop.env.example" "$ENV_EXAMPLE"
if [[ -f $ENV_FILE ]]; then
    log "$ENV_FILE: ja existe, mantido"
else
    log "criando $ENV_FILE a partir de $ENV_EXAMPLE (senha aleatoria)"
    senha="$(openssl rand -hex 24)"
    (umask 077 && sed "s/__SENHA__/$senha/" "$ENV_EXAMPLE" > "$ENV_FILE")
    unset senha
fi
chown root:"$APP_USER" "$ENV_FILE"
chmod 640 "$ENV_FILE"

DB_SENHA="$(sed -nE 's|^DATABASE_URL=postgresql://[^:]+:([^@]+)@.*|\1|p' "$ENV_FILE")"
[[ -n $DB_SENHA ]] || falha "DATABASE_URL sem senha em $ENV_FILE"

# --- 4. PostgreSQL e Redis ----------------------------------------------------
if [[ $DISTRO == fedora && ! -f /var/lib/pgsql/data/PG_VERSION ]]; then
    log "inicializando o cluster do PostgreSQL"
    postgresql-setup --initdb
    sed -i -E 's/^(host\s+.*\s)ident$/\1scram-sha-256/' /var/lib/pgsql/data/pg_hba.conf
fi

systemctl enable --now postgresql.service "$REDIS_SERVICE.service" &>/dev/null

for _ in $(seq 1 10); do
    como_postgres psql -qtAc 'SELECT 1' &>/dev/null && break
    sleep 1
done
como_postgres psql -qtAc 'SELECT 1' &>/dev/null || falha "PostgreSQL nao respondeu"

como_postgres psql -q -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_USER') THEN
        CREATE ROLE $DB_USER LOGIN;
    END IF;
END
\$\$;
ALTER ROLE $DB_USER WITH LOGIN PASSWORD '$DB_SENHA';
SQL
unset DB_SENHA

if [[ "$(como_postgres psql -qtAc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'")" == 1 ]]; then
    log "banco $DB_NAME: ja existe"
else
    log "criando banco $DB_NAME"
    como_postgres createdb -O "$DB_USER" "$DB_NAME"
fi

# --- 5. Codigo e venv em /opt/ufla-shop ---------------------------------------
log "sincronizando o codigo em $APP_DIR"
install -d -m 755 -o root -g root "$APP_DIR" "$APP_DIR/scripts"
rsync -a --delete --chown=root:root --chmod=D755,F644 --exclude '__pycache__/' \
    "$REPO_DIR/app/" "$APP_DIR/app/"
rsync -a --delete --chown=root:root --chmod=D755,F644 \
    "$REPO_DIR/static/" "$APP_DIR/static/"
install -m 644 -o root -g root "$REPO_DIR/requirements.txt" "$APP_DIR/requirements.txt"
install -m 755 -o root -g root "$REPO_DIR/scripts/backup.sh" "$APP_DIR/scripts/backup.sh"

if [[ -x $APP_DIR/.venv/bin/python ]]; then
    log "venv: ja existe"
else
    log "criando venv em $APP_DIR/.venv"
    python3 -m venv "$APP_DIR/.venv"
fi
log "instalando requirements.txt"
"$APP_DIR/.venv/bin/pip" install -q --disable-pip-version-check -r "$APP_DIR/requirements.txt"

install -d -m 750 -o "$APP_USER" -g "$APP_USER" "$BACKUP_DIR"

# --- 6. Units do systemd ------------------------------------------------------
log "instalando as units do systemd"
install -m 644 -o root -g root \
    "$REPO_DIR/systemd/ufla-shop.service" \
    "$REPO_DIR/systemd/ufla-shop-backup.service" \
    "$REPO_DIR/systemd/ufla-shop-backup.timer" \
    "$UNIT_DIR/"
systemctl daemon-reload
systemctl enable ufla-shop.service &>/dev/null
systemctl enable --now ufla-shop-backup.timer &>/dev/null
log "(re)iniciando ufla-shop.service"
systemctl restart ufla-shop.service

# --- 7. Nginx com TLS ---------------------------------------------------------
install -d -m 755 -o root -g root "$TLS_DIR"
if [[ -f $TLS_DIR/loja.pem && -f $TLS_DIR/loja.key ]]; then
    log "certificado TLS: ja existe"
else
    log "gerando certificado autoassinado em $TLS_DIR"
    openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
        -keyout "$TLS_DIR/loja.key" -out "$TLS_DIR/loja.pem" \
        -subj "/CN=localhost" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" 2>/dev/null
fi
chmod 600 "$TLS_DIR/loja.key"
chmod 644 "$TLS_DIR/loja.pem"

install -m 644 -o root -g root "$REPO_DIR/nginx/loja.conf" "$NGINX_CONF"
rm -f /etc/nginx/sites-enabled/default
if command -v setsebool &>/dev/null && selinuxenabled 2>/dev/null; then
    setsebool -P httpd_can_network_connect 1
fi
nginx -t -q
systemctl enable nginx.service &>/dev/null
log "recarregando o nginx"
systemctl reload-or-restart nginx.service

# --- 8. Healthcheck -----------------------------------------------------------
for tentativa in $(seq 1 10); do
    codigo="$(curl -s -o /dev/null -w '%{http_code}' "$READY_URL" || true)"
    if [[ $codigo == 200 ]]; then
        log "healthcheck OK: $READY_URL respondeu 200 (tentativa $tentativa/10)"
        log "$(curl -s "$READY_URL")"
        exit 0
    fi
    sleep 1
done

log "healthcheck FALHOU: $READY_URL nao respondeu 200 em 10 tentativas (ultimo codigo: $codigo)" >&2
journalctl -u ufla-shop.service -n 20 --no-pager >&2 || true
exit 1
