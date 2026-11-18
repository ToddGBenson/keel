# Self-review — TheHub #62022 (the evidence rule reads a path in any spelling)

Mode: solo (POAM-008); agent self-review, pending the independent review before merge
PR: (set when opened)   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-18
verdict: pass

guard-write.sh's evidence rule (AU-9) matched `*/evidence/*` and `evidence/*` on the path as
written: forward slashes, lower case. On Windows a path takes backslashes and its case is ignored,
so `evidence\142\g4\scan.sarif`, `C:\repo\evidence\...` and `Evidence/142/...` are the same
generated-evidence files, and every write tool wrote them unchecked. The rule predates the hook
sprint.

## The change

- **One normalised spelling.** The path is judged as `npath`: backslashes become slashes, case is
  lowered, repeated slashes and `./` segments collapse, and a leading `./` is dropped.
- **Lower-casing uses `tr`**, through a new wrapper so a failing `tr` is a fault, not `${x,,}`. bash
  3.2 (macOS) has no `${x,,}`, and the hook would crash there, refusing every write.
- **The high-consequence notices** (workflows, hooks, gates, compliance) read the same spelling.
- test/hook-write-fail-closed.test.py lists `tr` among the tools the hook runs.

## Verified independently

- **Red first:** 8 new selftest cases against main bd2ef2f's guard-write.sh. Of the 5 must-block
  cases, 4 were ALLOWED: backslashes, a Windows drive path, `Evidence/`, and `EVIDENCE/`. The `./`
  and `//` case was already blocked, because `*/evidence/*` matched it. The 3 must-allow cases passed:
  a backslashed `.md`, a capitalised `.MD`, and `docs/evidence-model.md`.
- **Green after:** selftest 338 passed / 0 failed. hook-write-fail-closed all passed. Bypass corpus
  224 entries, 804 runs, 0 failed.
- `./keel check` green in a capped python:3.12-slim container. shellcheck v0.10.0 `-S warning`
  clean. Pinned gitleaks v8.18.4: no leaks.

## Not verified

- Git Bash on Windows was not run. A Windows path reaches the hook as the tool sends it. The
  normalisation does not depend on the shell.
- Not covered: an 8.3 short name (`EVIDE~1`), a path through a symlink or junction, and a `..` that
  climbs back into evidence/ from outside (`src/../evidence/x`). That last one already contains
  `/evidence/`, so it is caught. NotebookEdit and MultiEdit reach this rule once #195 is on main; it
  reads the same `path`.

## Residual risk accepted

8.3 short names and links, as above. CI evidence integrity checks remain the authoritative control.
