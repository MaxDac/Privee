# Self-hosting

Anyone can run their own Privee server. The supported path is **Fly.io through
[PriveeDeploy](https://github.com/MaxDac/PriveeDeploy)**: fork it, add your own
Fly.io keys and run its Deploy workflow. The full walkthrough is in the
[PriveeDeploy README](https://github.com/MaxDac/PriveeDeploy#readme).

You don't need to fork this repository unless you want to change the code; if
you do, point your PriveeDeploy fork at your Privee fork with its `PRIVEE_REPO`
variable.

Clients connect to any instance by its DNS name: the
[Privee Android app](https://github.com/MaxDac/PriveeApp) asks for a server
address and checks it through `GET /api/app/info`, so it needs no changes for
your server.

## Configuration reference

The release reads these environment variables at runtime.

| Variable | Required | Description |
| --- | --- | --- |
| `DATABASE_URL` | yes | Postgres URL, e.g. `ecto://user:pass@host/db`. |
| `SECRET_KEY_BASE` | yes | Generate with `mix phx.gen.secret` or `openssl rand -base64 48`. |
| `PHX_HOST` | yes | Public DNS name of the instance, used in generated URLs and origin checks. |
| `PHX_PORT` | no | Public HTTPS port used in generated URLs, defaults to `443`. |
| `PORT` | no | Port the HTTP server listens on, defaults to `4000`. |
| `PROXY_HOPS` | no | Position of the client address from the right of `X-Forwarded-For`, used for per-client rate limits (`2` on Fly.io). |
| `PRIVEE_INSTANCE_NAME` | no | Display name reported by `GET /api/app/info`. |
| `PRIVEE_SOURCE_URL` | no | Link to the source code of the running version, defaults to `https://github.com/MaxDac/Privee`. |
| `POOL_SIZE` | no | Database pool size. |
| `ENABLE_DB_SSL` | no | Enables SSL for the database connection. |
| `DNS_CLUSTER_QUERY` | no | DNS query used to cluster nodes; set automatically on Fly.io. |

[`rel/env.sh.eex`](../rel/env.sh.eex) detects Fly.io through `FLY_APP_NAME`
and sets the node name and IPv6 distribution; elsewhere the node falls back to
a short name.

## Licence obligations

Privee is licensed under the [GNU AGPL v3](../LICENSE). If you run a modified
version for other people, you must offer them its source code: publish your fork
and set `PRIVEE_SOURCE_URL` to it (PriveeDeploy does this from `PRIVEE_REPO`).

## Other platforms

Docker, Kubernetes and other clouds are not supported, but the
[`Dockerfile`](../Dockerfile) builds a self-contained release you can run
anywhere. Keep in mind:

- Run migrations before each new version starts: `/app/bin/migrate`.
- Put a TLS-terminating proxy in front and allow WebSocket upgrades on `/live`
  (LiveView) and `/app/socket` (mobile clients).
- Set `PROXY_HOPS` to match your proxy chain, or rate limits will apply to the
  proxy address instead of clients.
- Run a **single replica**. Encrypted chat messages are kept in memory on the
  node serving the conversation and are lost on restart; see
  [End-to-end encryption](e2e-encryption.md#deliberate-trade-offs).
