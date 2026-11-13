# odoo20-stack-template

Odoo 20 (Community) + PostgreSQL 17 behind Kong, nightly backups with Dagu: one docker compose project,
every port on 127.0.0.1, reached over a Tailscale tailnet with `tailscale serve`. Nothing listens on the LAN
or a public IP.

Tested on 2026-11-12/13: a fresh Ubuntu 24.04 KVM guest (4 vCPU / 8 GB / 60 GB), `./setup.sh` to a working
login, a backup, and a restore into a scratch database.

## Architecture

```
  tailnet ─► tailscale serve :443 ─► kong :8100 ─┬─ /websocket      → odoo :8072 (gevent)
                                                 ├─ /web/database   → 404 (db manager never exposed)
                                                 └─ /               → odoo :8069
  odoo:20.0 ─► postgres:17 ($DATA_ROOT/pg)       filestore $DATA_ROOT/filestore
  dagu :8092 ─► 01:00 pg_dump + filestore tar ─► $DATA_ROOT/snapshots
```

## Install

Needs Docker with the compose plugin, and Tailscale if you want HTTPS on a tailnet.

```
git clone https://github.com/laris-co/odoo20-stack-template odoo20-stack && cd odoo20-stack
cp .env.example .env      # set PUBLIC_URL (and DATA_ROOT if not /srv/odoo20/data); leave secrets empty
./setup.sh                # random secrets into .env, odoo.local.conf, dirs, database "odoo", start, verify
./setup.sh verify
sudo tailscale serve --bg --https=443 http://127.0.0.1:8100
```

The Odoo admin password is in `.env` (`ODOO_ADMIN_PASSWD` is the master password; set the `admin` user's own
password in Odoo right after the first login).

## Configuration

| variable | meaning |
|---|---|
| `DATA_ROOT` | all state (pg, filestore, dagu, snapshots) |
| `ODOO_DB` | the one database (`dbfilter`), default `odoo` |
| `PUBLIC_URL` | the URL people open; setup.sh sets Odoo `web.base.url` to it and verifies through it |
| `PG_PASSWORD` `ODOO_ADMIN_PASSWD` `DAGU_ADMIN_PASSWORD` `DAGU_TOKEN_SECRET` | random, written by setup.sh into `.env` (chmod 600, gitignored) |

`odoo/odoo.conf.template` is committed; `odoo/odoo.local.conf` (with the master password) is generated and gitignored.
`proxy_mode = True`, `list_db = False`.

## Backups

Dagu runs `dagu/odoo-backup.yaml` at 01:00: a `pg_dump -Fc` of the database and a tar of the filestore into
`$DATA_ROOT/snapshots`. A database without its filestore loses every attachment, so restore both. Copy the
snapshots off the machine yourself. `./setup.sh verify` prints the newest snapshot's age and flags it STALE past 26 h.

## Traps we hit (all fixed here)

- Odoo 20 binds 127.0.0.1 inside its container, so Kong cannot reach it: `http_interface = 0.0.0.0`,
  on its own line (an inline `;` comment breaks the value).
- The filestore belongs to the image's `odoo` user (uid 100 / gid 101 in `odoo:20.0`); setup.sh asks the image
  with `id` instead of guessing.
- Dagu runs as root inside its container (`PUID`/`PGID` 0). Odoo's filestore dirs are 0700 for uid 100, and
  `docker exec` runs as root, so a non-root Dagu could neither tar the filestore nor read state a manual run
  had written. One night's scheduled backup was skipped (`open /var/lib/dagu/data/proc/odoo-backup: permission denied`)
  before this was fixed. The container has no Docker socket.
- Dagu needs its DAGs directory writable (it creates a wiki dir next to the DAGs), so it is not mounted `:ro`.

## Going public

Keep it tailnet-only until you need otherwise. Before any public host: a Tailscale ACL tag so the public node can
reach only Kong, then a reverse proxy with its own auth in front; `/web/database` stays 404.

## License

MIT, see [LICENSE](LICENSE).
