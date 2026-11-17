# Self-review — TheHub #61843 (guard-bash.sh finds its helpers only in system directories)

Mode: solo (POAM-008); agent self-review, pending the independent review before merge
PR: #189   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-17
verdict: pass

#61794's review finding #3 (MEDIUM, follow-up): PATH was not pinned. The hook reads every command
through grep, sed, awk, tr, cat and jq, looked up on PATH. A helper planted in a user-writable
directory earlier on PATH that exits 0 or 1 is not a fault, so the #61794 wrappers cannot see it.
On main, a grep that always says "no match", or a jq, sed or cat that prints nothing, makes the
hook ALLOW `gh pr merge 12`, `git push --force` and KB-177.

## The change

- The hook pins PATH before it runs anything: `/usr/bin:/bin:/usr/sbin:/sbin` on Linux and macOS,
  and `/usr/bin:/bin:/mingw64/bin` on Git Bash (`$OSTYPE` msys or cygwin). `/usr/local/bin` is
  excluded, because Homebrew on Intel Macs makes it user-writable.
- A jq outside those directories is not used, and the sed fallback runs instead; the corpus holds
  that mode. A helper missing from them exits 127, which the wrappers record, so the hook blocks.
- **Test seam:** the hook tests run a copy whose one marked line (`# guard-path-pin`) is a no-op,
  so the copy keeps the test's PATH. The live hook takes no override: no variable, flag or file.
  `guard_path` is assigned before use, so an inherited value is overwritten (tested).

## Verified independently

- **Red first:** the new test/hook-path-pinned.test.py runs the LIVE hook with planted helpers
  first on PATH. Against main c7ba09e, 37 of 54 checks failed. A planted grep, jq, sed or cat
  (each alone, and all together) let every must-block command through on both tools. The
  structural checks (one marked PATH line, system directories only) failed too.
- **Green after:** 54 passed, 0 failed.
- **Control:** with the seam disabled in hook-fail-closed.test.py, 18 fault-injection checks fail.
  The shims no longer reach the live hook, which shows the pin holds and the seam is what the tests
  use.
- **No regressions:** hook-fail-closed.test.py all passed, now through the copy. The bypass corpus
  ran 224 entries and 804 hook runs, 0 failed, in both jq and no-jq modes, now through the copy.
  selftest passed 305 / 0 against the live pinned hook. `./keel check` is green in a capped
  python:3.12-slim container. shellcheck v0.10.0 `-S warning` is clean. Pinned gitleaks v8.18.4
  reports no leaks.

## Not verified

- **Git Bash on Windows was NOT run.** This laptop is Linux. The msys branch rests on Git for
  Windows' layout: `/usr/bin` holds grep, sed, gawk, tr, cat, head, mktemp and rm, and `/bin` is
  the same directory. It needs one run of selftest.sh, hook-path-pinned.test.py and the corpus on
  the Windows host.
- **A per-user Git for Windows install** (under %LOCALAPPDATA%) makes `/usr/bin` user-writable
  there. The pin cannot help in that case.
- The `bash` that settings.json starts is still found on Claude Code's PATH. A planted bash is
  outside what a hook can defend against.

## Residual risk accepted

The three items above.
