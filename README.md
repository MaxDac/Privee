# Privee

[![CI](https://github.com/MaxDac/Privee/actions/workflows/ci.yml/badge.svg)](https://github.com/MaxDac/Privee/actions/workflows/ci.yml)
[![Main](https://github.com/MaxDac/Privee/actions/workflows/main.yml/badge.svg)](https://github.com/MaxDac/Privee/actions/workflows/main.yml)

Privee is a Phoenix LiveView umbrella application:

- `apps/privee` holds the domain logic and Ecto schemas.
- `apps/privee_web` holds the web layer: LiveViews, components and assets.

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
- a Docker image build

Enable the pre-commit hook, which runs `mix precommit`:

```bash
git config core.hooksPath .githooks
```

Editor setup notes are in [docs/ide-setup.md](docs/ide-setup.md).

## CI/CD

All workflows live in [`.github/workflows`](./.github/workflows):

| Workflow | Trigger | What it does |
| --- | --- | --- |
| [`ci.yml`](./.github/workflows/ci.yml) | Pull requests, manual, reusable | Elixir checks + tests (with Postgres), Dialyzer, asset checks, Docker build |
| [`main.yml`](./.github/workflows/main.yml) | Push to `main`, manual | Runs `ci.yml`, then deploys to Fly.io when it passes |

The deploy job targets the `production` GitHub environment and authenticates with the `FLY_API_TOKEN` environment secret. Create the token with:

```bash
fly tokens create deploy -a privee
```

## Deployment (Fly.io)

[`fly.toml`](./fly.toml) configures the app. Fly builds the [`Dockerfile`](./Dockerfile) remotely. Each deploy runs migrations through the `release_command` (`/app/bin/migrate`).

Set these runtime secrets on the Fly app:

```bash
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret) DATABASE_URL=ecto://... -a privee
```

Optional variables:

- `PHX_HOST`: defaults to `privee.fly.dev`.
- `POOL_SIZE`: database pool size.
- `ENABLE_DB_SSL`: enables SSL for the database connection.
- `DNS_CLUSTER_QUERY`: e.g. `privee.internal`, to cluster multiple machines.

[`rel/env.sh.eex`](./rel/env.sh.eex) detects Fly through `FLY_APP_NAME` and sets the node name and IPv6 distribution. Outside Fly the node falls back to a short name.

To deploy manually from a workstation:

```bash
fly deploy --remote-only
```
