---
name: api-change
description: Change the Privee native app API (/api/app REST endpoints, /app/socket channel events or payloads, GET /api/app/info) end to end without breaking released Android apps. Covers server code and tests, the api_version rules, updating docs/client-api.md and docs/cross-repo.md, and opening the follow-up issue in MaxDac/PriveeApp. Use when adding, changing or removing an endpoint, event, field or reply that the Android app uses, or when asked to bump api_version.
---

# Native API change

The Android app (MaxDac/PriveeApp, `com.privee.app`) and the web client share
the server API. Installed apps, especially F-Droid builds that lag by weeks,
must keep working after every deploy. Read `docs/cross-repo.md` first; the
rules there win over this summary.

## 1. Classify the change

| Change | Kind | `api_version` |
| --- | --- | --- |
| New endpoint, new channel event, new server push | additive | keep |
| New optional request field (old behaviour when absent) | additive | keep |
| New response/reply field | additive | keep (clients ignore unknown fields) |
| Remove/rename endpoint, event, field; change a type or meaning; make a field required; change auth or token format | breaking | bump |

Prefer an additive design: add a new event or field next to the old one and
keep the old one working. Unknown events already reply
`{error: "unknown_event"}`, so a newer app can probe an older server.

If the change is breaking, stop and confirm with the user. The app accepts
only the versions in `SUPPORTED_API_VERSIONS`
(`core/net/src/main/kotlin/com/privee/net/ServerInfo.kt` in PriveeApp,
currently `setOf(1)`), so bumping `@api_version` in `PriveeWeb.Instance` locks
out every installed app. The required order is: app supporting both versions
released and live on F-Droid, then the server bump.

## 2. Implement on the server

Where things live (see `docs/ARCHITECTURE.md`, "Where to change what"):

- Routes: `apps/privee_web/lib/privee_web/router.ex` (`/api/app` scopes; the
  `:app_session` pipeline requires the Bearer token).
- Controllers: `apps/privee_web/lib/privee_web/app/*_controller.ex`.
- Channels: `PriveeWeb.App.SessionChannel` (`session`) and
  `PriveeWeb.App.ChatChannel` (`chat:<peer session name>`).
- Shared logic: `PriveeWeb.SignalKeys` and `PriveeWeb.ChatActions` are also
  used by the LiveView web client. A payload change there changes the web
  client too: update `apps/privee_web/assets/js/utils/signal-client.mjs` and
  the hooks, with their vitest tests.
- Domain: `apps/privee/lib/privee/**`. Migrations must be reversible.

Conventions to keep: channel replies are always `{:ok, map}`, with failures as
an `error` string field; HTTP errors are `{error: "<code>"}` JSON; tokens are
unpadded base64url; ids come from the server and are never trusted from the
client.

Never add plaintext, private keys or message metadata to server storage, logs
or push payloads. If the change touches keys, messages, auth or push, also run
the `security-change-review` skill.

## 3. Test

- Add tests under `apps/privee_web/test/privee_web/app/`
  (`channels_test.exs`, `session_controller_test.exs`,
  `push_controller_test.exs`, `info_controller_test.exs`) for the new
  behaviour **and** for the old behaviour that released apps rely on.
- Run `mix precommit` (or the CI commands listed in `CLAUDE.md`). On Windows
  run them in WSL with `export PATH=$HOME/.local/share/mise/shims:$PATH`.
- If shared events changed, also run `npm run check` and `npm run e2e` in
  `apps/privee_web/assets`.

## 4. Update the docs in the same PR

- `docs/client-api.md`: endpoint and event tables, payloads, errors.
- `docs/cross-repo.md`: the surface table, conventions, and the versioning
  section if `api_version` semantics changed.
- `docs/e2e-encryption.md` if the encryption flow or its native API section is
  affected; `docs/ARCHITECTURE.md` if routes or modules changed.
- If you bump `@api_version`: update the JSON examples in `client-api.md` and
  `cross-repo.md`, and `info_controller_test.exs`.

## 5. Ship and follow up in the app

1. Open the PR with a Conventional Commit title (`feat(api): ...`). State in
   the body whether the change is additive or breaking and how old apps
   behave.
2. After merge, `main.yml` deploys to Fly.io (see the `deploy` skill). Verify
   with `curl -s https://bauta.fly.dev/api/app/info`.
3. Open the app follow-up issue:

   ```bash
   gh issue create -R MaxDac/PriveeApp \
     --title "Use <new API> from the server" \
     --body "Server change: <PR URL>. Contract: https://github.com/MaxDac/Privee/blob/main/docs/client-api.md. Compatibility: <additive / breaking, api_version N>. App work: <what the app must do>."
   ```

4. The app change ships through PriveeApp's Release workflow and F-Droid
   (`fdroid-release` skill there). Do not remove server support for the old
   behaviour until the new app version has been on F-Droid for a while, and
   treat that removal as a breaking change.
