#!/usr/bin/env bash
# odoo20-stack — one command on a Linux host with Docker.
#   ./setup.sh          first run: .env secrets, odoo.local.conf, data dirs, start, create the database, verify
#   ./setup.sh verify   only the checks
# Re-running is safe: every step skips what already exists. Nothing secret is printed.
set -euo pipefail
cd "$(dirname "$0")"

say() { printf '\033[1;34m==\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }
getenv() { grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- || true; }
setenv() { grep -qE "^$1=" .env && sed -i "s|^$1=.*|$1=$2|" .env || echo "$1=$2" >> .env; }
code() { curl -s -m 10 -o /dev/null -w '%{http_code}' "$1"; }

verify() {
  say "verify"
  docker compose ps --format '{{.Service}}  {{.Status}}'
  local k; k=$(getenv KONG_PORT); k=${k:-8100}
  printf 'odoo  /web/login (direct)        %s\n' "$(code "http://127.0.0.1:$(getenv ODOO_PORT || echo 8069)/web/login")"
  printf 'kong  /web/login                 %s\n' "$(code "http://127.0.0.1:$k/web/login")"
  printf 'kong  /web/database/manager      %s  (must be 404)\n' "$(code "http://127.0.0.1:$k/web/database/manager")"
  printf 'kong  /websocket                 %s\n' "$(code "http://127.0.0.1:$k/websocket")"
  local u; u=$(getenv PUBLIC_URL)
  if [ -n "$u" ]; then
    printf 'url   %s/web/login   %s\n' "$u" "$(code "$u/web/login")"
    printf 'url   %s/web/database/manager   %s  (must be 404)\n' "$u" "$(code "$u/web/database/manager")"
  fi
  docker compose exec -T db psql -U odoo -d "$(getenv ODOO_DB)" -tAc \
    "select 'modules installed: ' || count(*) from ir_module_module where state='installed'" 2>/dev/null || echo "database not created yet"
  # the nightly 01:00 backup must be younger than 26 h; a missed night printed nothing before 2026-11-13
  local snap age perr
  snap=$(ls -t "$(getenv DATA_ROOT)"/snapshots/odoo-*.dump 2>/dev/null | head -1 || true)
  if [ -n "$snap" ]; then
    age=$(( ($(date +%s) - $(stat -c %Y "$snap")) / 3600 ))
    printf 'backup newest %s  %s h old%s\n' "$(basename "$snap")" "$age" "$([ "$age" -gt 26 ] && echo '  STALE (over 26 h: a 01:00 run was missed)')"
  else
    echo "backup none yet"
  fi
  perr=$(docker logs --since 10m o20-dagu 2>&1 | grep -c 'permission denied' || true)
  [ "${perr:-0}" = 0 ] || printf 'dagu  %s "permission denied" lines in the last 10 min (scheduler cannot read its state)\n' "$perr"
}

[ "${1:-}" = verify ] && { verify; exit 0; }

say "preflight"
command -v docker >/dev/null || die "docker missing"
docker compose version >/dev/null || die "docker compose plugin missing"
[ -f .env ] || cp .env.example .env
chmod 600 .env
for k in PG_PASSWORD ODOO_ADMIN_PASSWD DAGU_ADMIN_PASSWORD; do
  [ -n "$(getenv $k)" ] || setenv $k "$(openssl rand -base64 24 | tr -d '/+=')"
done
[ -n "$(getenv DAGU_TOKEN_SECRET)" ] || setenv DAGU_TOKEN_SECRET "$(openssl rand -hex 32)"
DATA_ROOT=$(getenv DATA_ROOT); [ -n "$DATA_ROOT" ] || die "DATA_ROOT empty"
DB=$(getenv ODOO_DB); DB=${DB:-odoo}

say "odoo.local.conf (gitignored, holds admin_passwd)"
sed -e "s|__ADMIN_PASSWD__|$(getenv ODOO_ADMIN_PASSWD)|" -e "s|__PG_PASSWORD__|$(getenv PG_PASSWORD)|" \
    -e "s|__ODOO_DB__|$DB|" odoo/odoo.conf.template > odoo/odoo.local.conf
chmod 644 odoo/odoo.local.conf

say "pull images (odoo:20.0 is about 1 GB on a fresh host)"
docker compose pull -q db odoo kong
docker pull -q alpine >/dev/null

say "data dirs under $DATA_ROOT"
mkdir -p "$DATA_ROOT"/{pg,filestore,dagu,snapshots}
# the filestore belongs to the image's odoo user (uid 100 / gid 101 in odoo:20.0) — ask the image, don't guess
OU=$(docker run --rm --entrypoint id odoo:20.0 -u odoo); OG=$(docker run --rm --entrypoint id odoo:20.0 -g odoo)
docker run --rm -v "$DATA_ROOT":/d alpine sh -c "chown -R $OU:$OG /d/filestore" >/dev/null

say "start db + build dagu"
docker compose up -d db
docker compose build -q dagu

say "create database $DB (base module) if missing"
if ! docker compose exec -T db psql -U odoo -d postgres -tAc "select 1 from pg_database where datname='$DB'" | grep -q 1; then
  docker compose run --rm odoo odoo -c /etc/odoo/odoo.conf -d "$DB" -i base --stop-after-init \
    || die "database init failed (docker compose logs odoo)"
fi

say "start everything"
docker compose up -d
for i in $(seq 1 30); do [ "$(code http://127.0.0.1:$(getenv KONG_PORT)/web/login)" = 200 ] && break; sleep 3; done
verify
U=$(getenv PUBLIC_URL)
if [ -n "$U" ]; then
  # links Odoo writes (emails, portal, reports) use the tailnet URL, never localhost
  docker compose exec -T db psql -U odoo -d "$DB" -qc \
    "insert into ir_config_parameter (key, value) values ('web.base.url', '$U'), ('web.base.url.freeze', 'True')
     on conflict (key) do update set value = excluded.value" >/dev/null
  say "done. Odoo: $U  (local: http://127.0.0.1:$(getenv KONG_PORT))"
else
  say "done. Odoo: http://127.0.0.1:$(getenv KONG_PORT) — set PUBLIC_URL in .env after: sudo tailscale serve --bg --https=443 http://127.0.0.1:$(getenv KONG_PORT)"
fi
