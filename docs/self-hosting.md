# Self-hosting

Privee is meant to be run by anyone: clone or fork this repository, deploy it
on your own server, and chat over your own infrastructure. Web users open
`https://<your host>`. Users of the
[Android app](https://github.com/MaxDac/PriveeApp) enter the same address on the
app's server screen. Other clients can use the [Client API](client-api.md).

## Requirements

- A DNS name (for example `privee.example.org`) pointing to your server.
- HTTPS. Privee forces SSL in production, so it must run behind a reverse proxy
  that terminates TLS and sets `X-Forwarded-Proto` (Caddy, nginx, Traefik, Fly).
- PostgreSQL 14 or later.
- **A single application node.** Encrypted messages are held in memory on the
  node serving the conversation (see
  [End-to-end encryption](e2e-encryption.md#deliberate-trade-offs)). Do not run
  more than one replica, and expect undelivered messages to be lost on restart.

## Configuration

| Variable | Required | Description |
| --- | --- | --- |
| `PHX_HOST` | yes | Public DNS name of the instance, without scheme. |
| `SECRET_KEY_BASE` | yes | At least 64 random bytes, e.g. `mix phx.gen.secret` or `openssl rand -base64 48`. |
| `DATABASE_URL` | yes | `ecto://user:password@host/database` |
| `PORT` | no | HTTP port the app listens on, default `4000`. |
| `PHX_PORT` | no | Public HTTPS port used in generated URLs, default `443`. |
| `PRIVEE_INSTANCE_NAME` | no | Display name shown to clients by `GET /api/app/info`. |
| `PRIVEE_SOURCE_URL` | no | Source code of the version you run, default `https://github.com/MaxDac/Privee`. |
| `POOL_SIZE` | no | Database pool size, default `10`. |
| `ENABLE_DB_SSL` | no | `true` to connect to PostgreSQL over SSL. |
| `ECTO_IPV6` | no | `true` to connect to PostgreSQL over IPv6. |

### Licence obligations

Privee is licensed under the [AGPL-3.0](../LICENSE). If you change the code and
let other people use your instance, you must offer them the source of your
version: publish your fork and set `PRIVEE_SOURCE_URL` to it. The web interface
links to that URL and the info endpoint reports it. See [NOTICE](../NOTICE).

## Docker Compose (recommended)

[`docker-compose.yml`](../docker-compose.yml) runs Privee, PostgreSQL and
[Caddy](https://caddyserver.com), which obtains a Let's Encrypt certificate for
`PHX_HOST` automatically. Ports 80 and 443 must be reachable from the internet.

```bash
git clone https://github.com/MaxDac/Privee.git && cd Privee
cp .env.example .env    # set PHX_HOST, SECRET_KEY_BASE, POSTGRES_PASSWORD
docker compose up -d --build
```

Migrations run every time the `privee` container starts. Check that the
instance is up:

```bash
curl https://privee.example.org/api/app/info
```

To upgrade, pull the new code and rebuild:

```bash
git pull && docker compose up -d --build
```

## Fly.io

Copy [`fly.toml`](../fly.toml), then change `app` and `PHX_HOST` (for example
`<your app>.fly.dev`, or your own domain). Create a Postgres database and set
the secrets:

```bash
fly launch --no-deploy --copy-config --name <your app>
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret) DATABASE_URL=ecto://... -a <your app>
fly deploy --remote-only
```

Keep a single machine (`fly scale count 1`). The `release_command` runs
migrations on every deploy. The GitHub deploy workflow only runs in the
upstream repository, so in a fork either deploy manually or change the
`if:` condition in `.github/workflows/main.yml` and add your own
`FLY_API_TOKEN`.

## Bare release

Build a release with the toolchain from `.tool-versions`:

```bash
export MIX_ENV=prod
mix deps.get --only prod
npm ci --omit=dev --prefix apps/privee_web/assets
mix compile
mix assets.deploy
mix release
```

Then, with the variables above exported, run migrations and start the server:

```bash
_build/prod/rel/privee_umbrella/bin/migrate
_build/prod/rel/privee_umbrella/bin/server
```

Put a TLS-terminating reverse proxy in front of `PORT`. It must forward
WebSocket upgrades (`/live` and `/app/socket`) and set `X-Forwarded-Proto`.
