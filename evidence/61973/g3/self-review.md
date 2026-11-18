# Self-review — TheHub #61973 (the guards fail closed on time and on signals)

Mode: solo (POAM-008); agent self-review, pending the independent review before merge
PR: (set when opened)   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-18
verdict: pass

Claude Code gives a hook 60 s and lets the call PROCEED when it runs out. It blocks only on exit 2.
The review of #184 found three paths outside that diff that still cost seconds per kilobyte for
some command shapes: on Linux a write-heavy command reached 56-67 s, and on Git Bash far smaller
ones did. The review of #186 found two more ways to an allow. A catchable signal ended the hook
with 128+N and empty stderr. And exit 141 counted as success for every helper, so an extractor
killed by SIGPIPE left an empty capture.

## The change

- **A deadline (guard-bash.sh).** The hook now runs as a supervisor and a worker. The supervisor
  reads nothing and decides nothing. It starts the guard (this file, `--guard-worker`) as a background
  job in its own process group, plus a timer. If the guard finishes first, its verdict is passed on.
  If the timer fires first (40 s), the whole group (guard and helpers) is killed and the call is
  BLOCKED, as an internal error.
  - The guard's stdout is discarded and its stderr goes to a file the supervisor prints with
    builtins, so a helper that outlives the guard cannot hold Claude Code's pipes open.
  - A timer that cannot start (no `sleep`) is a block.
  - A guard that dies of a signal or crashes (any exit but 0 and 2) is a block.
  - A signal to the supervisor (HUP, INT, TERM, PIPE, ALRM) is a block.
- **A size cap (guard-bash.sh).** A command over 1 MiB is refused without being read.
- **Signals (both hooks).** HUP, INT, TERM, PIPE, ALRM, USR1 and USR2 are each recorded as a fault and
  turned into a block by the EXIT trap. SIGKILL cannot be caught: a hook killed that way exits 137.
- **141 is a fault (both hooks).** Every wrapped helper drains its input, so none is a writer whose
  reader stopped early. The full suites confirm no false block.
- **Review of #184, nits folded in:**
  - `guard_nextnl` is bounded (`guard_nc <= NR`).
  - The timing budget takes the better of two runs.
  - A harmless padded command (allowed, so every rule runs on every view) is timed, and must be
    allowed.
  - evidence/61939 now says "16 of 16 on the runner laptop" and names the paths it did not cover.
- docs/11-ai-agent-controls.md (GP-4) states what fails closed, and that SIGKILL does not.

The three slow paths are NOT made linear in this change. The deadline makes any slow shape a
block instead of an allow. TheHub #61987 reworks normalize() (one of the three), and the curl loop
and dot-segment removal remain slow but bounded: a command that reaches them blocks at 40 s.

## Verified independently

- **Red first:** the new test/hook-deadline.test.py against main 7d4c7fb: 30 of 33 checks failed.
  - With a hung helper the hook was still running at 30 s, for a harmless command and for
    must-block ones. Claude Code would have let them through.
  - TERM, INT, HUP and PIPE to either hook ended it with 128+N.
  - A sed, jq or cat killed by SIGPIPE let `gh pr merge` and `git push --force` through, and in
    guard-write.sh a jq or cat killed that way let a cloud key through.
  - A 1 MB harmless command was read and allowed.
- **Green after:** 33 passed, 0 failed.
  - The deadline cases block at the 2 s test deadline and return in about 2 s, so the hung helper
    did not hold the pipes.
  - With no hung helper, `git status` is allowed.
- **The real shape (local only, not committed):** the review's slow write-heavy command, on this
  branch, blocked at 40.0 s with the deadline message. The review measured it at 56-67 s on main.
- **No regressions:**
  - selftest 330 / 0; bypass corpus 224 entries, 804 runs, 0 failed (8 hooks in parallel);
    hook-fail-closed (now with the harmless padded case, best of two) and hook-write-fail-closed
    all pass.
  - `./keel check` green in a capped python:3.12-slim container.
  - shellcheck v0.10.0 `-S warning` clean; pinned gitleaks v8.18.4: no leaks.

## Not verified

- **Git Bash on Windows was NOT run.** The supervisor relies on `set -m` (a background job in its
  own process group), `kill -- -PGID`, `wait` being interrupted by a trapped signal, and `sleep` in
  `/usr/bin`. If the group kill fails there, the hook falls back to killing the guard alone. Its
  helpers' output then goes to the file, not to Claude Code, so the verdict still arrives. This
  needs one run of hook-deadline.test.py, selftest.sh and the corpus on the Windows host.
- Each call now starts one more bash and one `sleep`. On Linux that costs nothing measurable. On
  Git Bash, where process starts are slow, it is not measured here.
- The interaction with TheHub #61843 (PATH pin, not yet merged): the supervisor runs before the pin
  would. It uses only builtins, `$BASH`, `sleep`, `mktemp` and `rm`. hook-deadline.test.py already
  rewrites the pin line in its copy when it exists.

## Residual risk accepted

SIGKILL to the hook, the untested Windows path, and the three slow paths being bounded rather
than fast.
