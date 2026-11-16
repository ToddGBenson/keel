# Self-review — TheHub #61778 (Concourse posts PR-head checks: keel)

Mode: solo (POAM-008); agent self-review per the operator's 2026-11-04 decision
PR: #178   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-16
verdict: pass

New `pr-checks` job: every ten minutes it picks the newest open same-repository pull request head
with no verdict, runs the unit suites on it and reports `Concourse / keel` on that head through
MyKronos. No GitHub token, no pull-request resource type.

## Verified independently

- **MyKronos accepts it as is:** `/api/ingest/check-runs` (mykronos `backend/mykronos/api/ingest.py`)
  takes any `job`, names the check `Concourse / <repo>` (`ci_check_run.py`), and answers a `start` on
  a commit that already has a check with `unchanged` and its status, without calling GitHub. So no
  mykronos change is needed; keel's jobs are deliberately not registered there (ci.py, "KEEL'S 23
  STUBS").
- **`test/pr-pick.test.py` runs pr-pick.sh against a real local origin** with GitHub's ref shapes:
  the newest open same-repo head is judged; a fork head, a closed PR (no merge ref) and a head that
  is `main` are never asked about; completed heads are skipped, in-progress ones re-judged; nothing
  left marks `pr/.none`; a refused answer or curl failure fails; an SSH uri without a key is refused;
  the pick limit holds. 26 checks pass.
- **`test/check-run.test.py`** now asserts pr-checks reports success/failure/failure from its hooks
  on `pr/`, with `NO_COMMIT_OK=1`, posts nothing from its plan, is `serial`, and that the task that
  runs pull-request code has no params; and that only pr-checks may use `NO_COMMIT_OK`. Fails on
  main (no such job).
- **Full suite** (python:3.13, --cpus 2 --memory 2g): every manifest test, selftest 305/0, corpus
  224/0, evals and `validate-pipeline.py` pass. shellcheck v0.10.0 on the three scripts: clean.

## Agent findings

None. No three-pass agent review was run.

## Not verified

- **The job on a real Concourse:** not set. Unverified until the pipeline is set from main and a
  tick picks a real pull request. The first run should be watched.
- **That GitHub's ed25519 host key in pr-pick.sh is current:** taken from GitHub's published keys;
  a mismatch fails the pick loudly (StrictHostKeyChecking=yes), it does not fail open. Unverified here.
- **Node test files** (`test/*.test.js`) do not run in the python:3.13 image; they still run on
  Actions and `./keel check`. Unverified on Concourse.

## Cold-read notes

- `pr-checks` shares the `verdict` lane, so a main commit's chain can queue a few minutes behind a
  pull request run. The lane cap (three) forbids a fourth lane.
- A pull request's code runs on a LAN worker with the network and no credential. Only branches in
  this repository (write access) are run; forks never are. Comparable to main's commits, which
  already run there.
- binnacle needs the same files (ci/ is project-owned there); a separate PR.

## Residual risk accepted

A same-repository branch's tests run on the worker before review. Writers can already push to main
through a PR, and the commit chain runs main's code on the same workers.
