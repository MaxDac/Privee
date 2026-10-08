# Privee

[![CI](https://github.com/MaxDac/Privee/actions/workflows/ci.yml/badge.svg)](https://github.com/MaxDac/Privee/actions/workflows/ci.yml)
[![Main](https://github.com/MaxDac/Privee/actions/workflows/main.yml/badge.svg)](https://github.com/MaxDac/Privee/actions/workflows/main.yml)

Privee is a Phoenix LiveView umbrella application:

- `apps/privee` holds the domain logic and Ecto schemas.
- `apps/privee_web` holds the web layer: LiveViews, components and assets.

Chats are end-to-end encrypted with the Signal Protocol. See
[End-to-end encryption](docs/e2e-encryption.md) for the design, its trade-offs
(local plaintext history, node-local ciphertext, one device per session) and the
manual release checklist, and the [E2EE audit](docs/security/e2ee-audit.md) for
the independent review of the web, server and Android implementations.

## Run your own server

Anyone can run their own Privee server on Fly.io without forking this
repository: create a repository from the
[PriveeDeploy](https://github.com/MaxDac/PriveeDeploy) template, which deploys
the prebuilt `ghcr.io/maxdac/privee` image with your own `fly.toml`.
**Follow the step-by-step [Self-hosting walkthrough](docs/self-hosting.md).**

Clients work with any instance through its DNS name: the
[Privee Android app](https://github.com/MaxDac/PriveeApp) asks for a server
address, and other clients can use the [Client API](docs/client-api.md).

## Toolchain

Versions are pinned in [`.tool-versions`](./.tool-versions) for Erlang/OTP, Elixir and Node.js. CI reads the same file, so use [asdf](https://asdf-vm.com/) or [mise](https://mise.jdx.dev/) to install matching versions:

```bash
mise install   # or: asdf install
```

You also need a PostgreSQL server. The dev and test configs expect `postgres`/`postgres` on `localhost:5432`.

```bash
docker run --name privee-database -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres \
  --restart=unless-stopped -p 5432:5432 -d postgres:18
```

Podman accepts the same arguments (`podman run ...`).

## Getting started

```bash
mix setup          # deps, database, esbuild/tailwind binaries, npm packages
mix phx.server     # or: iex -S mix phx.server
```

The app listens on [`localhost:4000`](http://localhost:4000).

## Checks

Before pushing, run:

```bash
mix precommit
```

It compiles with `--warnings-as-errors`, unlocks unused deps, formats the code, then runs `credo --strict`, the tests and `npm run check` for the assets (prettier, tsc, eslint, vitest). CI runs the same checks in check-only mode, plus:

- `mix dialyzer` (PLTs are stored in `priv/plts`)
- browser end-to-end tests (below)
- a Docker image build

### Browser end-to-end tests

[Playwright](https://playwright.dev) specs in [`apps/privee_web/assets/e2e`](apps/privee_web/assets/e2e) drive real browsers through registration and encrypted chats: messages both ways, bursts, an offline recipient, reloads, and a check that no plaintext crosses the WebSocket. Each simulated user gets its own browser context, so it is a separate Signal device.

```bash
cd apps/privee_web/assets
npm run e2e:install   # once: downloads Chromium
npm run e2e           # starts `mix phx.server` and runs the specs
```

To reuse a running server, set `E2E_BASE_URL` (e.g. `E2E_BASE_URL=http://localhost:4000 npm run e2e`). To use an installed browser instead of the downloaded Chromium, set `E2E_BROWSER_CHANNEL` (e.g. `msedge` or `chrome`). CI runs the specs against a production build (`MIX_ENV=prod`, `mix assets.deploy`) and uploads the report and traces when they fail.

Enable the pre-commit hook, which runs `mix precommit`:

```bash
git config core.hooksPath .githooks
```

Editor setup notes are in [docs/ide-setup.md](docs/ide-setup.md).

## CI/CD

All workflows live in [`.github/workflows`](./.github/workflows):

| Workflow | Trigger | What it does |
| --- | --- | --- |
| [`ci.yml`](./.github/workflows/ci.yml) | Pull requests, manual, reusable | Elixir checks + tests (with Postgres), Dialyzer, asset checks, Playwright browser tests, Docker build |
| [`main.yml`](./.github/workflows/main.yml) | Push to `main`, `v*` tags, manual | Runs `ci.yml`, then publishes the Docker image to GHCR and (from `main`) deploys to Fly.io |

The image is published as `ghcr.io/<owner>/privee`, tagged `main` and `sha-<commit>` on every push to `main`, and `<version>` and `latest` on `v*` tags (e.g. `v1.2.0` → `1.2.0`). Self-hosters deploy it with [PriveeDeploy](https://github.com/MaxDac/PriveeDeploy). Release a version with:

```bash
git tag v1.2.0 && git push origin v1.2.0
```

The deploy job only runs in the upstream `MaxDac/Privee` repository, so forks get CI without trying to deploy. It targets the `production` GitHub environment and authenticates with the `FLY_API_TOKEN` environment secret. Create the token with:

```bash
fly tokens create deploy -a bauta
```

## Deployment (Fly.io)

This section describes the upstream instance. To run your own, follow
[Self-hosting](docs/self-hosting.md) instead of editing these files.

> **Chat storage is node-local.** Encrypted messages are kept in ETS on the node
> serving the conversation and are lost on restart, so the chat must run as a
> single Fly machine. See
> [End-to-end encryption](docs/e2e-encryption.md#deliberate-trade-offs).

[`fly.toml`](./fly.toml) configures the app. Fly builds the [`Dockerfile`](./Dockerfile) remotely. Each deploy runs migrations through the `release_command` (`/app/bin/migrate`).

Set these runtime secrets on the Fly app (`PHX_HOST` is already set in `fly.toml`):

```bash
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret) DATABASE_URL=ecto://... -a bauta
```

Required variables: `DATABASE_URL`, `SECRET_KEY_BASE` and `PHX_HOST` (the public DNS name of the instance).

Optional variables:

- `PHX_PORT`: public HTTPS port used in generated URLs, defaults to `443`.
- `PROXY_HOPS`: position of the client address from the right of `X-Forwarded-For` (`2` on Fly.io, set in `fly.toml`), used for per-client rate limits.
- `PRIVEE_INSTANCE_NAME`: display name reported by `GET /api/app/info`.
- `PRIVEE_SOURCE_URL`: link to the source code of the running version. Images published by `main.yml` default it to the repository that built them; otherwise it defaults to `https://github.com/MaxDac/Privee`.
- `POOL_SIZE`: database pool size.
- `ENABLE_DB_SSL`: enables SSL for the database connection.
- `DNS_CLUSTER_QUERY`: e.g. `privee.internal`, to cluster multiple machines.

[`rel/env.sh.eex`](./rel/env.sh.eex) detects Fly through `FLY_APP_NAME` and sets the node name and IPv6 distribution. Outside Fly the node falls back to a short name.

To deploy manually from a workstation:

```bash
fly deploy --remote-only
```

## License

Privee is free software, licensed under the
[GNU Affero General Public License v3.0 only](LICENSE) (`AGPL-3.0-only`).
Every fork, modified version or derived work must stay under the same licence,
and anyone who runs a Privee server for other people must offer them the
source code of the version they run. You cannot use this code in proprietary or
non-FOSS software. See [NOTICE](NOTICE) for details and third-party components.
