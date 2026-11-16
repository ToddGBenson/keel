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

Independent review of 9f4a47f (Opus, standing in for Fable; relayed by the PO), CHANGES NEEDED:

- **#1 CRITICAL, fixed:** the end hooks ran main's check-run.yml with `input_mapping: { repo: pr }`,
  and that task's `run:` path is `repo/ci/scripts/check-run.sh`, so they ran the PULL REQUEST's
  script with the ingestion token. Any same-repo branch could read the token or post any verdict.
  Now: no input mapping; pr-pick.sh writes the sha alone to a `pr-sha` output; check-run.sh reads it
  through `HEAD_FILE`; repo/ is main's checkout in every credentialed step.
- **#2 HIGH, fixed:** check-run.test.py asserted the mapping. It now refuses, for every step with a
  TOKEN/KEY/SECRET/PASSWORD param, an input mapped or declared from pull-request code, or a task file
  not from repo/. Run against 9f4a47f it fails 4 checks (the 3 hooks and the structural rule); it
  passes here.
- **#3 MEDIUM, closed by the operator:** the PR verdict and the chain's share the name
  `Concourse / <repo>`, and a merge commit keeps a PR head's sha in main's history. The operator made
  keel and binnacle squash-only (2026-11-16); ci/README.md records it.
- **#4 MEDIUM, fixed:** the pr-checks task timeout is 20m, not 1h. A separate serial group is ruled
  out by the three-lane cap (serial-lanes.test.py).
- **#5 LOW, documented:** a pull request with conflicts has no merge ref and is not judged.
- **#6 LOW, documented:** newest first can starve an older pull request during bursts.
- **#7 LOW, not taken:** digest-pinning python:3.13 contradicts the policy recorded in
  scripts/validate-pipeline.py (no base-image digest pins without a bump mechanism); kept by tag.

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

## Re-review (75049bc / 3131ec8): approve with nits

- 3c, a, b taken: the structural rule in test/check-run.test.py now also catches a credential by its
  `((var))` value, inline `config:` tasks, and a pull-request task that declares outputs or an
  output_mapping. Each is shown catching a deliberately bad fixture; the real 9f4a47f still fails it.

## Not verified (added after the review)

- That Concourse gives each task a copy-on-write view of its inputs, so pull-request code in the
  pr-checks task cannot change the `repo/` the later hooks read. That is Concourse's documented
  model; not tested here.

## Residual risk accepted

A same-repository branch's tests run on the worker before review. Writers can already push to main
through a PR, and the commit chain runs main's code on the same workers.
