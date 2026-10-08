# Copilot instructions for Privee

Privee is the server and web client of an end-to-end encrypted chat. It is an
Elixir/Phoenix umbrella: `apps/privee` (domain: Ecto, ETS chat storage, push,
rate limiting) and `apps/privee_web` (router, LiveViews, the native app API
under `PriveeWeb.App`, assets with a vendored libsignal WASM build). The
Android client lives in [MaxDac/PriveeApp](https://github.com/MaxDac/PriveeApp)
and talks to this server through the API in `docs/client-api.md`.

Also follow the Phoenix/Elixir rules in `AGENTS.md`.

## Build, test and lint

Use the versions in `.tool-versions` (Erlang 29.1.1, Elixir 1.20.4, Node
24.21.0). Tests need PostgreSQL with `postgres`/`postgres` on
`localhost:5432`.

- Setup: `mix setup`. Run: `mix phx.server` (port 4000).
- Before you finish: `mix precommit`.
- The CI checks (`.github/workflows/ci.yml`), which must all pass:
  - `mix deps.unlock --check-unused`
  - `mix compile --warnings-as-errors`
  - `mix format --check-formatted`
  - `mix credo --strict`
  - `mix test --warnings-as-errors` (`MIX_ENV=test`)
  - `mix dialyzer --format github` (`MIX_ENV=dev`)
  - in `apps/privee_web/assets`: `npm ci` then `npm run check` (prettier,
    tsc, eslint, vitest) and `npm run e2e` (Playwright)
  - `diff -r .claude/skills .github/skills`
- Prettier only covers `apps/privee_web/assets`; Markdown docs are not
  formatted by CI.
- On Windows, run mix inside WSL with mise on the PATH:
  `export PATH=$HOME/.local/share/mise/shims:$PATH`. Postgres may run on the
  Windows side at `localhost:5432`.

## Rules for every change

- **End-to-end encryption is not negotiable.** The server handles only
  ciphertext and public keys. Never log, store or forward plaintext, private
  keys or message content, and keep push payloads a constant wake-up body.
  For changes to keys, messages, auth, push or security headers, apply the
  `security-change-review` skill.
- **Released Android apps must keep working.** F-Droid builds lag by days to
  weeks. Make API changes additive. Do not bump `@api_version` in
  `PriveeWeb.Instance` unless you follow the order in `docs/cross-repo.md`.
  Update `docs/client-api.md` and `docs/cross-repo.md` with any API change, and
  open a follow-up issue in MaxDac/PriveeApp (`api-change` skill).
- **Migrations must be reversible**, and existing migrations on `main` must
  not be edited.
- **Keep the AGPL source link**: `PRIVEE_SOURCE_URL` and `source_url` in
  `GET /api/app/info` stay.
- **Do not deploy without confirmation.** Privee runs CI only; merging to
  `main` does not deploy. [PriveeDeploy](https://github.com/MaxDac/PriveeDeploy)
  owns `fly.toml` and the manual `deploy.yml` workflow. Follow `deploy-privee`:
  verify successful CI for the full source SHA and get explicit user
  confirmation before triggering it. Do not run `fly deploy` here.
- Chat messages are stored in node-local ETS, so production is one machine.
- Use `Req` for HTTP requests. Never commit secrets.
- Write Conventional Commit messages.

## Where to look

- `docs/ARCHITECTURE.md`: contexts, routes, data model, and a "where to change
  what" table.
- `docs/TECHNOLOGIES.md`: the stack with versions.
- `docs/cross-repo.md`: the server ↔ Android contract (API versioning, push,
  libsignal versions, coordinated releases and F-Droid).
- `docs/client-api.md`, `docs/e2e-encryption.md`,
  `docs/security/e2ee-audit.md`, `docs/self-hosting.md`.

## Skills

Skills live in `.github/skills/<name>/SKILL.md`, with identical copies in
`.claude/skills/` for Claude Code. When you change one, change both.

- `api-change`: native API changes end to end.
- `local-dev-stack`: run the server for the Android emulator
  (`http://10.0.2.2:4000`).
- `deploy-privee`: confirmed, CI-checked deployment through PriveeDeploy,
  verification and rollback.
- `libsignal-wasm-upgrade`: upgrade libsignal in the web client in step with
  the app.
- `security-change-review`: E2EE review checklist.

App releases and F-Droid publication are handled in PriveeApp (its
`docs/RELEASING.md`, `docs/FDROID.md` and `fdroid-release` skill).
