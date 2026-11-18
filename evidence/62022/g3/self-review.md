# Self-review — TheHub #62022 (the evidence rule reads a path in any spelling)

Mode: solo (POAM-008); agent self-review, pending the independent review before merge
PR: #197   Pair: binnacle #91   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-18
verdict: pass

guard-write.sh's evidence rule (AU-9) matched `*/evidence/*` and `evidence/*` on the path as
written: forward slashes, lower case. On Windows a path takes backslashes and its case is ignored,
so `evidence\142\g4\scan.sarif`, `C:\repo\evidence\...` and `Evidence/142/...` are the same
generated-evidence files, and every write tool wrote them unchecked. The rule predates the hook
sprint.

## The change

- **One normalised path, rebuilt segment by segment with builtins only:**
  - backslashes become slashes;
  - a relative path is joined to the payload's `cwd`;
  - a drive-relative `C:` prefix is dropped;
  - per segment, everything from the first `:` is dropped (an NTFS stream such as `::$INDEX_ALLOCATION`
    or `:$I30`), trailing dots and spaces are trimmed, `.` is skipped and `..` is resolved.
- **Case is ignored by the matches** (`shopt -s nocasematch`, bash 3.1 and later) rather than by
  rewriting the path. No external tool is involved, so a planted `tr` or other helper cannot change
  the answer. This replaces round 0's `tr` wrapper (review findings 5 and 6).
- **The high-consequence notices** read the same path, so a relative `.github/workflows/...` now
  gets its notice too.
- **The payload's `cwd`** is read by both parsers (jq and python).

## Verified independently

- **Red first, round 0:** of the first 8 cases, 4 failed against main bd2ef2f. Backslashes, a Windows
  drive path, `Evidence/` and `EVIDENCE/` were ALLOWED.
- **Red first, round 1** (review of #197/#91; the exact inputs are in the binnacle comment): 10 more
  cases against the reviewed head a04095b. 8 failed. These were ALLOWED: drive-relative
  `C:evidence\...`, `evidence::$INDEX_ALLOCATION/...`, `evidence:$I30:$INDEX_ALLOCATION/...`, a trailing
  dot, a trailing space, a relative path from a cwd inside `evidence/`, and the same with a Windows cwd
  `C:\repo\Evidence`. And `evidence/../src/a.py` was falsely blocked.
- **Red first, round 2** (review of 9902cd6/42af695; the exact inputs are in the binnacle comment): 8 more
  cases against 9902cd6 gave 350 passed and 6 failed. These were ALLOWED: `evidence/.../../142/a.sarif`,
  the `.. ` and `..:x` forms (a segment that only became `..` after trimming popped `evidence`), a
  `...` segment under evidence, a named stream `a.md:x.sarif`, and a path with a line feed. The
  review's 21 inputs, run against this head: 0 wrong.
- **The round-2 change:**
  - `.` and `..` are judged on the raw segment, before any trimming, and a segment that only
    becomes empty, `.` or `..` after trimming is refused.
  - A line feed or carriage return in the path or the cwd is refused.
  - Only a stream TYPE suffix (one with `$`) is stripped, and a named stream inside evidence/ is
    refused.
  - Empty-array expansions are guarded for bash older than 4.4 under `set -u`.
- **Green after:** selftest 356 passed / 0 failed (round 1: 348). hook-write-fail-closed all passed. Bypass corpus
  224 entries, 804 runs, 0 failed.
- `./keel check` green in a capped python:3.12-slim container. shellcheck v0.10.0 `-S warning`
  clean. Pinned gitleaks v8.18.4: no leaks.

## Not verified

- Git Bash on Windows was not run here. The review ran round 0 there and confirmed each blocked
  spelling resolves to the same file through Node's `fs.statSync`.
- **Corrected "not covered" note** (review finding 7): `evidence` is eight characters, so it has no
  8.3 alias. The round-0 note was wrong. The real gaps of round 0 were the spellings above, which
  this round closes.
- **Still not covered:**
  - a path through a symlink or junction into evidence/;
  - a `cwd` that the payload does not carry (the path is judged as given);
  - a relative path when the agent has `cd`ed and the payload's cwd is stale.
- NotebookEdit and MultiEdit paths reach this rule through `notebook_path` once #195/#89 is on main.
  Until then those paths are not read. selftest.sh conflicts with #195/#89, so whichever merges
  second rebases.
- **The false positive is wider, in the safe direction:** `Evidence/` anywhere on disk is treated as
  evidence, including on case-sensitive Linux, where it is a different directory.

## Residual risk accepted

8.3 short names and links, as above. CI evidence integrity checks remain the authoritative control.
