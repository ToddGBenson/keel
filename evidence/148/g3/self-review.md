# Self-review — TheHub #60981

Mode: solo (POAM-008)
PR: #148   Author: Todd Benson (Claude Opus 5.5, AI-authored)   Date: 2026-10-23
verdict: pass

Every gate command writes an evidence record `scripts/control-liveness.py` can count, so G0, G1
and G5 can register (POAM-018).

## Verified independently

- **The new tests fail against main.** The tests were committed first (`0371645`) and run
  against main's scripts: `control-liveness.test.py` 8 failures (empty directories counted,
  G5 never counted), `gate-record.test.py` red (the writer did not exist),
  `validate-platform.test.py` 9 failures (no evidence-path rule). On this branch: 18, 47 and
  11 ok, 0 failed.
- **Key validation was exercised, not just read.** I passed 23 hostile keys (traversal,
  separators, absolute paths, a trailing newline, Unicode digits, uppercase). Each exited 2,
  and nothing was written anywhere in a sandbox nested three levels deep. Three
  verdict-forgery attempts through role, gap and producer text were refused.
- **The real run.** `/ready` on hub-60981 wrote `evidence/hub-60981/g1/ready.md`,
  NOT READY, 1 of 4 items satisfied. `--update-baseline` then gave g1 = 1 and g3 = 15
  (16 with this record).
- All 13 `test/*.test.py` files pass. `selfreview-check.test.js`: 33 passed. Guard self-test
  passes. `validate-platform`, `validate-manifest` and `control-liveness --check` pass, and
  `./keel check` is green.

## Agent findings

None. I did not run a three-pass agent review, which is consistent with recent PRs.

## Not verified

- Shellcheck on the `ci-stage.sh` lines (Concourse lint task).
- The post-merge Concourse run.
- Propagation to binnacle (`sync-platform.sh`).

## Cold-read notes

- AC-4 as written would drop G3 from 15 to 0 and fail `--check`. I grandfathered the 15
  records in a frozen set instead of editing them (PD-7). The PO needs to decide this; the PR
  body says so.
- I judged G1 on my own story. The record says it is not independent.

## Residual risk accepted

A fork with its own pre-existing G3 records will see them read 0 after syncing this change.
