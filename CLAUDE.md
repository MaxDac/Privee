# CLAUDE.md

Guidance for Claude Code in **Privee**: the Elixir/Phoenix server and
LiveView web client of an end-to-end encrypted chat (Signal Protocol via
libsignal). The Android client is
[MaxDac/PriveeApp](https://github.com/MaxDac/PriveeApp); the contract between
the two is in [docs/cross-repo.md](docs/cross-repo.md).

`AGENTS.md` holds the generic Phoenix/Elixir coding rules; follow them too.

## Layout

- `apps/privee`: domain (Ecto, `Privee.Sessions`, `Privee.PreKeyStore`,
  `Privee.Chats` in ETS, `Privee.Push`, `Privee.RateLimiter`).
- `apps/privee_web`: router, LiveViews, native app API (`PriveeWeb.App.*`),
  shared event logic (`PriveeWeb.ChatActions`, `PriveeWeb.SignalKeys`), assets
  in `apps/privee_web/assets` (vendored libsignal WASM).
- Details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Commands

Toolchain from `.tool-versions` (Erlang 29.1.1, Elixir 1.20.4, Node 24.21.0)
via mise or asdf. Postgres `postgres`/`postgres` on `localhost:5432`.

```bash
mix setup                      # deps, DB, esbuild/tailwind, npm install
mix phx.server                 # http://localhost:4000
mix precommit                  # what to run before finishing a change
```

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs exactly:

```bash
# MIX_ENV=test
mix deps.get
mix deps.unlock --check-unused
mix compile --warnings-as-errors
mix format --check-formatted
mix credo --strict
mix test --warnings-as-errors
# MIX_ENV=dev
mix dialyzer --format github
# in apps/privee_web/assets
npm ci && npm run check        # prettier --check, tsc, eslint, vitest
npm run e2e                    # Playwright, CI uses a MIX_ENV=prod build
# repo root
diff -r .claude/skills .github/skills
```

Single test: `mix test apps/privee_web/test/privee_web/app/channels_test.exs:42`.

### Windows / WSL

On the maintainer's Windows machine, run Elixir inside WSL; Postgres runs as a
Windows service on `localhost:5432`:

```bash
wsl -e bash -lc 'export PATH=$HOME/.local/share/mise/shims:$PATH; cd <repo>; mix test'
```

Serving the Android emulator (`http://10.0.2.2:4000`) is covered by the
`local-dev-stack` skill.

## Guardrails

- **Never weaken E2EE.** The server stores and relays only ciphertext and
  public key material. No plaintext, private keys or message content in
  Postgres, ETS, logs, telemetry or push payloads. Pushes stay a constant
  wake-up (`1`). Run the `security-change-review` skill for anything touching
  keys, messages, auth, push or CSP.
- **Backward-compatible API.** Released Android apps (F-Droid lags by weeks)
  must keep working. Additive changes only; `api_version` in
  `PriveeWeb.Instance` is bumped only following
  [docs/cross-repo.md](docs/cross-repo.md#api-versioning). Use the `api-change`
  skill.
- **Reversible migrations.** `change/0` with reversible operations, or `up`/
  `down`. Never edit a migration that is already on `main`.
- **Keep the AGPL source URL.** `PRIVEE_SOURCE_URL` / `source_url` in
  `/api/app/info` and the licence notices must stay.
- **Deploys** happen only from `MaxDac/Privee` `main` through
  [`main.yml`](.github/workflows/main.yml). Do not run `fly deploy` or change
  Fly secrets unless explicitly asked (`deploy` skill).
- Chat storage is node-local ETS: production runs a single machine; do not
  scale it out.
- Use `Req` for HTTP. No secrets in the repo.
- Conventional Commits (`feat:`, `fix:`, `docs:`, ...).

## Docs

| Doc | Content |
| --- | --- |
| [docs/TECHNOLOGIES.md](docs/TECHNOLOGIES.md) | Stack and versions |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Apps, contexts, routes, data model, where to change what |
| [docs/cross-repo.md](docs/cross-repo.md) | Server ↔ app contract, versioning, push, libsignal alignment, release order |
| [docs/client-api.md](docs/client-api.md) | Native API reference |
| [docs/e2e-encryption.md](docs/e2e-encryption.md) | Signal design, trade-offs, manual checklist |
| [docs/security/e2ee-audit.md](docs/security/e2ee-audit.md) | E2EE audit findings |
| [docs/self-hosting.md](docs/self-hosting.md) | Running an instance |

## Skills (`.claude/skills/`)

| Skill | Use it to |
| --- | --- |
| `api-change` | Change the native API end to end, with docs and an app follow-up |
| `local-dev-stack` | Run the server for the Android emulator |
| `deploy` | Deploy to Fly.io, verify, roll back |
| `libsignal-wasm-upgrade` | Upgrade libsignal in the web client, aligned with the app |
| `security-change-review` | Review a change against the E2EE design and audit |

The same skills live in `.github/skills/` for Copilot; edit both copies
identically (CI runs `diff -r`).

## Android app

PriveeApp has its own agent instructions, docs (`docs/ARCHITECTURE.md`,
`docs/TECHNOLOGIES.md`, `docs/RELEASING.md`, `docs/FDROID.md`) and skills
(`fdroid-release`, `libsignal-upgrade`). App releases and F-Droid publication
are handled there.
