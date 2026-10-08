# Self-hosting

Anyone can run their own Privee server. The supported way is
[Fly.io](https://fly.io), using the
[PriveeDeploy](https://github.com/MaxDac/PriveeDeploy) template: a small
repository that holds only your Fly configuration and a deploy workflow, and
deploys the prebuilt Privee image. You don't need to fork or build the code.

Web users then open `https://<your host>`. Users of the
[Android app](https://github.com/MaxDac/PriveeApp) type the same address on the
app's server screen; the app has no default server, so nothing in it needs to
change. Other clients can use the [Client API](client-api.md).

## Before you start

- A [Fly.io account](https://fly.io/app/sign-up) and
  [`flyctl`](https://fly.io/docs/flyctl/install/), logged in with `fly auth login`.
- A GitHub account.
- **One application machine.** Encrypted messages wait in memory on the machine
  serving the conversation until they are delivered (see
  [End-to-end encryption](e2e-encryption.md#deliberate-trade-offs)). Never run
  more than one machine, and expect undelivered messages to be lost when it
  restarts or stops.

## Walkthrough

### 1. Create your deployment repository

Open [PriveeDeploy](https://github.com/MaxDac/PriveeDeploy), click
**Use this template → Create a new repository**, and clone it. Public or private
both work.

### 2. Create the Fly app

Pick a name; it becomes `<app>.fly.dev`.

```bash
fly apps create <app>
```

### 3. Create the database

Any PostgreSQL reachable from the app works. On Fly,
[Managed Postgres](https://fly.io/docs/mpg/) is the simplest:

```bash
fly mpg create
fly mpg attach <cluster id> -a <app>   # sets the DATABASE_URL secret
```

For a database elsewhere, set the URL yourself (add `ENABLE_DB_SSL=true` if it
requires SSL):

```bash
fly secrets set DATABASE_URL=ecto://USER:PASS@HOST/DATABASE -a <app>
```

### 4. Set the secret key

```bash
fly secrets set SECRET_KEY_BASE=$(openssl rand -base64 48) -a <app>
```

### 5. Connect GitHub to Fly

Create a deploy token:

```bash
fly tokens create deploy -a <app>
```

In your repository, open **Settings → Secrets and variables → Actions** and add:

- secret `FLY_API_TOKEN`: the token above;
- variable `FLY_APP`: `<app>`.

Optional variables:

| Variable | Default | Description |
| --- | --- | --- |
| `PHX_HOST` | `<FLY_APP>.fly.dev` | Public DNS name, e.g. a custom domain. |
| `PRIVEE_IMAGE` | `ghcr.io/maxdac/privee:latest` | Image to deploy (see [Updating](#updating)). |
| `PRIVEE_INSTANCE_NAME` | — | Display name reported to clients. |
| `PRIVEE_SOURCE_URL` | source of the image | Only needed if you run code that isn't in the image's repository. |

### 6. Adjust `fly.toml` (optional)

[`fly.toml`](https://github.com/MaxDac/PriveeDeploy/blob/main/fly.toml) in
your repository is yours to change: `primary_region` (pick one close to your
users), machine size, and auto-stop. The template keeps one machine always on.
Letting Fly stop it when idle (`auto_stop_machines = 'stop'`,
`min_machines_running = 0`) is cheaper, but undelivered messages are lost every
time it stops. Don't set `app` or `PHX_HOST` there; the workflow passes them.

### 7. Deploy

Run **Actions → Deploy → Run workflow**. Later, every push to `main` deploys.
Each deploy runs the database migrations first. Check the instance:

```bash
curl https://<app>.fly.dev/api/app/info
```

It answers with `"service": "privee"`. Open the address in a browser, or enter
it in the Android app.

### 8. Custom domain (optional)

Point your domain's DNS to the app (`fly ips list -a <app>`), then:

```bash
fly certs add chat.example.com -a <app>
```

Fly issues and renews the certificate. Set the `PHX_HOST` variable to
`chat.example.com` and deploy again: the server only accepts browser
connections for the host it is configured with.

## Updating

`PRIVEE_IMAGE` chooses what you run:

- `ghcr.io/maxdac/privee:latest`: the latest release (default);
- `ghcr.io/maxdac/privee:<version>`, e.g. `1.2.0`: a fixed release;
- `ghcr.io/maxdac/privee:main`: the latest commit on `main`;
- `ghcr.io/maxdac/privee:sha-<commit>`: a single commit.

Deploys pull the tag again, so re-run the Deploy workflow to update `latest` or
`main`. Release notes are on the
[Privee releases page](https://github.com/MaxDac/Privee/releases).

## Running modified code

To change the server code, fork [Privee](https://github.com/MaxDac/Privee). On
every push to `main` (and every `v*` tag), the fork's **Main** workflow publishes
`ghcr.io/<your user>/privee`, labelled with the fork as its source. Make that
package public (or give Fly access to it), then set `PRIVEE_IMAGE` in your
deployment repository to it. Your fork's own Fly deploy job only runs upstream,
so it stays inert.

## Configuration reference

The deploy workflow and `fly.toml` set most of these for you.

| Variable | Required | Description |
| --- | --- | --- |
| `PHX_HOST` | yes | Public DNS name of the instance, without scheme. |
| `SECRET_KEY_BASE` | yes | At least 64 random bytes, e.g. `mix phx.gen.secret` or `openssl rand -base64 48`. |
| `DATABASE_URL` | yes | `ecto://USER:PASS@HOST/DATABASE` |
| `PORT` | no | HTTP port the app listens on, default `4000`. |
| `PHX_PORT` | no | Public HTTPS port used in generated URLs, default `443`. |
| `PROXY_HOPS` | no | Position, from the right of `X-Forwarded-For`, of the client address added by trusted proxies; default `0` (header ignored). The Fly config sets it to `2`, because Fly appends the client address followed by the app's own IP. If it is wrong, every client shares one address in the login rate limit. Never set it higher than the real number of entries appended by trusted proxies, or clients can spoof their address. |
| `PRIVEE_INSTANCE_NAME` | no | Display name shown to clients by `GET /api/app/info`. |
| `PRIVEE_SOURCE_URL` | no | Source code of the version you run. Published images set it to the repository they were built from; otherwise `https://github.com/MaxDac/Privee`. |
| `POOL_SIZE` | no | Database pool size, default `10`. |
| `ENABLE_DB_SSL` | no | `true` to connect to PostgreSQL over SSL. |
| `ECTO_IPV6` | no | `true` to connect to PostgreSQL over IPv6 (set automatically on Fly). |

### Licence obligations

Privee is licensed under the [AGPL-3.0](../LICENSE). If you change the code and
let other people use your instance, you must offer them the source of your
version: publish your fork and run its image (or set `PRIVEE_SOURCE_URL` to
it). The web interface links to that URL and the info endpoint reports it. See
[NOTICE](../NOTICE).

## Other platforms

Only Fly.io is supported and documented. Running elsewhere (Docker, Kubernetes
on another cloud, on-premises) is your choice and responsibility. The
`ghcr.io/maxdac/privee` image is a standard Linux (`amd64`) container that
listens on `PORT`. You need to provide:

- the variables in the [configuration reference](#configuration-reference);
- PostgreSQL, and migrations before each release: run `/app/bin/migrate` in the
  image (e.g. a Kubernetes init container or Job);
- TLS termination in a reverse proxy that forwards WebSocket upgrades on `/live`
  and `/app/socket` and sets `X-Forwarded-Proto`, with `PROXY_HOPS` set to the
  position of the client address from the right of `X-Forwarded-For` (usually
  the number of proxies in front of the app);
- exactly one replica (e.g. a Kubernetes `Deployment` with `replicas: 1` and the
  `Recreate` strategy).
