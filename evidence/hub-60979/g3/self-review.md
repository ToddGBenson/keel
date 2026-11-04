# Self-review — TheHub #60979

Mode: solo (POAM-008); agent self-review per the operator's 2026-11-04 decision
PR: see the branch feat/protection-drift-60979   Author: workflow builder lane (Claude Opus 5.5, AI-authored)   Date: 2026-11-04
verdict: pass

Branch-protection drift check: `configure-github.sh --verify-only` and a daily
`protection-drift` job compare main's live protection with `.sdlc/protection.yaml`.

## Verified independently

- **The tests fail against main.** Committed first (895f806) and run against main's code:
  `protection-drift.test.py` 25 failures (`unknown option: --verify-only`, no declaration,
  OPERATING.md claiming signatures), `protection-drift-wiring.test.py` 12 failures (no job,
  task or script). On this branch both pass.
- **Guards, not evidence.** On main these also passed, vacuously: GET-only, drift exits 1,
  404 exits non-zero, token not in argv/output, reason rule refuses, defaults readable, and
  the wiring test's no-trace/no-echo/no-other-credential checks.
- **Exercised for real.** `bash scripts/configure-github.sh --verify-only --repo ToddGBenson/keel`
  with my own gh login: six `match` lines, exit 0 (2026-11-04).
- **A YAML trap found by running it.** `reason: TheHub #60849 ...` unquoted parses as
  `reason: TheHub`, because ` #` starts a comment. The checker refused it, which is how I
  found it. It now names the cause in its error. The real declaration uses `>-` blocks.
- shellcheck v0.10.0 on `scripts/configure-github.sh` and `ci/scripts/protection-drift.sh`:
  clean. `validate-pipeline.py`, `validate-manifest.py`, `test-manifest.py check`: ok. Lint
  stage 9/9. `supply-chain`, `platform-release`, `control-liveness(-keel)`, `check-run`,
  `serial-lanes`, `container-limits`: pass.

## Agent findings

None. No three-pass agent review was run.

## Not verified

- The Concourse run: it needs `github_protection_token`, which does not exist yet (operator step).
- Propagation to binnacle via `sync-platform.sh`. binnacle needs its own `.sdlc/protection.yaml`
  and a `test/manifest.txt` line, or its lint goes red on the platform-owned test.
- The curl path against the real API (tested only with a curl stub).

## Cold-read notes

- `required_signatures: false` is declared as live, with this story as the reason. No
  decision turned signatures off, and POAM-009 says they are on. That is the owner's call. The
  PR gives the command to turn them back on.
- Open #163 (TheHub #60978) rewrites `configure-github.sh`'s `CHECKS` and OPERATING.md. Whichever
  PR lands second rebases and updates `DEFAULTS`, the test's `CHECKS` parse and the declaration.

## Residual risk accepted

One more read-only credential in Vault. A leaked token reads protection settings and
changes nothing.
