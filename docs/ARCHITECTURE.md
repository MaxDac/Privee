# Architecture

Privee is a Phoenix umbrella with two OTP applications. The server relays
end-to-end encrypted chats between two kinds of client: the LiveView web client
served by this repository, and the
[Privee Android app](https://github.com/MaxDac/PriveeApp) (see its
[architecture](https://github.com/MaxDac/PriveeApp/blob/main/docs/ARCHITECTURE.md)).
Both clients encrypt with libsignal; the server only sees public keys and
ciphertext ([End-to-end encryption](e2e-encryption.md)).

Related pages: [Technologies](TECHNOLOGIES.md), [Client API](client-api.md),
[Cross-repo contract](cross-repo.md), [Self-hosting](self-hosting.md).

```text
 Browser (LiveView + libsignal-wasm)        Android app (libsignal-android)
        |  /live socket, HTTP                  |  /api/app (REST), /app/socket (channels)
        v                                      v
 +------------------------- apps/privee_web --------------------------+
 | Router, LiveViews, controllers, PriveeWeb.App.* (native API),     |
 | ChatActions / SignalKeys (shared by LiveView and app channels),   |
 | Events (PubSub topics), Instance (/api/app/info)                  |
 +---------------------------------+---------------------------------+
                                   |
 +---------------------------- apps/privee ---------------------------+
 | Sessions (Ecto), PreKeyStore (Ecto), Chats (ETS), Push (Req),      |
 | RateLimiter (ETS), SessionNameProvider                             |
 +-----------+----------------------------------+---------------------+
             | Postgres                         | HTTPS POST "1"
             v                                  v
     sessions, sessions_tokens,          UnifiedPush distributor
     push_endpoints                      (e.g. ntfy) -> app wake-up
```

## Umbrella apps

| App | Path | Responsibility |
| --- | --- | --- |
| `:privee` | [`apps/privee`](../apps/privee) | Domain logic, Ecto schemas, `Privee.Repo`, ETS storage, push delivery. No Phoenix web dependencies. |
| `:privee_web` | [`apps/privee_web`](../apps/privee_web) | Endpoint, router, LiveViews, controllers, channels, assets (JS, CSS, vendored libsignal WASM). Depends on `:privee`. |

Both share `config/`, `deps/`, `_build/` and `mix.lock` at the umbrella root.
The release is `privee_umbrella` ([`mix.exs`](../mix.exs)).

### Supervision

- `Privee.Application`: `Privee.Repo`, `DNSCluster`, `Phoenix.PubSub`
  (`Privee.PubSub`), `Privee.Chats.TableOwner` (owns the ETS tables and sweeps
  them every minute), `Task.Supervisor` (`Privee.TaskSupervisor`, async push
  deliveries). Runs migrations at boot only if `TRIGGER_STARTUP_MIGRATION=true`
  (PriveeDeploy's `fly.toml` runs `/app/bin/migrate` as the Fly release command
  instead).
- `PriveeWeb.Application`: `PriveeWeb.Telemetry`, `PriveeWeb.Endpoint`.

## Domain contexts (`apps/privee/lib/privee`)

| Module | Storage | Responsibility |
| --- | --- | --- |
| `Privee.Sessions` | Postgres `sessions`, `sessions_tokens` | Register/log in by session name + recovery phrase (bcrypt) or quick session; session tokens (60 days); generate available session names. Changesets for the chat form (`PriveeForm`) and messages. |
| `Privee.Sessions.Session` | `sessions` | `session_name` (24–72 chars, unique), `hashed_recovery_phrase` (nullable for quick sessions), `is_quick`, `has_logged`, `prekey_bundle` (jsonb). |
| `Privee.Sessions.SessionToken` | `sessions_tokens` | 32-byte random tokens, context `"session"`. |
| `Privee.Sessions.Message` | embedded, never persisted | Ciphertext envelope: `type` (2 or 3), `body` (base64, ≤ 16 KiB), `client_nonce`; every other field is set by the server. |
| `Privee.PreKeyStore` | `sessions.prekey_bundle` | Public Signal bundle: identity key, signed prekey, Kyber-1024 last-resort prekey, ≤ 100 one-time prekeys with append-only increasing ids. Every write validates key sizes inside a row-locked transaction. |
| `Privee.Chats` | ETS (`:chat_messages`, `:chat_conversations`, `:chat_nonces`) | Node-local ciphertext store grouped by conversation and **epoch**; dedup by client nonce; expiry after 24 h idle, 7 days or 1000 messages. Lost on restart, not shared across nodes. |
| `Privee.Push` | `push_endpoints` | UnifiedPush endpoint registration (bound to a session token) and content-free wake-up delivery with SSRF checks. |
| `Privee.Sessions.Janitor` | - | GenServer, every 6 hours: deletes expired session tokens and sessions without a sign-in for `PRIVEE_SESSION_RETENTION_DAYS` (cascading tokens, push endpoints and the prekey bundle). |
| `Privee.RateLimiter` | ETS `:rate_limits` | Fixed-window counters (auth, prekey pops, pushes). |
| `Privee.SessionNameProvider` | - | Behaviour + `Impl` (real names) and a mock used in tests (`config :privee, :session_name_provider`). |

## Web layer (`apps/privee_web/lib/privee_web`)

### Endpoint sockets

| Path | Module | Clients |
| --- | --- | --- |
| `/live` | `Phoenix.LiveView.Socket` | Web client (cookie session) |
| `/app/socket` | `PriveeWeb.App.AppSocket` (WebSocket only, `auth_token: true`) | Android app |

### Router scopes ([`router.ex`](../apps/privee_web/lib/privee_web/router.ex))

| Scope / pipeline | Routes |
| --- | --- |
| `/dev` (dev only) | LiveDashboard `/dev/dashboard`, Swoosh mailbox `/dev/mailbox` |
| `:browser` + `redirect_if_session_is_authenticated` | `live "/"` (`SessionRegistrationLive`), `live "/login"` (`SessionLoginLive`), `post "/sessions/log_in"` |
| `:browser` + `require_authenticated_session` | `live "/privee"` (`PriveeSelectorLive`), `live "/chat/:session"` (`Chat.ChatLive`); every LiveView here mounts `PriveeWeb.SignalKeysLive` and `PriveeWeb.NotificationsLive` (in-app notification for messages from other chats) |
| `:browser` (`live_session :public`) | `live "/guide"` (`GuideLive`), readable with or without a session |
| `:browser` | `get "/share/:session_name"` (`SessionShareController`), `delete "/sessions/log_out"` |
| `/api/app` + `:api` | `GET /info`, `POST /sessions`, `POST /sessions/log_in` |
| `/api/app` + `:api`, `:app_session` | `GET`/`DELETE /session`, `PUT`/`DELETE /push` |

The native API is documented in [Client API](client-api.md).

### Shared event logic

The web client and the app speak the **same events with the same payloads**:

- `PriveeWeb.SignalKeys`: key management events (`signal_status`,
  `publish_identity`, `reset_identity`, `rotate_signed_prekey`,
  `add_prekeys`). Used by `PriveeWeb.SignalKeysLive` (LiveView `on_mount`) and
  `PriveeWeb.App.SessionChannel`.
- `PriveeWeb.ChatActions`: chat events (`open_conversation`,
  `request_peer_bundle`, `send_message`, `fetch_messages`). Used by
  `PriveeWeb.Chat.ChatLive` and `PriveeWeb.App.ChatChannel`.
- `PriveeWeb.Events`: PubSub topics (`chat:<id>:<id>`, `receiver:<id>`) and
  broadcasts; `broadcast_new_message/1` also calls `Privee.Push.notify/1`.

Changing a payload in these modules changes **both** clients' contract.

### Native app modules (`PriveeWeb.App`)

| Module | Role |
| --- | --- |
| `AppAuth` | Bearer token (unpadded base64url of the session token); `require_app_session` plug; socket id per token, so logout disconnects sockets. |
| `InfoController` | `GET /api/app/info` from `PriveeWeb.Instance`, `cache-control: no-store`. |
| `SessionController` | Register, log in (rate-limited per IP), show, log out. |
| `PushController` | Register/remove the UnifiedPush endpoint. |
| `AppSocket`, `SessionChannel`, `ChatChannel` | Channels `session` and `chat:<peer session name>`. |

### Other web modules

- `PriveeWeb.SessionAuth`: cookie login, remember-me cookie, `on_mount` hooks.
- `PriveeWeb.Plugs.ForwardedRemoteIp` (`PROXY_HOPS`) and
  `PriveeWeb.Plugs.SecurityHeaders` (CSP, HSTS, ...).
- `PriveeWeb.Navigation`: menu state per `live_session`.
- Assets in [`apps/privee_web/assets`](../apps/privee_web/assets): `js/utils/signal-*.mjs`
  (libsignal client, IndexedDB store, locks, WASM loader), `chat.mjs` (with
  `markdown.mjs`, `commands.mjs` for local `:` commands and `vim.mjs`), LiveView
  hooks in `js/hooks`, vendored WASM glue in `vendor/libsignal-wasm`.
- Local conversation hints: `peer-hints.mjs` (stored in the `meta` store of
  `privee-<session id>`, key `peer:<id>`), `hint-editor.mjs` and
  `conversation-list.mjs` (the "Conversations on this browser" list on
  `/privee`). Hints never reach the server; `sign-out.mjs` clears them when
  the user logs out.

## Data model

| Table | Columns (main) | Notes |
| --- | --- | --- |
| `sessions` | `session_name` (unique), `hashed_recovery_phrase` (nullable), `is_quick`, `has_logged`, `prekey_bundle` (jsonb), timestamps | No personal data. |
| `sessions_tokens` | `session_id` → `sessions` (cascade), `token` (binary), `context`, `sent_to` | Unique `(context, token)`. |
| `push_endpoints` | `session_id` → `sessions`, `session_token_id` → `sessions_tokens` (both cascade), `endpoint` (text) | Unique per token and per endpoint; deleting a token (logout) removes the endpoint. |

Messages are **not** in Postgres: they live in ETS (`Privee.Chats`). Migrations
are in [`apps/privee/priv/repo/migrations`](../apps/privee/priv/repo/migrations).

## Instance metadata and AGPL source URL

`PriveeWeb.Instance` ([`instance.ex`](../apps/privee_web/lib/privee_web/instance.ex))
describes the deployment:

- `api_version` - module attribute `@api_version` (currently `1`), the version
  of the native API (`/api/app`, `/app/socket`). See
  [Cross-repo contract](cross-repo.md#api-versioning).
- `version` - `:privee_web` application version (`0.1.0` in `mix.exs`).
- `name` - `PRIVEE_INSTANCE_NAME` (blank → `null`).
- `source_url` - `PRIVEE_SOURCE_URL`, default `https://github.com/MaxDac/Privee`.
  AGPL-3.0 section 13 requires offering the running source to network users:
  forks must point it to their own repository. Never remove it.

Both variables are read in [`config/runtime.exs`](../config/runtime.exs) in
every environment.

## Where to change what

| I want to... | Change | Also update |
| --- | --- | --- |
| Add or change a native API endpoint | `router.ex`, `PriveeWeb.App.*Controller`, tests in `test/privee_web/app` | [client-api.md](client-api.md), [cross-repo.md](cross-repo.md); follow the `api-change` skill |
| Add or change a channel event | `PriveeWeb.ChatActions` / `PriveeWeb.SignalKeys` (shared) and the channel/LiveView | Web client JS (`signal-client.mjs`, hooks), [client-api.md](client-api.md), `channels_test.exs` |
| Change key validation or prekey handling | `Privee.PreKeyStore` | [e2e-encryption.md](e2e-encryption.md); follow `security-change-review` |
| Change message retention or epochs | `Privee.Chats` (`config :privee, Privee.Chats`) | [e2e-encryption.md](e2e-encryption.md#deliberate-trade-offs) |
| Change push delivery | `Privee.Push` | [cross-repo.md](cross-repo.md#push-notifications) (payload must stay content-free) |
| Change rate limits | Module attributes in `SessionController`, `ChatActions`, `Privee.Push` | [TECHNOLOGIES.md](TECHNOLOGIES.md#rate-limiting) |
| Change instance info / `api_version` | `PriveeWeb.Instance` | [client-api.md](client-api.md), [cross-repo.md](cross-repo.md#api-versioning) |
| Add a database column/table | New migration in `apps/privee/priv/repo/migrations` (reversible), schema in `apps/privee/lib` | This page (data model) |
| Upgrade libsignal in the web client | `vendor/libsignal-wasm`, `priv/static/wasm`, `WASM_VERSION` | Follow the `libsignal-wasm-upgrade` skill |
| Change a web screen | `apps/privee_web/lib/privee_web/live/**` and `.heex` templates | Playwright specs in `assets/e2e` |
| Change runtime configuration | `config/runtime.exs` | [README](../README.md#cicd), [self-hosting.md](self-hosting.md) |
| Change the release image | `Dockerfile` in this repository | [TECHNOLOGIES.md](TECHNOLOGIES.md#cicd-and-hosting), [self-hosting.md](self-hosting.md) |
| Change Fly deployment | [`fly.toml`](https://github.com/MaxDac/PriveeDeploy/blob/main/fly.toml), [`deploy.yml`](https://github.com/MaxDac/PriveeDeploy/blob/main/.github/workflows/deploy.yml) in PriveeDeploy, not here | Follow the `deploy-privee` skill (successful CI for the full source SHA, explicit user confirmation) |
