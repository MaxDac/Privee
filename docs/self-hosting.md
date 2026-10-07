# Self-hosting

Privee is meant to be run by anyone: clone or fork this repository, deploy it
to [Fly.io](https://fly.io), and chat over your own infrastructure. Web users open
`https://<your host>`. Users of the
[Android app](https://github.com/MaxDac/PriveeApp) enter the same address on the
app's server screen. Other clients can use the [Client API](client-api.md).

## Requirements

- A Fly.io account. Fly terminates TLS and issues the certificate for your
  `*.fly.dev` name or custom domain.
- A PostgreSQL database reachable from the app (for example Fly Postgres).
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
| `PROXY_HOPS` | no | Position, from the right of `X-Forwarded-For`, of the client address added by trusted proxies; default `0` (header ignored). `fly.toml` sets it to `2`, because Fly appends the client address followed by the app's own IP. If it is wrong, every client shares one address in the login rate limit. Never set it higher than the real number of entries appended by trusted proxies, or clients can spoof their address. |
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

## Fly.io

Copy [`fly.toml`](../fly.toml), then change `app` and `PHX_HOST` (for example
`<your app>.fly.dev`, or your own domain). Create a Postgres database and set
the secrets:

```bash
fly launch --no-deploy --copy-config --name <your app>
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret) DATABASE_URL=ecto://... -a <your app>
fly deploy --remote-only
```

For a custom domain, point its DNS to the app and run
`fly certs add <your domain>`; Fly issues and renews the certificate. Check that
the instance is up:

```bash
curl https://<your host>/api/app/info
```

Keep a single machine (`fly scale count 1`). The `release_command` runs
migrations on every deploy. The GitHub deploy workflow only runs in the
upstream repository, so in a fork either deploy manually or change the
`if:` condition in `.github/workflows/main.yml` and add your own
`FLY_API_TOKEN`.

## Other platforms

Only Fly.io is supported by this repository. You can run the release built by
the [Dockerfile](../Dockerfile) elsewhere, but then TLS termination, the
reverse proxy (forwarding WebSocket upgrades on `/live` and `/app/socket` and
setting `X-Forwarded-Proto`), PostgreSQL and migrations (`bin/migrate`) are
your responsibility. Set `PROXY_HOPS` to the position of the client address
from the right of `X-Forwarded-For` (usually the number of proxies in front of
the app).
