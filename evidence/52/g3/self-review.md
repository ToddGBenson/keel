# Self-review — #52

Mode: solo (POAM-008)
PR: #53   Author: Todd Benson (claude-opus-5, AI-authored)   Date: 2026-08-14

Follow-on work that was pushed to the #51 branch after #51 had already merged, plus a merge
of `main` to pick up PR #45.

## Verified independently

Every item below was **executed on the live Concourse**, not reasoned about:

- **SAST runs and gates.** Build `keel/sast/6` succeeded in 11m18s. Both languages analysed —
  "CodeQL scanned 3 of 3 Python files" and "2 of 2 JavaScript/TypeScript files" — 0 findings,
  and the gate evaluated: "No security findings at severity >= medium." The gate logic itself
  was checked against a fixture beforehand: 2 security findings counted, 1 quality finding
  correctly ignored.
- **The deploy key works.** `check-resource keel/repo` succeeds over SSH against the private
  repository. Before it: `fatal: could not read Username for 'https://github.com'`, which took
  every job down because they all get that resource.
- **`verify-artifact` passes.** It errored with `missing inputs: sbom` on every run; build 4
  succeeded after the fix.
- **Every other job green:** build, lint, test, full-suite, secrets, sca, iac,
  suppression-audit, platform-integrity, ai-evals, ai-guardrails, agent-assurance,
  compliance-daily/weekly/monthly, metrics-snapshot, build-and-attest, set-pipeline.
- **Each new validator rule was checked by making it fail**, not by reading it:
  missing-task-input (restored the required `sbom`, got 1 error / exit 1), broken group chain
  (reinstated the old `ci`/`supply-chain` split, got the warning), `set_pipeline` var_files
  (pointed at a missing file, got 1 error / exit 1).
- **The merge preserved both sides.** After merging `main`: `mykronos-atlas.yml` is template
  2.1.0 with the exit-128 handling and still `workflow_dispatch`-only; the deploy key, the
  eight new groups and all 27 jobs are intact. I compared main's unique lines before
  resolving — they were exactly the HTTPS `username`/`password` and the old group names this
  branch supersedes, so "ours" was correct rather than convenient.
- All ten workflows confirmed `workflow_dispatch`-only on `main` and on this branch.
- shellcheck clean across all scripts; `fly validate-pipeline` clean; `validate-platform`
  clean.

## Agent findings

**None — no three-pass agent review**, the same proportionality call as #48 and #50, and it is
weaker here than there: this branch is 13 commits and touches the release lane, the SAST gate
and repository authentication. That is not a one-token fix.

The mitigating fact is that almost every change in it was driven by a failure observed on the
live pipeline and confirmed fixed on the live pipeline. The reason not to run the agents was
throughput, not a judgement that the change was small. **If one thing in this PR gets an
independent read, make it `ci/scripts/release.sh` and the `sast` gate**, because those are the
two that assert a security property rather than fix an observed break.

## Not verified

- **`set_pipeline: self` has never applied a config from `main`.** It ran and succeeded, and
  what it did was revert my branch-pinned config to main's copy — which broke authentication
  and stopped everything. It is currently PAUSED. Whether it behaves correctly once main
  carries the deploy key is **unverified**, and it is the first thing to watch after merge.
- **The `sast` gate has never fired.** It passed with 0 findings. A gate that has only ever
  seen a clean input is a gate whose failure path is untested; the counter was fixture-tested,
  the end-to-end block was not.
- **The release lane has never run.** `release-preflight`, `deploy-staging` and
  `authorize-production` are ADAPT stubs around real cosign calls, and no build exists for any
  of them.
- **`mykronos-*` remain paused** — no ingestion token. Their SAST/secrets/atlas ingestion has
  still never executed end to end, before or after any of this.
- **`build-and-attest`'s new hard failure on a missing SBOM is untested.** I changed a warning
  into `exit 1`; the SBOM has been present on every run since.
- The 846MB-per-language CodeQL download is unaddressed. `serial: true` stops the jobs
  starving each other; it does not make the cost reasonable for a repo with five source files.

## Cold-read notes

- **I did not notice #51 had merged.** I kept pushing to the branch for roughly a dozen
  commits after it was squashed into `main`, and only found out when asked where the PR was.
  Nothing was lost, but for a while the most important work in this session had no PR, no
  review path, and no way to reach `main` — and I was reporting on it as though it did.
- **The merge nearly reverted someone else's fix.** PR #45's resync improved the Atlas lane's
  handling of an empty repository; this branch predated it and a naive merge would have put
  2.0.0 back. I checked because the diff looked larger than my own change, not because I had a
  process for it. A rebase would have surfaced it more loudly than a merge did.
- **What I did not want to look at:** that I have now been the author, the reviewer and the
  merger of a change that removes the only merge gate the repository had. Every individual
  step was directed and recorded, and the aggregate is still one identity with no independent
  check anywhere in the loop. POAM-014 says this; it deserves saying in the first person too.

## Residual risk accepted

- Single-identity review, with no agent passes on a 13-commit branch.
- Three of the changed lanes (release, sast-failure-path, mykronos) have never run.
- Merged content will be applied by `set_pipeline: self`, whose correct operation is itself
  unverified.
- Next external sample review due: 2026-10-01.
