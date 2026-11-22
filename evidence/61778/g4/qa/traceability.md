# G4 QA verification - TheHub #61778, keel half (keel #178, merged as 3373c614)

key: 61778
gate: g4 (Verified), Part A (QA)
verdict: fail
failed criterion: AC4 (the check's link is not a link to the build); AC3 as written is not met for keel
date: 2026-11-17 (read 06:42Z to 07:00Z)
verified at: keel main c7ba09eccb363a4badb2ad80f5fbf01311440b8a; Concourse pipeline main/keel, job pr-checks
recorded by: Verifier agent for the PO (Claude Opus 5.5, model claude-opus-5-5), session https://claude.ai/code/session_017AsgBjWY1XqoZ6sEHuwhc1
independence: did not build, review or merge #178.
story: "Concourse posts PR-head checks for keel and binnacle (the pr-gates pattern), so their PRs are judged without GitHub Actions"
scope: keel only. binnacle's half belongs to the binnacle sub-PO and was not examined.
refs: TheHub #61006 (v0.1.0), POAM-018

## Real environment

The delivered thing is the `pr-checks` job running in the live Concourse pipeline `main/keel` and the check-run it posts on GitHub. Both were read live; nothing was triggered.

## Traceability (AC -> test -> result -> evidence)

| AC | Check | Result | Evidence |
|---|---|---|---|
| AC1 a new keel PR gets 'Concourse / keel' on its head within 15 minutes | check-runs on PR #187 head df7f7c4d | met | last commit 06:38:59Z, PR opened 06:39:40Z, `Concourse / keel` (app mykronos-platform) started 06:41:31Z, conclusion success: about 2.5 minutes |
| AC2 a red unit suite turns the check red | check-run on PR #181 head 5c7c7b6a, and its build | met | `Concourse / keel` conclusion failure, started 2026-11-16T21:07:18Z, title "Not verified: pr-checks did not pass"; pr-checks build 86 (id 2421609) status failed, log line "Failed on #181 5c7c7b6a...: hook-fail-closed.test", then `{"conclusion":"failure","outcome":"updated"}` |
| AC3 no GitHub Actions minutes used (Actions runs list empty for the PR) | `gh run list --commit df7f7c4d` | not met as written for keel | the list is not empty: Unit results, Mykronos sast, Mykronos secrets (plus CodeQL and Gitleaks check-runs) ran on #187. The Concourse check itself uses no Actions. keel is public and keeps Actions by design, so the criterion fits binnacle and TheHub, not keel; it needs re-scoping by the PO rather than a pass from me |
| AC4 `gh pr checks` on the next keel PR lists the Concourse check with a link to the build | `gh pr checks 187` and the check-run's `details_url` | **not met** | `Concourse / keel  pass  2m48s  https://github.com/ToddGBenson/mykronos`. The link is the mykronos repository, not the pr-checks build. The same holds for PR #181's failing check-run, so a red check cannot be followed to its log from GitHub |

Unit coverage: `test/pr-pick.test.py` (which heads are judged, once each) and the pr-checks wiring assertions ran green in Concourse keel/test 168 (ref c7ba09ec): "pr-checks.on_success reports success on the pull request head", "pr-checks.on_failure reports failure on the pull request head", "pr-checks.sh runs the same suites as Actions' unit-suites".

## What I ran

1. `curl http://127.0.0.1:8080/api/v1/teams/main/pipelines/keel/jobs` and `/jobs/pr-checks/builds?limit=4` (anonymous): builds 137-139 succeeded, 140 started at read time; the job polls about every 10 minutes.
2. `curl -N .../api/v1/builds/2421609/events` (pr-checks build 86): judged #181 5c7c7b6a, failed on hook-fail-closed.test, reported failure on the head.
3. `gh pr checks 187 -R ToddGBenson/keel`; `gh api repos/ToddGBenson/keel/commits/df7f7c4d.../check-runs`; `gh api repos/ToddGBenson/keel/commits/5c7c7b6a/check-runs`; `gh run list --commit df7f7c4d...`.

## Could not verify

- Queue time from PR push to the check is measured from check-run timestamps only; Concourse's anonymous build JSON has no created time.
- Build 86's log also shows `curl: (6) Could not resolve host: mykronos.toddbenson.net` twice before the check-run post; the check still posted. I did not trace what those two calls were for.

## Did not examine

- binnacle's half of the story, and its `Concourse / binnacle` check.
- Part B (security: the GitHub App credential handling in the poster) and Part C (not AI-relevant). This is the QA verdict only.
- No forced-failure PR was opened; AC2 rests on the real failure of #181.

## To pass

Set the check-run's details URL to the pr-checks build (`<concourse>/teams/main/pipelines/keel/jobs/pr-checks/builds/<n>`), and have the PO re-scope AC3 for keel, then re-verify on the next keel PR.
