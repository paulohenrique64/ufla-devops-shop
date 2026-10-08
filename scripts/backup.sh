#!/usr/bin/env bash
# Backup do banco loja com rotacao dos 7 mais recentes. Uso: sudo systemctl start ufla-shop-backup.service
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/ufla-shop}"
MANTER="${MANTER:-7}"
: "${DATABASE_URL:?DATABASE_URL nao definida (carregue /etc/ufla-shop.env)}"

trap 'logger -t backup -p user.err "falha no backup do banco loja (linha $LINENO)"' ERR

umask 077
mkdir -p "$BACKUP_DIR"

arquivo="$BACKUP_DIR/loja-$(date +%Y-%m-%d-%H%M).sql.gz"
parcial="$arquivo.parcial"
trap 'rm -f "$parcial"' EXIT

pg_dump --no-owner --dbname="$DATABASE_URL" | gzip -9 > "$parcial"
mv -f "$parcial" "$arquivo"

shopt -s nullglob
dumps=("$BACKUP_DIR"/loja-*.sql.gz)
excesso=$(( ${#dumps[@]} - MANTER ))
if (( excesso > 0 )); then
    rm -f -- "${dumps[@]:0:excesso}"
fi

tamanho="$(du -h --apparent-size "$arquivo" | cut -f1)"
logger -t backup "backup gerado: $arquivo ($tamanho); mantidos os $MANTER mais recentes"
echo "backup gerado: $arquivo ($tamanho)"
