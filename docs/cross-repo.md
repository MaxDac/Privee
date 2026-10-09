# Cross-repo contract (server ↔ Android app)

This page is the single source of truth for everything shared by
[MaxDac/Privee](https://github.com/MaxDac/Privee) (this server and its web
client) and [MaxDac/PriveeApp](https://github.com/MaxDac/PriveeApp) (the
Android client, app id `com.privee.app`). PriveeApp links here instead of
duplicating it. Read it before changing the native API, the push payload, the
Signal key handling or libsignal versions in either repository.

Detailed references:

- [Client API](client-api.md): every endpoint, event and payload of the native
  API. This page summarises it and adds the compatibility rules.
- [End-to-end encryption](e2e-encryption.md) and the
  [E2EE audit](security/e2ee-audit.md).
- PriveeApp: [architecture](https://github.com/MaxDac/PriveeApp/blob/main/docs/ARCHITECTURE.md),
  [technologies](https://github.com/MaxDac/PriveeApp/blob/main/docs/TECHNOLOGIES.md),
  [releasing](https://github.com/MaxDac/PriveeApp/blob/main/docs/RELEASING.md),
  [F-Droid](https://github.com/MaxDac/PriveeApp/blob/main/docs/FDROID.md).

## Surface used by the app

Any Privee instance serves the same API from its base URL
(`https://<PHX_HOST>`). Release builds of the app only accept `https://`;
debug builds also accept `http://` and suggest `http://10.0.2.2:4000` (a local
`mix phx.server` seen from the emulator).

| Kind | Path / topic | Server module |
| --- | --- | --- |
| Discovery | `GET /api/app/info` | `PriveeWeb.App.InfoController`, `PriveeWeb.Instance` |
| REST | `POST /api/app/sessions`, `POST /api/app/sessions/log_in` | `PriveeWeb.App.SessionController` |
| REST (Bearer) | `GET` / `DELETE /api/app/session` | `PriveeWeb.App.SessionController` |
| REST (Bearer) | `PUT` / `DELETE /api/app/push` | `PriveeWeb.App.PushController` |
| WebSocket | `/app/socket/websocket?vsn=2.0.0`, token in `Sec-WebSocket-Protocol` | `PriveeWeb.App.AppSocket` |
| Channel `session` | `signal_status`, `publish_identity`, `reset_identity`, `rotate_signed_prekey`, `add_prekeys`; pushes `replenish_prekeys`, `identity_superseded`, `message_received` | `PriveeWeb.App.SessionChannel` → `PriveeWeb.SignalKeys` |
| Channel `chat:<peer session name>` | `open_conversation`, `request_peer_bundle`, `send_message`, `fetch_messages`; pushes `new_message`, `peer_keys_ready` | `PriveeWeb.App.ChatChannel` → `PriveeWeb.ChatActions` |

Payloads, replies and error values: [Client API](client-api.md). Conventions
the app relies on:

- Channel replies always have status `ok`; failures carry an `error` field.
  Unknown events reply `{error: "unknown_event"}` on both channels, so a new
  event sent by a newer app to an older server fails softly.
- The token is the raw 32-byte session token as **unpadded base64url**, valid
  60 days, used both as `Authorization: Bearer` and as the socket
  `auth_token`. Logout revokes it and disconnects its sockets.
- The server deletes a session (with its tokens, push endpoint and prekey
  bundle) once no token has been issued for it for
  `PRIVEE_SESSION_RETENTION_DAYS` (default 90, never under 60); a never-used
  quick session goes after a day. Its name can then be registered again, so
  a later log in returns `401 invalid_credentials`. The app should treat that
  as "this session no longer exists" and register its UnifiedPush endpoint
  again after a new sign-in.
- Signal addresses and safety numbers use the numeric session ids (`session.id`,
  `peer_id`), not session names.
- Message `type` is libsignal's `CiphertextMessageType`: `2` (Whisper) or `3`
  (PreKey). `body` is base64 ciphertext, at most 16 KiB.
- Ciphertext is node-local and expires by conversation **epoch** (24 h idle,
  7 days, 1000 messages, or server restart). Clients bind Signal sessions to the
  epoch and must handle `stale_epoch` by rebuilding the session.
- Register and log in are rate-limited to 10 per minute per IP (`429
  {error: "rate_limited"}`); one-time prekey pops to 3 per 10 minutes per pair.

The web client uses the same `SignalKeys` and `ChatActions` events over the
LiveView socket, so a change there affects both clients.

## API versioning

`GET /api/app/info` returns:

```json
{"service": "privee", "api_version": 1, "version": "0.1.0", "name": null, "source_url": "https://github.com/MaxDac/Privee"}
```

- `api_version` is the `@api_version` attribute of
  [`PriveeWeb.Instance`](../apps/privee_web/lib/privee_web/instance.ex)
  (currently **1**). It is a single integer: a server advertises exactly one
  version.
- `version` is the `:privee_web` app version (`0.1.0`); informational only.
- The app accepts a server only if `service == "privee"` and `api_version` is
  in its `SUPPORTED_API_VERSIONS` set (`core/net/.../ServerInfo.kt` in
  PriveeApp, currently `setOf(1)`). Any other value is shown as "unsupported
  version", and the app refuses the server.

Compatibility rules (also in [Client API](client-api.md#versioning)):

1. **Additive changes keep `api_version`.** New endpoints, new events, new
   optional request fields and new response fields are allowed. Clients must
   ignore unknown fields and events; the server must treat new request fields
   as optional with the old behaviour as default.
2. **Breaking changes bump `api_version`.** Removing or renaming endpoints,
   events or fields, changing types or semantics, or making a field required.
3. Because the app rejects unknown versions, **bumping `api_version` locks out
   every installed app that does not list the new version.** Order for a
   breaking change:
   1. Prefer a non-breaking design (new event/field next to the old one).
   2. If unavoidable, first release an app that supports both versions
      (`setOf(1, 2)`) and speaks both protocols, and wait until it is live on
      F-Droid and most users have updated.
   3. Only then deploy the server with the bump. Keep the old behaviour
      available as long as feasible.

## Push notifications

- Transport: [UnifiedPush](https://unifiedpush.org). The app registers its
  distributor endpoint with `PUT /api/app/push {endpoint}`; it is bound to the
  session token (logout or `DELETE /api/app/push` removes it). No FCM, no
  Google services.
- Payload: `Privee.Push` sends `POST <endpoint>` with body `1`, headers
  `content-type: text/plain`, `ttl: 86400`, `urgency: high`. It is a
  **wake-up only**: no message id, sender, or ciphertext, and no Web Push
  encryption/VAPID.
- On wake-up the app connects to `/app/socket`, joins `session` and the
  relevant `chat:<peer>` channels, and fetches messages with
  `fetch_messages`. `message_received {message_id, from_session_name}` on the
  `session` channel tells a connected app which chat to fetch.
- At most one push per recipient every 2 s. Endpoints answering `404`/`410`
  are deleted, so the app should re-register its endpoint on start.
- Production requires public `https` endpoints (no IP literals, no
  `localhost`, DNS checked against private ranges). Dev (`config/dev.exs`)
  allows `http` and local hosts, e.g. a local ntfy.
- Keep the payload content-free. Adding data to it is a security change (see
  the `security-change-review` skill) and an API change.

## libsignal version alignment

Both clients must use the same libsignal release so they agree on the wire
format (PQXDH with Kyber-1024 prekeys, message types, serialisation).

| Where | Version | Pinned in |
| --- | --- | --- |
| Web client (this repo) | libsignal **v0.86.5** via `libsignal-wasm` 0.86.5 | [`vendor/libsignal-wasm/README.md`](../apps/privee_web/assets/vendor/libsignal-wasm/README.md), `WASM_VERSION` in [`signal-wasm.mjs`](../apps/privee_web/assets/js/utils/signal-wasm.mjs), binary in `apps/privee_web/priv/static/wasm/` |
| Android app | `org.signal:libsignal-android` **0.86.5** (built from source for F-Droid) | PriveeApp `gradle/libs.versions.toml` (`libsignal`), `libsignal/source.lock.json` |
| Server validation | Kyber-1024 public key 1569 bytes (0x08 prefix), Curve25519 keys 33 bytes, signatures 64 bytes | `Privee.PreKeyStore` |

Upgrade both together: see the `libsignal-wasm-upgrade` skill here and the
`libsignal-upgrade` skill in PriveeApp. A libsignal upgrade that changes the
wire format or key types is a breaking protocol change and needs the same
ordering as an `api_version` bump.

## Coordinated change order

F-Droid builds lag the app's GitHub release by days to weeks, and users update
when they like. The server is deployed manually through
[PriveeDeploy](https://github.com/MaxDac/PriveeDeploy), not on merge to `main`.
Therefore the
**server must keep supporting every released app version**.

1. **Server first, backward compatible.** Implement the change in Privee so
   that existing apps keep working (additive API, optional fields, old events
   kept). Update [client-api.md](client-api.md) and this page in the same PR.
2. **Deploy before the dependent app release.** Merging to `main` runs CI
   only. Follow `deploy-privee`: select the full source SHA with successful CI,
   get explicit user confirmation, then trigger PriveeDeploy's manual
   `deploy.yml` with `ref=<sha>`. Verify the deploy run, instance info
   (`GET https://bauta.fly.dev/api/app/info` upstream) and logs before shipping
   an app that requires the change.
3. **App change.** Open the follow-up in PriveeApp (issue or PR) that uses the
   new API, test it against a local server (`local-dev-stack` skill) and
   against production.
4. **App release.** Manual Release workflow in PriveeApp (reproducible, signed
   APK on GitHub Releases); see
   [RELEASING.md](https://github.com/MaxDac/PriveeApp/blob/main/docs/RELEASING.md).
5. **F-Droid.** F-Droid picks up the `v*` tag (`UpdateCheckMode: Tags`),
   rebuilds it, and publishes the upstream-signed APK when its build is
   byte-identical; see
   [FDROID.md](https://github.com/MaxDac/PriveeApp/blob/main/docs/FDROID.md)
   and the `fdroid-release` skill in PriveeApp.
6. **Cleanup (optional, much later).** Only remove server support for old
   behaviour after the replacing app version has been on F-Droid long enough,
   and treat the removal as a breaking change (rules above).

Never require the reverse order (app first, then server) unless the app keeps
working against the currently deployed server.

PriveeDeploy owns `fly.toml` and the deployment workflow; this repository owns
the source, `Dockerfile` and CI. Rollback is another confirmed deployment of an
explicitly chosen older full source SHA with successful CI, after checking
compatibility with the current database migrations; it does not undo migrations.

## App releases in short

- App id `com.privee.app`; versions in PriveeApp `version.properties`; tags
  `v<versionName>`.
- Releases are manual (GitHub Actions Release workflow), reproducible, and
  signed with the upstream key (certificate SHA-256
  `ea586e3f2deaf1ff3c507f8eae4ce3363c9f892d787da19d0003817ee58892f9`, pinned in
  F-Droid's `AllowedAPKSigningKeys`).
- F-Droid rebuilds from source (libsignal built from the pinned commit) and
  publishes the upstream-signed APK if identical, so users can switch between
  GitHub and F-Droid builds.
- Inclusion request:
  [fdroiddata MR !51681](https://gitlab.com/fdroid/fdroiddata/-/merge_requests/51681).
- Runbooks: PriveeApp
  [RELEASING.md](https://github.com/MaxDac/PriveeApp/blob/main/docs/RELEASING.md),
  [FDROID.md](https://github.com/MaxDac/PriveeApp/blob/main/docs/FDROID.md),
  skill `fdroid-release` (`.claude/skills/` and `.github/skills/`).

## Checklist for a cross-repo change

- [ ] Server change is backward compatible with the latest released app (and
      with the app currently on F-Droid).
- [ ] `api_version` unchanged, or the bump follows the order above.
- [ ] [client-api.md](client-api.md) and this page updated.
- [ ] Tests in `apps/privee_web/test/privee_web/app/` cover old and new
      behaviour.
- [ ] Follow-up issue opened in MaxDac/PriveeApp, linking the server PR.
- [ ] No plaintext, message metadata or private keys added to the server or
      to push payloads.
