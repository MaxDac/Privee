---
name: deploy-privee
description: Deploy Privee to production (Fly.io) by triggering the PriveeDeploy workflow with gh. Use when asked to deploy, release, ship or publish Privee, or to check what version is deployed.
---

# Deploy Privee

This repository only holds the code and its checks; it never deploys. Deployments
run from a separate repository, [PriveeDeploy](https://github.com/MaxDac/PriveeDeploy),
whose `Deploy` workflow checks out Privee at a given ref and deploys it to Fly.io.
You trigger that workflow with `gh`.

## Settings

- Deploy repository: `$PRIVEE_DEPLOY_REPO` if set, otherwise `MaxDac/PriveeDeploy`.
  In a fork, ask the user for their deploy repository if the variable is unset.
- Code repository: the `origin` remote of this checkout (`gh repo view --json nameWithOwner -q .nameWithOwner`).
  The deploy repository builds the repository in its `PRIVEE_REPO` variable
  (default `MaxDac/Privee`); check they match with
  `gh variable get PRIVEE_REPO -R <deploy repo>`.

## Steps

1. **Pick the commit.** Default to the latest commit of `main` on the remote
   (`git fetch origin main` and `git rev-parse origin/main`); use another branch,
   tag or SHA only if the user asks. Never deploy unpushed local commits.

2. **Check CI.** The commit must have a successful `CI` run:

   ```bash
   gh run list -R <code repo> -w CI -c <sha> --json status,conclusion,url
   ```

   If it failed or is still running, report it and stop (or wait for it with
   `gh run watch <run id> -R <code repo>` if the user agrees).

3. **Confirm.** This is a production deploy. Show the user the deploy repository,
   the commit (`git log -1 --oneline <sha>`) and get an explicit yes before
   continuing.

4. **Trigger the deploy:**

   ```bash
   gh workflow run deploy.yml -R <deploy repo> -f ref=<sha>
   ```

   Pass the full SHA, not a branch name, so the deployed code is exactly what was
   checked.

5. **Watch it.** Find the run and follow it until it finishes:

   ```bash
   gh run list -R <deploy repo> -w deploy.yml -L 1 --json databaseId,status,url
   gh run watch <run id> -R <deploy repo> --exit-status
   ```

   On failure, show the failing step with `gh run view <run id> -R <deploy repo> --log-failed`.

6. **Verify.** The run summary shows the public URL. Check the instance answers:

   ```bash
   curl -fsS https://<host>/api/app/info
   ```

   It must return `"service": "privee"`. The first request can be slow if the
   machine was stopped (scale to zero).

## Don'ts

- Don't run `fly deploy` from this repository; there is no `fly.toml` here.
- Don't deploy without the user's confirmation, and don't retry a failed deploy
  more than once without asking.
