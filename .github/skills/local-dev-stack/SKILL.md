---
name: local-dev-stack
description: Run the Privee server locally so the web client and the Android app (emulator at http://10.0.2.2:4000 or a device) can use it. Covers the toolchain (mise, WSL on Windows), PostgreSQL, PRIVEE_INSTANCE_NAME / PRIVEE_SOURCE_URL, mix setup, mix phx.server, reaching the server from the emulator, and local UnifiedPush. Use when asked to start, debug or reset the local server, or to test the Android app against a local backend.
---

# Local dev stack

## 1. Toolchain

Versions come from `.tool-versions` (Erlang 29.1.1, Elixir 1.20.4-otp-29,
Node.js 24.21.0). Install them with `mise install` (or `asdf install`).

On Windows, run Elixir inside WSL. mise shims are not on the PATH of a
non-interactive shell, so export them in every command:

```bash
wsl -e bash -lc 'export PATH=$HOME/.local/share/mise/shims:$PATH; cd /mnt/c/<path>/Privee && mix --version'
```

## 2. PostgreSQL

`config/dev.exs` and `config/test.exs` expect `postgres`/`postgres` on
`localhost:5432` (databases `privee_dev` and `privee_test`). Use either:

- an existing local server (on the maintainer's machine, a Windows service on
  `localhost:5432`, reachable from WSL), or
- a container:

  ```bash
  docker run --name privee-database -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres \
    --restart=unless-stopped -p 5432:5432 -d postgres:18
  ```

Check it with `pg_isready -h localhost -p 5432` or `mix ecto.create`.

## 3. Setup and run

```bash
mix setup          # deps, ecto.setup (create, migrate, seeds), esbuild/tailwind, npm install
export PRIVEE_INSTANCE_NAME="Local dev"                       # optional, shown by /api/app/info
export PRIVEE_SOURCE_URL="https://github.com/MaxDac/Privee"   # optional, this is the default
mix phx.server     # or: iex -S mix phx.server
```

`config/runtime.exs` reads `PRIVEE_INSTANCE_NAME` and `PRIVEE_SOURCE_URL` in
every environment (blank values count as unset). `PORT` (default `4000`) sets
the HTTP port.

Check:

```bash
curl -s http://localhost:4000/api/app/info
# {"api_version":1,"name":"Local dev","service":"privee","source_url":"...","version":"0.1.0"}
```

Reset the database with `mix ecto.reset`. Chat ciphertext lives in ETS and is
lost when the server stops; clients then start a new epoch.

## 4. Reach it from the Android emulator

- The emulator reaches the host loopback at `10.0.2.2`, so use
  `http://10.0.2.2:4000` as the server address. **Debug** builds of PriveeApp
  accept `http://` and suggest this URL; release builds require `https://`.
- Dev binds to `127.0.0.1` (`http: [ip: {127, 0, 0, 1}]` in
  `config/dev.exs`). With the server in WSL 2, Windows forwards
  `localhost:4000` into WSL, so the emulator on Windows reaches it through
  `10.0.2.2`. If it does not, first check
  `curl http://localhost:4000/api/app/info` from Windows.
- Dev sets `check_origin: false`, so `/app/socket` accepts the emulator's
  WebSocket.
- For a physical device, use `adb reverse tcp:4000 tcp:4000` and
  `http://localhost:4000` on the device, or temporarily bind dev to
  `{0, 0, 0, 0}` (do not commit it) and use the host's LAN IP.

## 5. Push notifications locally

`config/dev.exs` sets `config :privee, Privee.Push, allow_insecure: true`, so
`http` and local endpoints are accepted (production requires public `https`).
To test UnifiedPush end to end, run a local ntfy server and point the
distributor app on the emulator at it. The server sends `POST <endpoint>` with
body `1`; the app wakes up and fetches messages over its socket.

## 6. Useful dev routes

- `http://localhost:4000/` (register), `/login`, `/privee` (web client).
- `http://localhost:4000/dev/dashboard` (LiveDashboard).

## 7. Tests

```bash
mix test                                     # needs Postgres
mix test apps/privee_web/test/privee_web/app
cd apps/privee_web/assets && npm run check   # JS checks
cd apps/privee_web/assets && npm run e2e     # Playwright; E2E_BASE_URL reuses a running server
```
