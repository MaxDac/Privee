# End-to-end encryption (Signal Protocol)

Privee chats are end-to-end encrypted with the Signal Protocol (PQXDH key agreement
plus the Double Ratchet), implemented by Signal's official Rust
[libsignal](https://github.com/signalapp/libsignal) `v0.86.5`. The browser runs it
through [`libsignal-wasm`](https://github.com/MaxDac/libsignal-wasm), a
wasm-bindgen wrapper vendored in `assets/vendor/libsignal-wasm/` (JS glue) and
`priv/static/wasm/` (binary). The Android app uses `org.signal:libsignal-android`
at the same version, so both clients speak the same wire format. The server only
ever sees public keys and ciphertext.

## Components

### Server (`apps/privee`, `apps/privee_web`)

| Module | Role |
| --- | --- |
| `Privee.PreKeyStore` | Stores each session's public bundle (identity key, signed prekey, last-resort Kyber-1024 prekey, one-time prekeys) in `sessions.prekey_bundle`. Validates key sizes, keeps one-time prekey ids append-only and increasing, caps the pool at 100, and pops one-time prekeys under `SELECT ... FOR UPDATE`. |
| `PriveeWeb.SignalKeysLive` | `on_mount` hook of every authenticated LiveView: `signal_status`, `publish_identity`, `reset_identity`, `rotate_signed_prekey` and `add_prekeys` events, scoped to the current session. Pushes `replenish_prekeys` when the pool runs low and `identity_superseded` when another device resets the identity. The events are implemented in `PriveeWeb.SignalKeys`. |
| `PriveeWeb.ChatLive` | `open_conversation`, `request_peer_bundle` (rate-limited to 3 one-time prekey pops per 10 minutes per pair), `send_message` and `fetch_messages`, implemented in `PriveeWeb.ChatActions`. The sender, recipient and ids are always set by the server. |
| `Privee.Chats` | Plain functions over public ETS tables owned by `Privee.Chats.TableOwner`. Stores ciphertext only, deduplicates by client nonce, and groups messages in conversation **epochs**. |
| `Privee.RateLimiter` | Fixed-window ETS counters, shared across sockets. |

There is no HTTP API for keys: the former unauthenticated `POST /api/prekeys/:id`
route was removed.

### Native app API (`PriveeWeb.App`)

The Android app uses the same events, with the same reply payloads, over a
Phoenix channels socket instead of LiveView:

| Endpoint | Role |
| --- | --- |
| `POST /api/app/sessions` | Registers a session (`recovery_phrase`, or `is_quick: true`; the name is generated unless `session_name` is given) and logs in. |
| `POST /api/app/sessions/log_in` | `session_name` with `recovery_phrase`, or with `is_quick: true` for a quick session never logged into. Failures are a generic `401`. |
| `GET` / `DELETE /api/app/session` | The authenticated session; log out revokes the token and disconnects the app sockets. |
| `PUT` / `DELETE /api/app/push` | Registers / removes the app's UnifiedPush endpoint (see below). |
| `/app/socket` | WebSocket authenticated with the channels `auth_token`. Topic `session`: the `SignalKeys` events, plus `replenish_prekeys`, `identity_superseded` and content-free `message_received %{message_id, from_session_name}` pushes. Topic `chat:<peer session name>`: the `ChatActions` events, plus `new_message` (serialized ciphertext) and `peer_keys_ready` pushes. |

Log ins return `%{token, session: %{id, session_name, is_quick}}`, and chat
joins reply `%{peer_id, peer_session_name}`: like the web client, the app uses
the numeric session ids as Signal address names and safety number
identifiers. The token is the 60-day session token as
unpadded base64url, sent as `Authorization: Bearer <token>` and as the socket
`auth_token`. Registration and log in are rate-limited to 10 attempts per
minute per client address. Channel replies always have the `ok` status; failures
carry an `error` field, as with LiveView.

Background delivery uses [UnifiedPush](https://unifiedpush.org) (`Privee.Push`):
`PUT /api/app/push %{endpoint}` stores the app's distributor endpoint, bound to
its session token (log out removes it), and `DELETE /api/app/push` drops it.
Endpoints must be public `https` URLs (no `localhost` or literal IPs; `dev`
sets `allow_insecure` for a local ntfy). When a message is stored, each endpoint
of the recipient receives a constant body (`1`), at most once every 2 seconds,
so the push server never sees message metadata beyond timing; the app then
fetches the ciphertext over its socket. Endpoints answering `404`/`410` are
deleted.

### Client (`apps/privee_web/assets/js/utils`)

| Module | Role |
| --- | --- |
| `signal-wasm.mjs` | Loads the libsignal WASM module once, lazily, from `/wasm/libsignal_wasm_bg.wasm`. |
| `signal-db.mjs` | One IndexedDB database per Privee session and device: `privee-<session id>`. Version 2 (PQXDH) drops the X3DH keys and sessions but keeps history and outbox. |
| `signal-store.mjs` | Staged IndexedDB access: the serialized libsignal state, history and outbox are committed in a single transaction, so they never diverge. Trust on first use; a changed identity is refused until the user approves it. |
| `signal-locks.mjs` | Web Locks, used to coordinate tabs. Locking is fail-closed: browsers without the API cannot chat. |
| `signal-client.mjs` | Key management, session building, encrypt/decrypt, outbox, history and catch-up. Every protocol operation restores the libsignal state, runs under the exclusive keys lock, and saves it back. |
| `chat.mjs` | Chat screen controller: renders entries, composer, banners and menu actions. Plaintext only reaches the DOM through `textContent`. |
| `markdown.mjs` | Inline formatting (`**bold**`, `*italic*`, `~~strike~~`, `` `code` ``, http(s) links). Builds DOM nodes with `textContent`, never HTML; links open with `rel="noopener noreferrer nofollow"`. |
| `commands.mjs`, `vim.mjs` | `:` commands (`lock`, `unlock`, `export`, `safety`, `hint`, `clear`, `vim`) and the optional VIM mode of the composer. Commands run in the browser and are never sent. |

## Flows

- **Keys.** The first authenticated page (selector or chat) calls `ensureKeys`.
  It generates and publishes a bundle, rotates the signed prekey and the Kyber
  prekey (same id, signed by the identity key) weekly (a retired
  key is kept for the conversation lifetime plus a day after it stops being
  published), and tops up one-time
  prekeys. Private keys are persisted before their public halves are uploaded.
  Ids are never reused.
- **Sending.** `open_conversation` returns the current epoch. The client builds a
  session from `request_peer_bundle` if it has none for that epoch. It then
  encrypts, and commits the ratchet together with a `pending_outbox` row (keyed
  by a random client nonce) in one transaction, before calling `send_message`.
  Retries reuse the nonce, so the server stores the message once. If the epoch
  changed (`stale_epoch`), the message is re-encrypted under a fresh session with
  a new nonce.
- **Receiving.** Stream entries carry `id`, `seq`, `epoch`, `type` and `body`.
  They are decrypted in ascending `seq` order, and the plaintext is stored in the
  local history keyed by server id. On mount, `fetch_messages` catches up on
  messages older than the rendered window.
- **Identity changes.** A new peer identity blocks the conversation and shows its
  safety number until the user accepts it. The old session is then dropped and
  rebuilt. The "Safety number" button compares numbers at any time.
- **New device.** A browser without local keys for a session that already has a
  published bundle must *reset the encryption identity*. Devices still holding
  the old identity become **superseded** and stop sending. A reset also ends
  every server-side conversation of the session (and drops its ciphertext, which
  the new identity cannot decrypt), so peers start a new epoch and rebuild their
  sessions against the new bundle on their next message.

## Deliberate trade-offs

- **Local history.** Signal message keys are single-use, so ciphertext cannot be
  decrypted twice. Decrypted messages (and your own sent messages) are therefore
  kept in IndexedDB, as plaintext, on the device. They are never purged by age;
  use "Clear history on this device" or "Forget this device". Logging out keeps
  the keys and history, so logging back in on the same browser keeps working.
- **Local conversation hints.** A user can add a short hint (at most 40
  characters) about who is speaking in a conversation. The hint and the peer's
  session name are kept as plaintext in the peer's metadata in IndexedDB, and
  are never sent to the server or put in push payloads. The editor advises,
  every time, not to use the contact's name. "Clear history on this device"
  keeps hints; logging out and "Forget this device" remove them.
- **Chat commands are local.** The server never sees a `:` command, so it
  cannot act on it. `:lock <password>` replaces the rendered plaintext with the
  stored ciphertext and masks new messages; the password hash (salted SHA-256)
  is kept in memory only, and reloading the page unlocks. It hides the screen
  from onlookers, it does not encrypt the local history. Messages that arrive
  while locked are still decrypted (Signal keys are single-use) and saved to
  the local history. `:export` (and "Export CSV") downloads the local history
  as CSV, with cells starting with `= + - @` prefixed by `'` to defuse formulas.
- **Server retention.** Ciphertext lives in node-local ETS and is lost when the
  node restarts. A conversation expires as a whole after 24 hours of inactivity,
  7 days of age, or 1000 messages; the next message starts a new epoch. Older
  messages remain visible under "Earlier on this device".
- **Single node.** Chat storage is node-local, so the chat must run on a single
  node (PubSub is cluster-wide, storage is not).
- **One device at a time per session.** There is no multi-device fan-out:
  resetting the identity on a new device supersedes the previous one.

## Cutover from X3DH to PQXDH

- Migration `20261007000000_wipe_pre_kyber_prekey_bundles` clears every bundle
  without a Kyber prekey; `PreKeyStore` now requires one.
- The client's IndexedDB upgrade to version 2 drops the X3DH identity, sessions,
  prekeys and trust records, then republishes a new identity. History and the
  outbox are kept; pending messages are re-encrypted.
- Message types are libsignal's: `2` (whisper) and `3` (prekey). Type `1` is
  rejected.

## Cutover from the RSA / hand-rolled implementation

- Migration `20260601000000_wipe_legacy_prekey_bundles` clears every stored P-256
  bundle.
- The client deletes the legacy `SignalKeyStore` IndexedDB database.
- Old cached JavaScript hits catch-all event handlers that ask the user to reload.
- Existing sessions get new keys on their next visit. Peers see no identity-change
  warning, because nothing had been pinned before.

## Manual browser checklist

Run against `mix assets.deploy` output (minified, production CSP) before releasing.

1. [ ] **Two browsers.** Register A (browser 1) and B (browser 2). A opens a chat
   with B before B has ever visited the selector: the composer shows "Your contact
   has not set up encryption yet". B opens the selector; A sends; B sees the
   message live. Reply both ways several times.
2. [ ] **Offline recipient.** A sends three messages while B's chat is closed; B
   opens the chat and reads all three, in order.
3. [ ] **Reload.** Both reload: the conversation renders from local history, and
   new messages keep working both ways.
4. [ ] **Two tabs, one session.** Open B's chat in two tabs and send from both.
   Both tabs render every message; nothing shows "could not be decrypted".
5. [ ] **Session switching.** Log out of A and register C in the same browser.
   Chat C↔B, log back in as A: A's history and keys are intact (separate
   `privee-<id>` databases in DevTools → Application → IndexedDB).
6. [ ] **New device.** Log into B from a third browser: the chat asks to reset
   the encryption identity. Reset. The old B browser shows the "reset on another
   device" banner and cannot send. A sees the security-code-changed banner with a
   safety number, accepts, and the conversation continues with the new B.
7. [ ] **Safety number.** It matches on both sides, grouped in blocks of five.
8. [ ] **Clear / forget.** "Clear history on this device" removes the local
   history only (hints stay). "Forget this device" deletes the `privee-<id>`
   database and reloads. Add a hint from the chat's "Hint" button: the editor
   advises not to use the contact's name, the hint shows under the chat title
   and in "Conversations on this browser" on `/privee`, and no WS frame carries
   it. After logging out, the hint is gone.
9. [ ] **Notifications.** With the chat unfocused, an incoming message raises
   exactly one generic notification, even with several tabs open.
10. [ ] **No plaintext on the wire.** DevTools → Network → WS: `send_message`
    carries only `type`, `body` (base64), `client_nonce`, `epoch` and
    `identity_key`. No event carries the typed text.
11. [ ] **CSP.** No CSP violations in the console. WebAssembly compilation is
    allowed by `script-src 'unsafe-eval'`; the binary loads from `'self'`.
12. [ ] **Server restart.** Restart the server: the chat still shows the earlier
    messages from local history, and the next message starts a new session that
    the peer decrypts.
