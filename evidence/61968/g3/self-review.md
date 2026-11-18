# Self-review — TheHub #61968 (self-review follow-ups from the #183 review)

Mode: solo (POAM-008); agent self-review per the operator's 2026-11-04 decision
PR: #193   Author: Claude Sonnet 5.5 (builder agent, AI-authored)   Date: 2026-11-17
verdict: pass
Opened: 2026-11-17   Reviewed: 2026-11-17 (same session; no interval, see "Not verified")

Docs and text only. `scripts/sprint.sh`, `SECURITY.md`, the self-hosted-runner runbook,
`.claude/commands/self-review.md` and the PR template are corrected, and
`test/self-review-docs.test.py` pins them.

Scope change (PO decision): this PR must stay low-risk, so it does not touch compliance records or
the branch-protection script. The CIS map (`docs/compliance/cis-supply-chain-map.md`), the POAM-008
control table (`docs/compliance/poam.md`) and the `configure-github.sh` info line were moved out to
TheHub story 62001 and reverted here to main's content. `test/self-review-docs.test.py` excludes
exactly those three paths by name (a comment cites #62001) from the CI-required check; every other
check is unchanged. Those three files still carry the CI-required wording until 62001 lands.

## Verified independently

- **Which script reads what, read in code:** `scripts/selfreview-check.js` tests the record for
  `\bPR:?\s*#<n>\b` and the two sections; `grep -i verdict` on it returns nothing.
  `scripts/control-liveness.py` defines `VERDICT_RE` (`^\s*verdict:\s*(pass|fail)\s*$`) and
  `is_record()` uses it. `self-review.md` now says exactly that.
- **Template rules, read in code:** `closingIssues()` matches `\b(closes|fixes|resolves)\b\s*:?\s*#n`,
  so `Fixed`/`Closed`/`Resolved` do not close; `linkedIssue()` falls to
  `\brefs?\b\s*:?\s*#n` (case-insensitive); `resolveRecordPath()` needs the body to contain the
  `evidence/<n>/.../self-review.md` path. The template says that.
- **`pr-governance.yml` is `workflow_dispatch`-only** (banner at the top of the file, retired
  2026-10-20, TheHub #60849); the CI-required wording was false.
- **Red first:** the test was committed alone (910b0f7) and run on that tree: exit 1, 13 failed.
  After the fix commit: exit 0.
- **Whole-tree grep** (`git grep` for `/self-review`, `run.*self-review`, and `required|enforc|blocks`
  near it, outside `evidence/`): the remaining hits are the "operator does not run it" rule text,
  dated historical POAM notes, `docs/13` (policy "required", not CI), and the one item below.
- **sprint.sh is text only:** `git diff -w` shows changes inside the heredoc and the printf format
  string; no `%s` added or removed, argument list untouched, `bash -n` exit 0.
- **Checks, all exit 0:** the test list and exit codes are in the PR body.

## Agent findings

None. No three-pass agent review was run; this record is the builder's own, and the PR needs the
independent review the Definition of Done asks for.

## Not verified

- `scripts/selfreview-check.js:179` still prints "Run `/self-review N`" in a failure message. I left
  it: it is addressed to the PR author, it is logic-file text with tests, and the story limited
  script edits to `sprint.sh`. Reported, not fixed.
- `test/hook-bypass-corpus.test.py` mentions `self-review.md` only in a comment about an evidence
  path and is slow; no hook changed. I started it and did not wait for it. Unverified.
- The cooling-off interval: this record was written in the session that built the change.
- binnacle receives these files through the platform sync; not run or inspected here.

## Cold-read notes

- An earlier head also edited the CIS map, the POAM-008 table row and the `configure-github.sh` info
  line. Those are out of this PR now (TheHub 62001); the test excludes the three paths by name, so
  it does not guard them here.
- The test is a phrase blocklist; a new phrasing of the same claim will pass. It pins the shapes
  found today, nothing more.

## Residual risk accepted

- Single-identity review. No independent human read this diff.
