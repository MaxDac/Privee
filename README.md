# Privee

[![CI](https://github.com/MaxDac/Privee/actions/workflows/ci.yml/badge.svg)](https://github.com/MaxDac/Privee/actions/workflows/ci.yml)

Privee is a Phoenix LiveView umbrella application:

- `apps/privee` holds the domain logic and Ecto schemas.
- `apps/privee_web` holds the web layer: LiveViews, components and assets.

Chats are end-to-end encrypted with the Signal Protocol. See
[End-to-end encryption](docs/e2e-encryption.md) for the design, its trade-offs
(local plaintext history, node-local ciphertext, one device per session) and the
manual release checklist, and the [E2EE audit](docs/security/e2ee-audit.md) for
the independent review of the web, server and Android implementations.

## Run your own server

Anyone can run their own Privee server on Fly.io: fork
[PriveeDeploy](https://github.com/MaxDac/PriveeDeploy), add your Fly.io keys,
and run its Deploy workflow. It builds Privee (or your fork of it) with your own
`fly.toml`. **The step-by-step walkthrough is in the
[PriveeDeploy README](https://github.com/MaxDac/PriveeDeploy#readme)**;
[Self-hosting](docs/self-hosting.md) lists the server configuration and notes on
other platforms.

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

[`ci.yml`](./.github/workflows/ci.yml) runs on pull requests, on every push to `main` and on demand: Elixir checks and tests (with Postgres), Dialyzer, asset checks, Playwright browser tests and a Docker build.

This repository never deploys. Deployments run on demand from [PriveeDeploy](https://github.com/MaxDac/PriveeDeploy), which checks out a chosen commit of Privee and deploys it to Fly.io; the upstream instance and its `fly.toml` live there. To deploy from a workstation:

```bash
gh workflow run deploy.yml -R MaxDac/PriveeDeploy -f ref=$(git rev-parse origin/main)
```

AI agents follow the [`deploy-privee`](.github/skills/deploy-privee/SKILL.md) skill, which checks CI and asks for confirmation first.

The release reads its configuration from environment variables, listed in [Self-hosting](docs/self-hosting.md#configuration-reference). [`rel/env.sh.eex`](./rel/env.sh.eex) detects Fly through `FLY_APP_NAME` and sets the node name and IPv6 distribution; outside Fly the node falls back to a short name.

> **Chat storage is node-local.** Encrypted messages are kept in ETS on the node
> serving the conversation and are lost on restart, so the chat must run as a
> single machine. See
> [End-to-end encryption](docs/e2e-encryption.md#deliberate-trade-offs).

## License

Privee is free software, licensed under the
[GNU Affero General Public License v3.0 only](LICENSE) (`AGPL-3.0-only`).
Every fork, modified version or derived work must stay under the same licence,
and anyone who runs a Privee server for other people must offer them the
source code of the version they run. You cannot use this code in proprietary or
non-FOSS software. See [NOTICE](NOTICE) for details and third-party components.
