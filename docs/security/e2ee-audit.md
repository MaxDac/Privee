# End-to-end encryption audit

Frontier models independently reviewed the Signal end-to-end encryption in
Privee (web client and server) and PriveeApp (Android), in two rounds:

- **Baseline:** Claude Opus 5.5, GPT-6.1 Sol, Grok 4.7 and GPT-5.6 Sol, run on
  the merged native API with libsignal-wasm, before the self-hosting changes.
- **Final:** the same four models plus GPT-6 Astra, run on the finished code of
  both repositories, including the configurable server in the app.

Each reviewer received the same read-only prompt and these questions:

- **A.** Is every web chat message encrypted in the browser, with the official
  libsignal-wasm, before it reaches the server? Does plaintext reach the
  LiveView socket, logs, ETS or Postgres?
- **B.** Does the native API (`/api/app`, `/app/socket`, `/api/app/info`) carry
  only Signal ciphertext and public keys, with sound authentication, prekey
  consumption and identity reset?
- **C.** Does the Android app use libsignal (PQXDH with Kyber) for every
  message, store its keys safely and handle identity changes?
- **D.** (final round) Does the app's server selection validate the server,
  enforce HTTPS, and keep keys, sessions, accounts and links bound to one
  server?

Baseline verdicts:

| Reviewer | A | B | C |
| --- | --- | --- | --- |
| Claude Opus 5.5 | Yes | Yes | Yes |
| GPT-6.1 Sol | Yes | Yes for content; credentials only over TLS | Yes |
| Grok 4.7 | Yes | Yes for content; no auth bypass | Yes |
| GPT-5.6 Sol | Yes, unless the server is malicious | Yes | Yes |

Final verdicts, before the fixes listed below:

| Reviewer | A | B | C | D |
| --- | --- | --- | --- | --- |
| Claude Opus 5.5 | Pass | Pass | Pass | Pass (low findings 11, 12) |
| GPT-6.1 Sol | Pass | Partial (13) | Pass | Partial (10) |
| Grok 4.7 | Pass | Partial (14) | Pass | Pass |
| GPT-5.6 Sol | Pass | Partial (9) | Pass | Partial (10) |
| GPT-6 Astra | Pass | Partial (rate limits, 16) | Partial (interop not executed) | Partial (15) |

All reviewers agree:

- Message bodies leave the client only as libsignal ciphertext (whisper type
  2 or PQXDH prekey type 3).
- The server, ETS, Postgres, logs and push notifications never see plaintext.
- Both clients require a Kyber prekey, so there is no downgrade to X3DH.

The table below lists every finding, which reviewers reported it, and its
status. Findings 1–8 come from the baseline, 9–16 from the final round.

| # | Severity | Finding | Reported by | Status |
| --- | --- | --- | --- | --- |
| 1 | High (inherent) | The server delivers the web client's JavaScript and WASM, so a malicious or compromised server could serve a client that leaks keys. | GPT-5.6 | Accepted. This is inherent to web E2EE. Use the Android app, or self-host a server you trust. |
| 2 | Medium | Trust on first use: the server is the only source of peer bundles, so it could substitute keys on first contact. Later identity changes are blocked until the user approves them. | GPT-5.6, Grok, Opus | Accepted and documented. Compare safety numbers out of band to detect this. |
| 3 | High / Low | Push SSRF: `PUT /api/app/push` accepted any public HTTPS host name, and the name could resolve to, or redirect to, internal addresses. Only the constant body `"1"` was sent, so this was a blind SSRF. | GPT-6.1, Grok, Opus | **Fixed.** Hosts are resolved and every address must be public right before delivery, and redirects are disabled. |
| 4 | Medium | The native chat channel kept a stale peer identity after another device reset it, so it accepted messages for the superseded identity. | GPT-6.1 | **Fixed.** The channel subscribes to identity resets and rejects the old identity. |
| 5 | Medium | The login rate limit used Fly's proxy address, so one client could lock everyone out. | Opus | **Fixed.** The `ForwardedRemoteIp` plug reads trusted `X-Forwarded-For` entries, configured with `PROXY_HOPS` (corrected to `2` on Fly, see 14). |
| 6 | Medium | Replay after an epoch change: clients drop the session when a PreKey message carries a new server epoch. Android did not track reuse of the last-resort Kyber prekey (`markKyberPreKeyUsed` was a no-op). A malicious server could therefore make an old message be accepted again. Content is not disclosed. | Opus | **Fixed.** Android records Kyber/signed-prekey/base-key uses and rejects replays (PriveeApp#12). The web libsignal-wasm store already rejects reused base keys. |
| 7 | Low | The CSP allows `'unsafe-inline'` and `'unsafe-eval'`. | Opus | Open hardening item: move to nonces and `'wasm-unsafe-eval'`. |
| 8 | Low | The web client keeps keys, sessions and history unencrypted in IndexedDB. Android encrypts them with a Keystore key. | Grok | Accepted trade-off. Protect the browser profile, or use the app. |
| 9 | Medium | Identity-reset race: a send could be accepted under a superseded identity before the reset broadcast reached the channel. | GPT-5.6 | **Fixed.** `send_message` reads the current identity from the store on every send. |
| 10 | Medium | `privee://share/<name>` carried no server, and a pending invite survived a server change, so a chat could open with a same-named user on another deployment. | GPT-5.6, GPT-6.1, Opus, Grok (low) | **Fixed** in PriveeApp#13. Links carry the server; a mismatched or legacy link needs confirmation naming both hosts; changing server clears pending invites. |
| 11 | Low | The app showed the server-supplied name instead of its host, and server validation followed redirects. | Opus | **Fixed** in PriveeApp#13. The host is always shown; validation does not follow redirects. |
| 12 | Low | Share links were not bound to the server (same root cause as 10). | Opus | **Fixed** with 10. |
| 13 | Medium / Low | Push DNS rebinding: the destination was checked, then resolved again when connecting. | GPT-6.1, Opus, Grok | **Fixed.** Delivery connects to the checked address and keeps the host name for SNI, certificate checks and `Host`. |
| 14 | Medium | On Fly the rightmost `X-Forwarded-For` entry is the app's own IP, so `PROXY_HOPS=1` still put all clients in one rate-limit bucket. | Grok | **Fixed.** [PriveeDeploy's `fly.toml`](https://github.com/MaxDac/PriveeDeploy/blob/main/fly.toml) sets `PROXY_HOPS=2`, verified against Fly's documentation. |
| 15 | Medium | The app's authenticated client followed redirects, so a redirect from the selected server could send the session token (WebSocket) or the recovery phrase (307 login) to another host. | Astra | **Fixed** in PriveeApp#13. API, socket and server-validation requests never follow redirects; tests show a redirect target receives no request. |
| 16 | Info | Message sends and key-management events have no per-event rate limit (login, prekey consumption and pushes do). | Astra | Accepted. Abuse is limited to authenticated accounts; a future hardening item. |

## Self-hosting and server selection

Clients choose their server explicitly. `GET /api/app/info` identifies a
Privee server (`service`, `api_version`). The Android app requires HTTPS in
release builds. It keeps keys, sessions and the account separately for each
server URL, so changing server never reuses identities across deployments.
Invite links carry their server, and the app does not follow redirects from
the selected server. Web↔Android interoperability was reviewed in code but not
executed by the reviewers.
See [client-api.md](../client-api.md) and
[self-hosting.md](../self-hosting.md).

## Device threats

Threat model: malicious or over-privileged apps on the same phone as the
Android app, without root. A rooted or compromised OS is out of scope; no app
can defend against it.

**Server: no change.** The app keeps its session token AES-GCM encrypted under
a non-exportable Android Keystore key, so stealing the token already requires
root. Binding the token to a device key would add little there, because root
can use the key on the device. An account taken over with a stolen recovery
phrase is already visible to the owner as `identity_superseded`. Token binding
and login alerts are deferred unless a concrete incident calls for them.

**App mitigations (PriveeApp):**

- `FLAG_SECURE` in every build: no screenshots, screen recordings, casting or
  recents thumbnails. Store screenshots are rendered on the JVM instead.
- Other apps' overlays are hidden on Android 12+; touches through overlays are
  filtered on older versions (tapjacking).
- On Android 14+, the UI is marked accessibility-data-sensitive, so only real
  accessibility tools can read it.
- Text fields ask the keyboard not to learn from input
  (`IME_FLAG_NO_PERSONALIZED_LEARNING`).
- Notifications say only "New message": no sender in the text, on the lock
  screen or in the tag that notification listeners can read.

**Rejected:** StrongBox and `setUnlockedDeviceRequired` for the storage key
(StrongBox is slow for frequent Signal-state writes and the key is already
non-exportable; requiring an unlocked device breaks fetching messages in the
background while the phone is locked), root detection and Play Integrity
(easy to bypass, and they break F-Droid and de-Googled users), clipboard flags
(the app never writes to the clipboard), and a biometric app lock (it defends
against physical access, not hostile apps; it would be a separate feature).

## Recommendations for users

- Compare safety numbers with your contacts, which removes risk 2.
- Use a server you, or someone you trust, operate. It sees metadata (who talks
  to whom and when), but never message content.
- Keep the server behind HTTPS and set `PROXY_HOPS` correctly.
