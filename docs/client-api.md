# Client API

This is the API that native clients, such as the
[Privee Android app](https://github.com/MaxDac/PriveeApp), use to talk to a
Privee server. Every instance exposes the same API, so a client only needs the
server's base URL (`https://<PHX_HOST>`) to work with any self-hosted deployment
(see [Self-hosting](self-hosting.md)).

All payload encryption happens on the client with the Signal Protocol (PQXDH +
Double Ratchet, libsignal). The server only stores and relays public keys and
opaque ciphertext. See [End-to-end encryption](e2e-encryption.md).

## Discovery: `GET /api/app/info`

Unauthenticated. Clients call it when the user enters a server address, to
check that the address is a compatible Privee instance before they store it.

```json
{
  "service": "privee",
  "api_version": 1,
  "version": "0.1.0",
  "name": "My Privee",
  "source_url": "https://github.com/MaxDac/Privee"
}
```

| Field | Meaning |
| --- | --- |
| `service` | Always `"privee"`. Clients must reject any other value. |
| `api_version` | Integer version of this API. Bumped only on breaking changes; clients must reject versions they do not support. |
| `version` | Server release version, informational. |
| `name` | Display name set with `PRIVEE_INSTANCE_NAME`, or `null`. |
| `source_url` | Where to get the source code of the running version (AGPL-3.0, section 13). |

The response is sent with `cache-control: no-store`.

Clients should require `https://` URLs. Plain `http://` is only meant for local
development.

## REST: `/api/app`

JSON requests and responses. Authenticated endpoints need the
`Authorization: Bearer <token>` header, with the token returned by register or
log in.

| Method and path | Auth | Body | Response |
| --- | --- | --- | --- |
| `POST /api/app/sessions` | - | `session_name` (optional, generated when missing), `recovery_phrase` or `is_quick: true` | `201 {token, session}` or `422 {error: "invalid", errors}` |
| `POST /api/app/sessions/log_in` | - | `session_name` with `recovery_phrase`, or with `is_quick: true` | `200 {token, session}` or `401 {error: "invalid_credentials"}` |
| `GET /api/app/session` | Bearer | - | `{session}` |
| `DELETE /api/app/session` | Bearer | - | `204`; revokes the token and disconnects its sockets |
| `PUT /api/app/push` | Bearer | `endpoint` (UnifiedPush URL) | `204` or `422 {error: "invalid_endpoint"}` |
| `DELETE /api/app/push` | Bearer | - | `204` |

`session` is `{id, session_name, is_quick}`. Register and log in are
rate-limited per IP and return `429 {error: "rate_limited"}` when the limit is
exceeded. Push notifications carry no message content.

Sessions with no token issued for `PRIVEE_SESSION_RETENTION_DAYS` (default 90)
are deleted by the server, together with their push endpoint and prekey
bundle; log in then answers `401 {error: "invalid_credentials"}`.

Clients may send `Accept-Language` on every REST request, including registration
and login. Supported languages are `en`, `it`, `pt-PT` (European Portuguese),
`es` and `fr`. Base and regional variants match the supported base language
(for example `pt` and `pt-BR` select the European Portuguese catalog).
Quality weights are respected; absent or unsupported headers default to English.
The browser's language cookie is not consulted for native API requests.

Only human-readable validation arrays in `errors[field]` are localized, including
interpolated limits. The API version remains **1**; HTTP statuses, envelope/field
names and top-level machine `error` strings (such as `invalid`,
`invalid_credentials` and `rate_limited`) are unchanged. Socket payloads are
unchanged. Clients should translate machine codes locally. Previously received
validation text may be cleared on language changes while retaining entered values;
the next validation request returns errors in the newly selected language.

## Socket: `/app/socket`

A [Phoenix Channels](https://hexdocs.pm/phoenix/channels.html) WebSocket
(`wss://<host>/app/socket/websocket?vsn=2.0.0`). The token is sent through
Phoenix's `auth_token`, in the `Sec-WebSocket-Protocol` header:
`base64url.bearer.phx.<unpadded base64url of the token>`. Connections with a
missing or revoked token are refused.

Replies always have the `ok` status. Failures carry an `error` field.

### Channel `session`

Key management for the authenticated session.

| Event | Payload | Reply |
| --- | --- | --- |
| `signal_status` | - | `{identity_key, opk_count, max_opk_id, max_age_ms}` |
| `publish_identity` | full bundle (below) | `{ok: true}` |
| `reset_identity` | full bundle | `{ok: true}`; ends existing conversations, other devices receive `identity_superseded` |
| `rotate_signed_prekey` | `{identity_key, signed_prekey, kyber_prekey}` | `{ok: true}` |
| `add_prekeys` | `{identity_key, one_time_prekeys}` | `{ok: true}` |

The full bundle contains only public keys (base64):

```json
{
  "identity_key": "<33-byte Curve25519 key>",
  "registration_id": 1234,
  "signed_prekey": {"key_id": 1, "public_key": "...", "signature": "..."},
  "kyber_prekey": {"key_id": 1, "public_key": "...", "signature": "..."},
  "one_time_prekeys": [{"key_id": 1, "public_key": "..."}]
}
```

Server pushes:

- `replenish_prekeys` (`{}`): the one-time prekey pool is running low.
- `identity_superseded` (`{identity_key}`): another device published a new identity.
- `message_received` (`{message_id, from_session_name}`): fetch the message through `chat:<from_session_name>`.

### Channel `chat:<peer session name>`

A conversation with the peer. Joining replies `{peer_id, peer_session_name}`,
or fails with `{reason: "not_found"}`.

| Event | Payload | Reply |
| --- | --- | --- |
| `open_conversation` | - | `{epoch}` |
| `request_peer_bundle` | - | `{peer_id, bundle}` (consumes one of the peer's one-time prekeys) or `{peer_id, error: "not_found"}` |
| `send_message` | `{type, body, client_nonce, epoch, identity_key}` | `{id, seq, epoch, client_nonce}` or `{error}` (`superseded`, `stale_epoch` with `epoch`, `invalid`, ...) |
| `fetch_messages` | `{epoch, after_seq}` | `{messages, next_cursor}` |

`type` is the libsignal ciphertext type (`2` = Whisper, `3` = PreKey) and `body`
is the base64 ciphertext. Messages are `{id, seq, epoch, type, body, direction,
client_nonce}`, where `direction` is `in` or `out`.

Server pushes:

- `new_message`: a message of this conversation.
- `peer_keys_ready` (`{}`): the peer published new keys.

## Versioning

New fields and events may be added without changing `api_version`. Clients must
ignore fields they do not know. Removing or changing existing fields or events
increments `api_version`.
