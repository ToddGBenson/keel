# Self-review — TheHub #60980

Mode: solo (POAM-008)
PR: #147   Author: Todd Benson (Claude Opus 5.5, AI-authored)   Date: 2026-10-23

One list of test files, `test/manifest.txt`, read by `ci/scripts/ci-stage.sh` and by
`./keel check` through `scripts/test-manifest.py`. CI fails on a test file the list does not
name and on an entry with no file behind it.

## Measured, not read (2026-10-23)

- Before: `./keel check` ran 2 of 11 test files; ci-stage.sh named 11 by hand. With a
  deliberately failing, unlisted `test/zz-deliberate.test.py` added to `main` (af878f1), both
  CI stages exit 0 in `python:3.13` (lint 1s, test 14s) and the old `./keel check` is green.
- After (83cfba3), same image: clean lint rc=0 (3 of 3 files), clean test rc=0 (8 of 9 files,
  `selfreview-check.test.js` NOT RUN for lack of node, as before), self-test 143/143, evals hold.
  Unlisted failing file: lint rc=1, naming it. Listed under `test`: lint rc=0, test rc=1,
  `FAILED: test/zz-deliberate.test.py`. Listed locally: `./keel check` red with
  `! warn: test/zz-deliberate.test.py FAILED`.
- `test/test-manifest.test.py` against the old scripts: 11 checks FAIL (the script it drives
  is missing, so its 15 own-tool cases cannot run at all); 28/28 pass on this branch, locally (Windows) and on ubuntu-latest (`Unit suites`).
- Wall clock on the operator's Windows host, docker hidden: `./keel check` 3m58s,
  `./keel check --quick` 3m12s. The guard self-test is 2m41s of each.

## Not changed

- `.github/workflows/ci.yml` (workflow_dispatch only) still names 3 test files by hand;
  `unit-results.yml` globs `test/*.test.*` and runs all of them on every PR.
- shellcheck 0.10.0 is clean on `ci/scripts/ci-stage.sh`. On `keel` it reports SC2015,
  SC2221/2222 and SC2034 on lines this change did not write; CI does not shellcheck `keel`
  (no `.sh` suffix).
