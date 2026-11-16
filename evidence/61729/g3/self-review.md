# Self-review — TheHub #61729 (keel main: fix the red unit suites)

Mode: solo (POAM-008); agent self-review per the operator's 2026-11-04 decision
PR: #PRNUM   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-16
verdict: pass

The protection-drift job (keel #164) came in with no timeouts, so `test/task-timeouts.test.py` has
failed on main since. This adds `timeout: 15m` to its `get repo`, `get daily-0600` and task.

## Verified independently

- **The red, reproduced on main 54db881** (python:3.13, --cpus 2 --memory 2g, the same steps as
  `unit-results.yml`): `task-timeouts.test.py` fails 2 checks: "every task step declares a timeout
  <= 3h" (`protection-drift.plan[2] task protection-drift: no timeout`) and "every get and
  set_pipeline step declares a timeout <= 15m" (`plan[0] get repo`, `plan[1] get daily-0600`).
  It is the only failing suite. GitHub's `Unit suites → MyKronos` run 43774683665 on main shows the
  same three lines.
- **The rest of the story's list is already green on main**, fixed by keel #173 (bce7caf): the PS
  hook cases "approve, splatted method" and "list pending, irm GET" (selftest 305 passed, 0 failed),
  and class `powershell-tool` (hook-bypass-corpus: 224 entries, 804 hook runs, 0 failed).
- **On this branch:** task-timeouts passes; every lint- and test-stage manifest test passes;
  selftest 305/0; corpus 0 failed; agent evals rc=0; `validate-pipeline.py` rc=0.
- **`protection-drift --verify-only` against live protection:** `bash scripts/configure-github.sh
  --verify-only --repo ToddGBenson/keel` (GET only, the operator's gh login) on 2026-11-16: all 6
  declared fields match on main, rc=0.
- **binnacle, the same defects checked:** binnacle main 9c8474e has no protection-drift job (so no
  timeout defect), and its lint, test, selftest (290/0) and corpus (214, 0 failed) are green. Its
  hooks lack keel #173's later additions; that port is filed as its own story.

## Agent findings

None. No three-pass agent review was run; the change is three `timeout:` lines.

## Not verified

- The Concourse `protection-drift` job itself: build 1 errored on "undefined vars:
  github_protection_token" (TheHub #61716), an operator-provided secret. Unverified until it exists.
- That 15m is enough for the task on a slow day: the script makes a handful of GitHub API reads,
  but no successful Concourse run exists to measure. Unverified.

## Cold-read notes

- 15m matches every other `get` in the pipeline; tasks elsewhere use 3h or 5m. 15m for an
  API-reading task is generous and still frees the ingest lane if a call hangs.
- 61709 and 61710 (the red Unit suites on #173 and #172) have this as their cause.

## Residual risk accepted

None.
