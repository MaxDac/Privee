---
name: deploy
description: Deploy the upstream Privee server to Fly.io, verify it and roll it back. Production (Fly app "bauta", https://bauta.fly.dev) deploys automatically from main through .github/workflows/main.yml; this skill covers watching that run, post-deploy checks, migrations, and rollback with fly releases / fly deploy --image. Use when asked to deploy, check a deploy, investigate a failed deploy or roll back. Never deploy manually unless the user explicitly asks.
---

# Deploy (Fly.io)

## How production deploys

- Every push to `main` in `MaxDac/Privee` runs
  [`main.yml`](../../../.github/workflows/main.yml): the full `ci.yml`, then
  the `deploy` job (`flyctl deploy --remote-only`, GitHub environment
  `production`, secret `FLY_API_TOKEN`). Forks never deploy.
- `fly.toml`: app `bauta`, region `ams`, host `bauta.fly.dev`, internal port
  8080, one shared-CPU 1 GB machine, auto stop/start.
- Fly builds the `Dockerfile` remotely. Before the new machine starts,
  `release_command = '/app/bin/migrate'` runs `PriveeWeb.Release.migrate`.
  If migrations fail, the deploy stops and the old release keeps running.
- Chat ciphertext is in node-local ETS: every deploy restarts the machine and
  drops it. Clients recover by starting a new epoch. Keep a single machine.

So "deploying" normally means: merge the PR to `main` and watch the run.
Do **not** run `fly deploy`, `fly secrets set` or `fly scale` unless the user
explicitly asks.

## 1. Before merging

- CI is green on the PR (`gh pr checks <n>`).
- The change is backward compatible with released Android apps
  (`docs/cross-repo.md`).
- New migrations are reversible and safe to run while the old release still
  serves traffic (add columns nullable or with defaults; no destructive change
  in the same release that stops using the column).
- New runtime environment variables are set as Fly secrets **before** merging
  (ask the user; never print secret values).

## 2. Watch the deploy

```bash
gh run list -R MaxDac/Privee --workflow main.yml --limit 5
gh run watch <run-id> -R MaxDac/Privee --exit-status
```

## 3. Verify

```bash
curl -s https://bauta.fly.dev/api/app/info      # service, api_version, version
curl -sI https://bauta.fly.dev/ | head -n 1      # 200
fly status -a bauta
fly logs -a bauta --no-tail | tail -n 100       # migrations and boot
```

`api_version` must be unchanged unless the PR intentionally bumped it (see
`docs/cross-repo.md`). Optionally log into the web client and send a message
between two browsers.

## 4. Roll back

Prefer a forward fix (revert PR merged to `main`), which redeploys through CI:

```bash
git revert <sha> && git push   # via a PR, per the normal flow
```

For an urgent rollback, with the user's approval:

```bash
fly releases -a bauta --image          # find the last good release and its image
fly deploy -a bauta --image <registry.fly.io/bauta:deployment-...>
```

Redeploying an old image runs its `release_command`, which only migrates up.
If the bad release ran a migration the old code cannot handle, roll the
database back first, with the user's approval:

```bash
fly ssh console -a bauta -C "/app/bin/privee_umbrella eval 'PriveeWeb.Release.rollback(Privee.Repo, <version>)'"
```

`<version>` is the timestamp of the oldest migration to revert: every
migration from it onwards is rolled back (`Ecto.Migrator.run(repo, :down,
to: version)`). After any manual action, push the matching revert to `main` so
the next deploy does not undo it.

## 5. Manual deploy (only if asked)

```bash
fly deploy --remote-only -a bauta
```

Run it from a clean checkout of `main` so production matches the repository.

Self-hosted instances follow `docs/self-hosting.md`.
