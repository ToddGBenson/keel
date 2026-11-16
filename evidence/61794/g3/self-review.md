# Self-review — TheHub #61794 (guard-bash.sh fails closed when a helper fails)

Mode: solo (POAM-008); agent self-review per the operator's 2026-11-04 decision
PR: #PRNUM   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-16
verdict: pass

On keel #176's Actions run the hook ALLOWED KB-177 (`curl -T env.json …/environments/production`)
once; every rerun blocked it. The hook decides with text tools inside `$(...)` captures and never
checked that they ran, so a helper that errored or was killed left a capture empty and the hook
reached `exit 0`. Now every helper runs through a wrapper that records real errors, and an EXIT
trap turns an allow into a block when any were recorded.

## Verified independently

- **Red first:** `test/hook-fail-closed.test.py` against main's hook (a5466d1): 114 failures.
  A shim that makes ONE helper fail (exit 2, or SIGKILL) lets the must-block commands through:
  a failing `sed` lets `gh pr merge 12` and `git push --force` through; a failing `tr` alone lets
  KB-177 through, in both jq and no-jq modes and for both tools. That is the observed failure.
- **Green after:** 154 checks, 0 failed, with real jq; also run with the jq shim. No fault: the
  rules decide (each command blocked by its rule, `git status` allowed).
- **No false blocks:** selftest 305 passed / 0 failed and the bypass corpus 224 entries, 804 hook
  runs, 0 failed, both with real jq and without; every manifest test passes; agent evals rc=0.
  grep's 1 (no match) and 141 (SIGPIPE from an early-closing reader such as `grep -q`) are not
  faults, which is what keeps those green.
- **`type -P jq`, not `command -v jq`:** `command -v` reports the new jq() function even with no jq
  binary, which would send the no-jq mode down the jq path and block everything. Caught by the
  no-jq selftest before the change was kept.
- shellcheck v0.10.0 at CI's `-S warning`: clean. The two SC2016 infos are on main already.

## Agent findings

None yet. An independent Opus review runs before the operator sees this (security-sensitive hook).

## Not verified

- **The root cause of the original allow.** The Actions log has no hook stderr. A transient helper
  failure under the corpus test's 8 parallel hooks on a 2-CPU runner is the best fit, and a failing
  `tr` reproduces it exactly, but it is unproven. The corpus test now prints the hook's stderr on a
  wrong verdict, so the next one is diagnosable.
- **A failed fork.** If bash cannot fork a capture at all, no wrapper runs and nothing is recorded.
  Not covered; unverified how often a runner refuses a fork rather than a helper failing.
- **guard-write.sh** has the same structure and was not changed. Follow-up.
- Git Bash on Windows (where the hook also runs) was not exercised here.

## Cold-read notes

- Fail closed means an intermittent host problem now blocks a harmless call instead of allowing a
  harmful one; the message says it is an internal error and to retry.
- Wrapping is by function name, so a rule that calls a helper by absolute path would bypass it. None
  does today; the shims test the names the hook uses.

## Residual risk accepted

The fork-failure and guard-write.sh gaps above.
