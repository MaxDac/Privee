# Technologies

The full stack of the Privee server and web client. Versions are the ones
pinned in the repository; the source of truth for each is listed in the last
column, so update this page when you bump them.

The Android client has its own breakdown in
[PriveeApp `docs/TECHNOLOGIES.md`](https://github.com/MaxDac/PriveeApp/blob/main/docs/TECHNOLOGIES.md).
How the two fit together is described in [Cross-repo contract](cross-repo.md).

## Languages and runtimes

| Component | Version | Notes | Source of truth |
| --- | --- | --- | --- |
| Erlang/OTP | 29.1.1 | BEAM runtime | [`.tool-versions`](../.tool-versions), `OTP_VERSION` in [`Dockerfile`](../Dockerfile) |
| Elixir | 1.20.4 (OTP 29 build) | `elixir: "~> 1.20"` in both apps | [`.tool-versions`](../.tool-versions), `ELIXIR_VERSION` in [`Dockerfile`](../Dockerfile) |
| Node.js | 24.21.0 | Asset tooling and tests only; not used at runtime. The Docker builder installs Node 24 for the daisyUI npm package | [`.tool-versions`](../.tool-versions), `NODE_MAJOR` in [`Dockerfile`](../Dockerfile) |
| JavaScript | ES2022 modules (`.mjs`) | Checked by TypeScript (`tsc`, JSDoc types), no TS sources | [`config/config.exs`](../config/config.exs) (`--target=es2022`), [`assets/tsconfig.json`](../apps/privee_web/assets/tsconfig.json) |

Install the toolchain with `mise install` (or `asdf install`). CI reads the
same `.tool-versions` file (`erlef/setup-beam` with `version-type: strict`,
`actions/setup-node`).

## Server (Elixir)

The project is a Mix umbrella: `apps/privee` (domain) and `apps/privee_web`
(web). See [Architecture](ARCHITECTURE.md).

| Area | Technology | Version (mix.lock) | Notes |
| --- | --- | --- | --- |
| Web framework | Phoenix | 1.8.15 | Router, controllers, channels |
| Server UI | Phoenix LiveView | 1.2.12 | Registration, login, selector and chat screens |
| HTML | phoenix_html | 4.3.0 | HEEx templates |
| HTTP server | Bandit | 1.12.5 | `Bandit.PhoenixAdapter` |
| Real time | Phoenix Channels + Phoenix.PubSub | phoenix_pubsub 2.3.0 | LiveView socket `/live`, native app socket `/app/socket` |
| Database layer | Ecto SQL | ecto 3.14.2, ecto_sql 3.14.0 | Single repo `Privee.Repo` |
| Database driver | Postgrex | 0.22.4 | PostgreSQL (CI and docs use `postgres:18`) |
| Password hashing | bcrypt_elixir | 3.3.2 | Hashes recovery phrases |
| HTTP client | Req | 0.7.5 | Push delivery (`Privee.Push`); use Req, not httpoison/tesla/httpc |
| JSON | Jason | 1.4.5 | |
| Clustering | dns_cluster | 0.3.1 | Optional (`DNS_CLUSTER_QUERY`); chat storage is node-local, so production runs a single machine |
| Mail | Swoosh | 1.28.1 | Local adapter only; no mail is sent in production |
| i18n | Gettext | 1.0.2 | |
| Telemetry | telemetry_metrics, telemetry_poller, phoenix_live_dashboard | 1.2.0, 1.3.0, 0.9.1 | Dashboard only under `/dev` in development |
| In-memory storage | ETS | OTP | Ciphertext (`Privee.Chats`), rate-limit counters (`Privee.RateLimiter`) |

### Authentication and sessions

- There are no user accounts, e-mails or passwords. A **session** is a
  randomly generated name plus a **recovery phrase** (bcrypt-hashed), or a
  **quick session** without a phrase that can be logged into only once
  (`Privee.Sessions.session_valid?/1`).
- Login creates a 32-byte random token stored in `sessions_tokens`
  (context `"session"`), valid for 60 days
  (`Privee.Sessions.SessionToken`).
- Web: the token lives in the signed Phoenix session cookie plus an optional
  signed remember-me cookie (`PriveeWeb.SessionAuth`).
- Native app: the same token, unpadded base64url, sent as
  `Authorization: Bearer <token>` and as the Phoenix channels `auth_token` of
  `/app/socket` (`PriveeWeb.App.AppAuth`). Logout deletes the token and
  disconnects its sockets.

### Encryption

- Signal Protocol (PQXDH with Kyber-1024 + Double Ratchet) from Signal's
  official [libsignal](https://github.com/signalapp/libsignal) **v0.86.5**.
- The server never encrypts or decrypts. It stores public key bundles
  (`sessions.prekey_bundle`, validated by `Privee.PreKeyStore`) and relays
  opaque ciphertext. Details: [End-to-end encryption](e2e-encryption.md).

### Push notifications

- [UnifiedPush](https://unifiedpush.org) endpoints registered by the app
  (`PUT /api/app/push`), stored in `push_endpoints`.
- Delivery is a plain HTTP `POST` with `Req` (`Privee.Push`): constant body
  `1`, headers `content-type: text/plain`, `ttl: 86400`, `urgency: high`. It is
  a **wake-up only**: no message content, sender or id. The app then fetches
  the ciphertext over its socket.
- No Web Push encryption (RFC 8291), no VAPID, no FCM/Google services.
- At most one push per recipient every 2 seconds; endpoints answering `404` or
  `410` are deleted. Endpoints must be public `https` URLs, and the host is
  resolved and checked against private ranges before each delivery (SSRF
  protection). `config/dev.exs` sets `allow_insecure: true` for a local ntfy.
- The web client uses browser notifications raised by the open page
  (`assets/js/utils/push-notifications.mjs`, `notification-coordinator.mjs`);
  there is no server-side Web Push.

### Rate limiting

`Privee.RateLimiter`: fixed-window counters in a public ETS table, swept every
minute by `Privee.Chats.TableOwner`.

| Key | Limit | Where |
| --- | --- | --- |
| `{:app_auth, ip}` | 10 per minute per client IP | `PriveeWeb.App.SessionController` (register, log in) |
| `{:opk_pop, me, peer}` | 3 one-time prekey pops per 10 minutes per pair | `PriveeWeb.ChatActions.request_peer_bundle/2` |
| `{:push, session_id}` | 1 push per 2 seconds per recipient | `Privee.Push.notify/1` |

The client IP comes from `X-Forwarded-For`, counting `PROXY_HOPS` from the
right (`PriveeWeb.Plugs.ForwardedRemoteIp`; `2` on Fly.io).

### Security headers

`PriveeWeb.Plugs.SecurityHeaders` sets CSP, HSTS, COOP, `nosniff`,
`X-Frame-Options` and `Referrer-Policy`. The CSP allows `'unsafe-eval'` in
`script-src` for WebAssembly compilation. Production forces HTTPS
(`config/prod.exs`).

## Web client (browser)

| Area | Technology | Version | Source of truth |
| --- | --- | --- | --- |
| Signal Protocol | `libsignal-wasm` (wasm-bindgen build of libsignal v0.86.5, `@maxdac/libsignal-wasm` 0.86.5), vendored | 0.86.5 | [`vendor/libsignal-wasm/README.md`](../apps/privee_web/assets/vendor/libsignal-wasm/README.md), `WASM_VERSION` in [`signal-wasm.mjs`](../apps/privee_web/assets/js/utils/signal-wasm.mjs) |
| WASM binary | `priv/static/wasm/libsignal_wasm_bg.wasm`, fetched lazily as `/wasm/libsignal_wasm_bg.wasm?v=<WASM_VERSION>` | | |
| Local storage | IndexedDB (one `privee-<session id>` database per session), Web Locks | | [`signal-db.mjs`](../apps/privee_web/assets/js/utils/signal-db.mjs), [`signal-locks.mjs`](../apps/privee_web/assets/js/utils/signal-locks.mjs) |
| Bundler | esbuild (Mix `esbuild` 0.10.0) | 0.28.2 | [`config/config.exs`](../config/config.exs) |
| CSS | Tailwind CSS (Mix `tailwind` 0.5.1) | 4.3.3 | [`config/config.exs`](../config/config.exs) |
| UI components | daisyUI | 5.7.47 | [`package.json`](../apps/privee_web/assets/package.json) |
| LiveView glue | `phoenix`, `phoenix_html`, `phoenix_live_view` JS from `deps/` | as above | `NODE_PATH` in [`config/config.exs`](../config/config.exs) |

## Tooling and tests

| Tool | Version | Used for |
| --- | --- | --- |
| ExUnit | Elixir | `mix test` (needs PostgreSQL) |
| Credo | 1.7.19 | `mix credo --strict` |
| Dialyxir | 1.4.8 | `mix dialyzer` (PLTs in `priv/plts`) |
| `mix format` | Elixir | Elixir and HEEx formatting (`phoenix_live_view` formatter plugin) |
| Prettier | 3.9.9 | Formats `apps/privee_web/assets` only (not the Markdown docs) |
| TypeScript | 6.0.3 | `tsc` type-checks the JS through JSDoc |
| ESLint | 10.12.0 | JS lint |
| Vitest | 5.0.3 | JS unit tests, with jsdom 30.1.2 and fake-indexeddb 6.2.5; real libsignal WASM in `signal-client.test.mjs` |
| Playwright | 1.63.0 | Browser end-to-end specs in `assets/e2e` (Chromium) |

`mix precommit` runs the Elixir checks plus `npm run check` (prettier, tsc,
eslint, vitest). See [CLAUDE.md](../CLAUDE.md) for the exact commands.

## CI/CD and hosting

| Area | Technology | Notes |
| --- | --- | --- |
| CI | GitHub Actions ([`ci.yml`](../.github/workflows/ci.yml)) | On pull requests, pushes to `main` and manual dispatch: Elixir (deps, unused deps, compile with warnings as errors, format, credo, tests with `postgres:18`), Dialyzer, assets (`npm run check`), Playwright E2E against a `MIX_ENV=prod` build, Docker build, and the skills sync check. No deployment |
| Deployment | PriveeDeploy GitHub Actions ([`deploy.yml`](https://github.com/MaxDac/PriveeDeploy/blob/main/.github/workflows/deploy.yml)) | Manual dispatch only; checks out the chosen Privee ref and builds its Dockerfile on Fly's remote builders. Uses `production`, `FLY_API_TOKEN` and `--ha=false`. Agents require successful source CI for the full SHA and explicit user confirmation (`deploy-privee`) |
| Container | [`Dockerfile`](../Dockerfile) | Multi-stage release (`hexpm/elixir` builder, `debian:trixie` runner), release `privee_umbrella` |
| Hosting | [Fly.io](https://fly.io) (PriveeDeploy [`fly.toml`](https://github.com/MaxDac/PriveeDeploy/blob/main/fly.toml)) | Upstream app `bauta` at `bauta.fly.dev`; instance-agnostic config in PriveeDeploy, app/host supplied by repository variables. Region `ams`, one shared-CPU machine with 1 GB, internal port 8080, auto stop/start, `release_command = '/app/bin/migrate'` |
| Database (prod) | PostgreSQL via `DATABASE_URL` | Optional SSL (`ENABLE_DB_SSL=true`) and IPv6 (`ECTO_IPV6`) |

Self-hosting on other platforms: [Self-hosting](self-hosting.md).

## Licence

AGPL-3.0-only ([LICENSE](../LICENSE), [NOTICE](../NOTICE)). Every instance
advertises the source of the running version through `PRIVEE_SOURCE_URL`
(`source_url` in `GET /api/app/info`).
