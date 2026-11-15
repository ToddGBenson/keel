# Self-review — TheHub #60978 (keel PR #163)

Mode: solo (POAM-008). Written under the operator decision of 2026-11-04: the agent that
builds a binnacle or keel pull request writes its self-review record. MyKronos
`independent-review`, which this PR makes keel's merge gate, does not replace this record.
PR: #163   Head reviewed: edfbeb2   Date: 2026-11-04
Author: Claude Opus 5.5 builder session (AI-authored). Record written by Claude Opus 5.5 in a
later session that did not write the change, reading the diff cold.
Opened: 2026-11-04T02:23Z   Reviewed: 2026-11-04T03:40Z   Cooling-off: about 1h (short; do not merge on this record alone)
verdict: pass

## Verified independently

- Read the whole `scripts/configure-github.sh` diff and every doc hunk in OPERATING.md and `docs/compliance/poam.md`. Step 5 now requires `independent-review` pinned to an App id (default 4551328), `strict` off; step 4 keeps existing `checks` with their app ids; step 6 verifies the pin, not just the name.
- The script refuses the GitHub Actions App by id (15368) and by slug, and refuses an App that has not posted a check run on the default branch head or one of the five newest open PR heads.
- `--checks-only` on an unprotected-checks branch falls back to a full PUT built from the protection read back (`put_from_current`), which carries `enforce_admins`, the review settings and linear history unchanged.
- The `--dry-run` path no longer sends the `required_signatures` DELETE; it prints instead.
- Live keel protection on 2026-11-04 matches what the docs now say: no required status checks, `enforce_admins` off, one approving review.

## Agent findings

- No three-pass agent review was run for this record. The PO workflow reviewer's two comments are the independent read: "fix before merge" on 9496c64, then "ship with follow-ups" on edfbeb2 after the fixes.

## Not verified

- I did not run `test/configure-github.test.py` (about 5 minutes on Windows). The 35/35 green and the 28-of-35 red on main are the builder's and the reviewer's results, UNVERIFIED by me.
- The gate itself is UNVERIFIED: it is not applied until the operator runs the script, and no PR has yet been seen blocked on `independent-review` and then merged on an approval.

## Cold-read notes

- DEFECT, low, doc, still on this head: the new `ci/README.md` box says keel "has no consumer" of `scripts/selfreview-check.js` or `test/selfreview-check.test.js`. The test has one: `test/manifest.txt` lists it and `.github/workflows/unit-results.yml` runs every `test/*.test.js` on pull requests. Only the script lacks a keel consumer.
- OPERATING.md, which this PR edits, still says at "No self-approval" that `/self-review` is "the compensating artifact CI requires". In keel no CI check requires it now (PR Governance is retired). Under the 2026-11-04 decision the record is still required, written by the building agent, and read by reviewers, so the sentence should say that instead of naming CI.
- `--solo` turns `enforce_admins` on. The agents push as the owner's account, so without it an admin merge bypasses the new gate; with it, an operator emergency merge also needs the gate. The PR body says this; it is a real trade-off for the operator, not a defect.

## Residual risk accepted

- Same model family and the same GitHub identity as the builder. This is a self-review, not independent review, and it is not an approval.
