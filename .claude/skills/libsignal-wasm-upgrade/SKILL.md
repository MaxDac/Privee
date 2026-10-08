---
name: libsignal-wasm-upgrade
description: Upgrade the libsignal WebAssembly build used by the Privee web client (vendored libsignal-wasm in apps/privee_web/assets/vendor/libsignal-wasm and priv/static/wasm), keeping it on the same libsignal release as the Android app (org.signal:libsignal-android in MaxDac/PriveeApp). Mirror of PriveeApp's libsignal-upgrade skill. Use when asked to bump libsignal, update libsignal-wasm, or check that web and Android libsignal versions match.
---

# libsignal WASM upgrade (web client)

The web client and the Android app must run the **same libsignal release** so
they agree on the wire format (PQXDH with Kyber-1024, message types,
serialisation). Current pin: libsignal **v0.86.5** on both sides. See
`docs/cross-repo.md#libsignal-version-alignment`.

| Side | Where the version is pinned |
| --- | --- |
| Web (this repo) | `apps/privee_web/assets/vendor/libsignal-wasm/README.md`, `WASM_VERSION` in `apps/privee_web/assets/js/utils/signal-wasm.mjs`, binary `apps/privee_web/priv/static/wasm/libsignal_wasm_bg.wasm` |
| Docs (this repo) | `docs/e2e-encryption.md` (first paragraph), `docs/TECHNOLOGIES.md`, `docs/cross-repo.md` |
| Android (PriveeApp) | `gradle/libs.versions.toml` (`libsignal = "..."`), `libsignal/source.lock.json` (source build for F-Droid); skill `libsignal-upgrade` |

## 1. Decide the target version

- Pick a tag of [signalapp/libsignal](https://github.com/signalapp/libsignal)
  that is also published as `org.signal:libsignal-android`, so the app can
  move to the same version.
- Read the libsignal release notes between the current and target tags for
  protocol changes (new message versions, key types, removed APIs). A change
  that makes old and new clients unable to talk is a **breaking protocol
  change**: it needs the coordinated order in `docs/cross-repo.md` (both
  clients able to handle it before anything relies on it).
- Coordinate with the app: either open the PriveeApp upgrade first or right
  after, and do not leave the two on different versions in released builds.

## 2. Build or download libsignal-wasm

The JS glue and binary come from
[`MaxDac/libsignal-wasm`](https://github.com/MaxDac/libsignal-wasm)
(`@maxdac/libsignal-wasm`), a wasm-bindgen (`--target web`) wrapper of the
libsignal protocol crate. Either build it at the target tag
(`scripts/build.sh` in that repository) or download its release tarball for
the target version. You need `pkg/libsignal_wasm.js`,
`pkg/libsignal_wasm.d.ts` and `pkg/libsignal_wasm_bg.wasm`.

If the repository or release is not reachable, stop and ask the user; do not
fetch an unofficial build.

## 3. Vendor it

```bash
cp pkg/libsignal_wasm.js pkg/libsignal_wasm.d.ts apps/privee_web/assets/vendor/libsignal-wasm/
cp pkg/libsignal_wasm_bg.wasm apps/privee_web/priv/static/wasm/
```

Then:

- Bump `WASM_VERSION` in `apps/privee_web/assets/js/utils/signal-wasm.mjs`.
  It is the cache-busting query (`/wasm/libsignal_wasm_bg.wasm?v=...`), so
  browsers never pair the new glue with a cached old binary.
- Update the tag and package version in
  `apps/privee_web/assets/vendor/libsignal-wasm/README.md`.
- Update the version in `docs/e2e-encryption.md`, `docs/TECHNOLOGIES.md` and
  `docs/cross-repo.md`.
- If the exported API changed (`SignalStore`, `preKeyMessageIdentity`, ...),
  adapt `signal-wasm.mjs`, `signal-client.mjs` and `signal-store.mjs`.
  `libsignal_wasm.d.ts` drives the `tsc` check.
- If key sizes or message types changed, update the validation in
  `Privee.PreKeyStore` (Curve25519 33 bytes, Kyber-1024 1569 bytes with
  `0x08` prefix, 64-byte signatures) and `Privee.Sessions.Message` (types
  `2`, `3`), and run the `security-change-review` skill.
- `vendor/libsignal-wasm/` is excluded from prettier (`.prettierignore`); do
  not reformat it.

## 4. Test

```bash
cd apps/privee_web/assets
npm run check        # tsc, eslint, vitest (signal-client.test.mjs runs the real WASM)
npm run e2e          # Playwright: registration, chats both ways, no plaintext on the wire
cd ../../..
mix test             # server-side key validation
```

Also run the "Manual browser checklist" in `docs/e2e-encryption.md` against a
`mix assets.deploy` build (the WASM must compile under the production CSP set
by `PriveeWeb.Plugs.SecurityHeaders`), and check interoperability with an Android build that uses
the same libsignal version (`local-dev-stack` skill, emulator at
`http://10.0.2.2:4000`): messages both ways, and a fresh PreKey session after
a server restart.

## 5. Ship

- PR title like `chore(deps): upgrade libsignal-wasm to vX.Y.Z`, stating the
  matching PriveeApp PR or issue.
- If the app is not upgraded yet, open the issue:

  ```bash
  gh issue create -R MaxDac/PriveeApp --title "Upgrade libsignal to X.Y.Z" \
    --body "The web client moves to libsignal X.Y.Z in <Privee PR URL>. Use the libsignal-upgrade skill (gradle/libs.versions.toml and libsignal/source.lock.json)."
  ```

- The server deploys from `main` (`deploy` skill). Clients with cached
  JavaScript pick up the new binary through the `WASM_VERSION` query.
