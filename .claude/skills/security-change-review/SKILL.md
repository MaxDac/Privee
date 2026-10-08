---
name: security-change-review
description: Review a Privee server or web-client change against the end-to-end encryption design (docs/e2e-encryption.md) and the E2EE audit (docs/security/e2ee-audit.md). A checklist for anything touching Signal keys, messages, authentication and tokens, channels, push notifications, rate limits, logging, CSP/security headers, migrations on sessions or prekey bundles, or the vendored libsignal WASM. Use before opening or approving such a PR, or when asked for a security review of a change.
---

# Security change review

Privee's promise: the server only ever sees **public key material and opaque
ciphertext**. Read `docs/e2e-encryption.md` (design, flows, trade-offs) and
`docs/security/e2ee-audit.md` (findings and fixes) before reviewing. Report
each item below as pass, fail or not applicable, with file and line for
failures.

## 1. Scope the change

```bash
git diff --stat origin/main...HEAD
git diff origin/main...HEAD -- apps/privee/lib apps/privee_web/lib apps/privee_web/assets/js config apps/privee/priv/repo/migrations
```

High-risk areas: `Privee.PreKeyStore`, `Privee.Chats`,
`Privee.Sessions.Message`, `Privee.Sessions` / `SessionToken`, `Privee.Push`,
`Privee.RateLimiter`, `PriveeWeb.ChatActions`, `PriveeWeb.SignalKeys`,
`PriveeWeb.App.*`, `PriveeWeb.SessionAuth`, `PriveeWeb.Plugs.*`,
`assets/js/utils/signal-*.mjs`, `chat.mjs`, `vendor/libsignal-wasm`.

## 2. Plaintext and secrets never reach the server

- [ ] Nothing sends message plaintext to the server: `send_message` carries
      only `type`, `body` (base64 ciphertext), `client_nonce`, `epoch`,
      `identity_key`.
- [ ] No private keys, ratchet state or plaintext history leaves the browser
      (IndexedDB only) or the app.
- [ ] No new logging, telemetry, `inspect/1` or error reports of message
      bodies, tokens, recovery phrases, push endpoints or prekey bundles.
      Sensitive schema fields stay `redact: true`.
- [ ] Ciphertext stays in ETS (`Privee.Chats`), not in Postgres; retention
      limits (24 h idle, 7 days, 1000 messages) are not extended without a
      documented reason.

## 3. Keys and Signal protocol

- [ ] `Privee.PreKeyStore` still validates every key (Curve25519 33 bytes,
      Kyber-1024 1569 bytes with `0x08` prefix, signatures 64 bytes), keeps
      one-time prekey ids unique, positive and strictly increasing, caps the
      pool at 100, and runs each write in one row-locked transaction.
- [ ] One-time prekeys are popped atomically and rate-limited (3 per 10
      minutes per requester/peer pair).
- [ ] Only the owner (authenticated session) can publish, reset or rotate its
      keys. `reset_identity` still ends conversations and supersedes other
      devices; superseded identities cannot send.
- [ ] Server-set fields (`id`, `seq`, `epoch`, `from`, `to`,
      `sender_session_name`) are never taken from the client.
- [ ] Message `type` stays `2` or `3`; body size limit (16 KiB) kept.
- [ ] The web client still uses libsignal-wasm for every operation (no
      hand-rolled crypto, no `crypto.subtle` replacement of protocol steps),
      trust on first use with explicit approval of identity changes, and
      plaintext rendered only via `textContent`.
- [ ] Web and Android stay on the same libsignal version
      (`docs/cross-repo.md`).

## 4. Authentication and authorisation

- [ ] Tokens are random (32 bytes), stored server-side, expire (60 days) and
      are revoked on logout, which also disconnects sockets.
- [ ] New `/api/app` routes that touch session data go through
      `:app_session`; new LiveViews that need a session are in the
      `require_authenticated_session` `live_session`.
- [ ] Channel joins check that the peer exists and scope every action to
      `socket.assigns.current_session`.
- [ ] Recovery phrases are bcrypt-hashed; login failures stay generic
      (`401 invalid_credentials`) with constant-time checks
      (`Bcrypt.no_user_verify/0`).
- [ ] Register/log in remain rate-limited per client IP; `PROXY_HOPS`
      semantics unchanged (spoofable if set too high).

## 5. Push notifications

- [ ] The push body stays the constant `1`: no message id, sender, session
      name or ciphertext.
- [ ] Endpoint validation unchanged: public `https`, no IP literals or
      `localhost`, DNS resolved and checked against private ranges right
      before delivery, connection pinned to the checked address,
      `redirect: false`. `allow_insecure` only in dev.
- [ ] At most one push per recipient per 2 s; `404`/`410` endpoints deleted.

## 6. Web security

- [ ] `PriveeWeb.Plugs.SecurityHeaders` (CSP, HSTS, COOP, nosniff, frame
      options, referrer policy) not weakened; no new external origins or
      extra `'unsafe-*'` sources (the existing `'unsafe-inline'` /
      `'unsafe-eval'` in `script-src` are known limitations, not precedent).
- [ ] `force_ssl` in production kept; `check_origin` only disabled in dev.
- [ ] No user-controlled HTML (`raw/1`, `innerHTML`) rendering.

## 7. Data and operations

- [ ] Migrations are reversible and do not copy keys or tokens to new
      places. Wiping bundles (as in `20261007000000_wipe_pre_kyber_prekey_bundles`)
      is documented in `docs/e2e-encryption.md`.
- [ ] The AGPL `source_url` is still served by `/api/app/info`.
- [ ] No secrets in code, config or docs.

## 8. Tests and evidence

- [ ] Tests cover the new behaviour and the rejection paths (invalid keys,
      wrong owner, rate limits, invalid endpoints).
- [ ] `mix test`, `npm run check` and, for client or protocol changes,
      `npm run e2e` (asserts no plaintext over the WebSocket) pass.
- [ ] For protocol-level changes, run the "Manual browser checklist" in
      `docs/e2e-encryption.md` and test against the Android app
      (`local-dev-stack` skill).

## 9. Report

Summarise: scope, items that fail (with fix suggestions), items not
applicable, and whether `docs/e2e-encryption.md`,
`docs/security/e2ee-audit.md`, `docs/client-api.md` or `docs/cross-repo.md`
need updates. If the change affects the app (keys, payloads, push), say which
PriveeApp follow-up is needed.
