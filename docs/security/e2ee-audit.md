# End-to-end encryption audit

Four frontier models independently reviewed the Signal end-to-end encryption
in Privee (web client and server) and PriveeApp (Android). Each one received
the same read-only prompt and the same three questions:

- **A.** Is every web chat message encrypted in the browser, with the official
  libsignal-wasm, before it reaches the server? Does plaintext reach the
  LiveView socket, logs, ETS or Postgres?
- **B.** Does the native API (`/api/app`, `/app/socket`, `/api/app/info`) carry
  only Signal ciphertext and public keys, with sound authentication, prekey
  consumption and identity reset?
- **C.** Does the Android app use libsignal (PQXDH with Kyber) for every
  message, store its keys safely and handle identity changes?

| Reviewer | A | B | C |
| --- | --- | --- | --- |
| Claude Opus 5.5 | Yes | Yes | Yes |
| GPT-6.1 Sol | Yes | Yes for content; credentials only over TLS | Yes |
| Grok 4.7 | Yes | Yes for content; no auth bypass | Yes |
| GPT-5.6 Sol | Yes, unless the server is malicious | Yes | Yes |

All four reviewers agree:

- Message bodies leave the client only as libsignal ciphertext (whisper type
  2 or PQXDH prekey type 3).
- The server, ETS, Postgres, logs and push notifications never see plaintext.
- Both clients require a Kyber prekey, so there is no downgrade to X3DH.

The table below lists every finding, which reviewers reported it, and its
status. The baseline ran on the merged native API with libsignal-wasm, before
the self-hosting changes.

| # | Severity | Finding | Reported by | Status |
| --- | --- | --- | --- | --- |
| 1 | High (inherent) | The server delivers the web client's JavaScript and WASM, so a malicious or compromised server could serve a client that leaks keys. | GPT-5.6 | Accepted. This is inherent to web E2EE. Use the Android app, or self-host a server you trust. |
| 2 | Medium | Trust on first use: the server is the only source of peer bundles, so it could substitute keys on first contact. Later identity changes are blocked until the user approves them. | GPT-5.6, Grok, Opus | Accepted and documented. Compare safety numbers out of band to detect this. |
| 3 | High / Low | Push SSRF: `PUT /api/app/push` accepted any public HTTPS host name, and the name could resolve to, or redirect to, internal addresses. Only the constant body `"1"` was sent, so this was a blind SSRF. | GPT-6.1, Grok, Opus | **Fixed.** Hosts are resolved and every address must be public right before delivery, and redirects are disabled. |
| 4 | Medium | The native chat channel kept a stale peer identity after another device reset it, so it accepted messages for the superseded identity. | GPT-6.1 | **Fixed.** The channel subscribes to identity resets and rejects the old identity. |
| 5 | Medium | The login rate limit used the proxy's address behind Caddy or Fly.io, so one client could lock everyone out. | Opus | **Fixed.** The `ForwardedRemoteIp` plug reads trusted `X-Forwarded-For` entries, configured with `PROXY_HOPS`. |
| 6 | Medium | Replay after an epoch change: clients drop the session when a PreKey message carries a new server epoch. Android does not track reuse of the last-resort Kyber prekey (`markKyberPreKeyUsed` is a no-op). A malicious server could therefore make an old message be accepted again. Content is not disclosed. | Opus | Android: forwarded to the PriveeApp PR. Web: depends on libsignal-wasm's Kyber store. Open. |
| 7 | Low | The CSP allows `'unsafe-inline'` and `'unsafe-eval'`. | Opus | Open hardening item: move to nonces and `'wasm-unsafe-eval'`. |
| 8 | Low | The web client keeps keys, sessions and history unencrypted in IndexedDB. Android encrypts them with a Keystore key. | Grok | Accepted trade-off. Protect the browser profile, or use the app. |

## Self-hosting and server selection

Clients choose their server explicitly. `GET /api/app/info` identifies a
Privee server (`service`, `api_version`). The Android app requires HTTPS in
release builds. It keeps keys, sessions and the account separately for each
server URL, so changing server never reuses identities across deployments.
See [client-api.md](../client-api.md) and
[self-hosting.md](../self-hosting.md).

## Recommendations for users

- Compare safety numbers with your contacts, which removes risk 2.
- Use a server you, or someone you trust, operate. It sees metadata (who talks
  to whom and when), but never message content.
- Keep the server behind HTTPS and set `PROXY_HOPS` correctly.
