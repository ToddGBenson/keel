# Self-review — TheHub #60935

Mode: solo (POAM-008)
PR: #143   Author: Todd Benson (Claude Opus 5.5, AI-authored)   Date: 2026-10-22

Close the three overdue POA&M entries (POAM-010, POAM-014, POAM-016), and apply the operator
decision that `sca` and `container-scan` fail when there is nothing to scan.

## Outcome per entry

| Entry | Outcome | Why |
|---|---|---|
| POAM-016 | **Closed** | One release path, `release.yml`. Concourse release jobs, task and script deleted. Staging/deploy stubs and `PRODUCTION_URL` removed |
| POAM-010 | **Re-dated to 2026-11-21** (first extension) | The weak job is deleted, but the remaining G5 has never run, and the `production` environment refused tags until the operator applies the new policy |
| POAM-014 | **Re-dated to 2026-11-21** (first extension) | `Concourse / keel` does not run on PR heads. It reports on `main` commits only |

## Measured, not read (2026-10-22)

- `gh api repos/ToddGBenson/keel`: `visibility: public`.
- `gh api repos/ToddGBenson/keel/environments/production`: `required_reviewers` (`ToddGBenson`,
  `prevent_self_review: false`), `deployment_branch_policy: {protected_branches: true,
  custom_branch_policies: false}`, `can_admins_bypass: true`.
- `gh run list -w release.yml`: one run ever, `31770313398`, `workflow_dispatch` from `main`,
  2026-08-14, still `queued`.
- `fly builds` (read-only): `release-preflight` 2 builds (#1 failed, #2 succeeded, 2026-10-11).
  `authorize-release` 0 builds. `container-scan` 1 build, succeeded, scanned nothing.
- `gh api .../branches/main/protection`: 1 review, no required status checks, `enforce_admins`
  off.
- PR-head workflows on #142: `Unit results`, `Mykronos sast`, `Mykronos secrets`, all success,
  none required.
- `scripts/sync-platform.sh`: `git fetch upstream --no-tags` and `UPSTREAM_REF=upstream/main`.
  Forks take `main`, not tags.

## Verified independently

- **The new no-subject tests fail against the old scripts.** I put `grype.sh` and `trivy.sh`
  back to `main` and re-ran the tests: 4 failures in each file. On this branch: all pass.
- **checkov `github_actions` over `.github/workflows/`** (bridgecrew/checkov, local): 676
  passed, 0 failed, 0 skipped. The CKV_GHA_7 skip is gone because the input it covered is
  gone.
- **ShellCheck 0.10.0** is clean on `configure-github.sh`, `grype.sh`, `trivy.sh`,
  `ci-stage.sh`, and on each `run:` block of `release.yml` (extracted).
- `fly validate-pipeline -c ci/pipeline.yml`: looks good. `scripts/validate-pipeline.py` ok,
  20 warnings (21 on `main`; the removed release task was one). `validate-manifest.py` ok.
  `validate-platform.py`: 0 warnings. Every `test/*.test.py` passes. `selfreview-check.test.js`:
  33 passed. `./keel check`: green. Guard self-test and agent evals pass.

## Agent findings

None. No three-pass agent review, consistent with recent PRs.

**If one thing gets an independent read, make it `release.yml` `authorize-release`'s approval
check.** It uses `GET /actions/runs/{id}/approvals`, filtered to `state == approved` for the
`production` environment. I have not run it against a real approval. If that API returns
nothing for an approved run, the job fails closed. That is the safe direction, but it would
block the first release.

## Not verified

- **No release was dispatched.** G5 is a human act. The gate's behaviour on a real tag is
  POAM-010's closure evidence, and it comes from the operator's first release.
- **The environment policy change is not applied.** `configure-github.sh` now sets `main` +
  `v*` tags. Until someone runs it, a tag dispatch is refused by the environment.
- **Concourse does not apply the pipeline until merge.** Deleting the release jobs and the
  release group takes effect when `set-pipeline` runs on `main`. Their build history leaves
  the UI with them, so it is recorded above.
- **Forks that deploy a service lose the `staging`/`authorize-and-deploy` scaffolding** from
  `release.yml` on their next sync (`.github/workflows/` is `merge_required`). It was all
  `echo "ADAPT"` stubs. `docs/07-release-and-change.md` still describes what to build.
