# Self-review — #70

Mode: solo (POAM-008)
PR: #71   Author: Todd Benson (claude-opus-5, AI-authored)   Date: 2026-08-15

Making the fork path actually work, in response to "get it in a state to start a fork of a new
app". Two day-one defects, both found by running `scripts/bootstrap.sh` for the first time.

## Verified independently

- **Every finding came from execution, not from reading.** I read the script first and spotted
  the missing evidence clear. I did **not** spot that `.bootstrapped` and `docs/PLATFORM.md`
  break the manifest validator — that only appeared when a bootstrapped fork ran its own checks.
  Reading found one of two defects; running found both in four minutes.
- **The fix was verified by re-running the whole path end to end, twice**, in fresh clones:
  - before: 14 evidence dirs, `G3: 13 records, ever fired: yes`, 2 manifest errors
  - after: 0 evidence dirs, all six gates `NEVER`, all three validators pass
- **The first re-test failed to prove anything and I noticed why.** I cloned a branch whose fix
  was still uncommitted, so the clone carried the old script and the output was unchanged. That
  is the same class as the merge-strand: I nearly accepted "no change observed" as "no effect",
  when it meant "the change was not there".
- **keel's own manifest validator still passes** after adding two `project_owned` entries that
  do not exist upstream — confirmed, since a wrong bucket would have made keel itself red.

## Agent findings

**None — no three-pass agent review.** Consistent with every PR since #48.

**If one thing gets an independent read, make it the ADR handling.** I moved keel's five ADRs
to `docs/adr/platform/` rather than deleting them. A reviewer might argue a fork should not
carry the platform's architectural history at all, or conversely that ADR-0005 (gate authority)
is so load-bearing it should stay in the fork's own `docs/adr/`.

## Not verified

- **The bootstrapped fork was never pushed to GitHub, so nothing exercised its gates, its
  Actions workflows, or `configure-github.sh`.** I proved a fork starts *clean*; I did not prove
  it *works*. The G0–G5 question POAM-018 raises is untouched by this PR.
- **Only the `python` stack was tested.** Bootstrap splices stack-specific commands into the
  workflows; the other profiles are unexercised.
- **`sync-platform.sh` is still unrun.** A fork's ability to *receive updates* remains unproven —
  now the only major unexercised mechanism in the fork lifecycle, and the more important half,
  since bootstrap happens once and sync happens forever.
- **I did not check what a fork inherits beyond the files I looked for.** I measured evidence,
  ledgers, ADRs and lessons because I suspected those. Something else may still carry over; the
  method was targeted inspection, not an exhaustive diff against a clean project.

## Cold-read notes

- **What I did not want to look at:** the missing evidence-clear is my defect from earlier
  today. I added `.control-liveness.json` and `.merge-reconciled.json` and wrote MANIFEST
  comments explaining that a fork must not inherit them — *and then did not make bootstrap
  delete them*. I documented the hazard and shipped it anyway, which is worse than not noticing,
  because the comment reads as though it was handled.
- **Two existing lessons predicted both defects.** L0016: the header claimed evidence was
  cleared while the code cleared the POA&M — a claim answering a different question than the
  code. L0011: unexecuted code is a plan. Both were written in this repository, by me, days ago.
  I did not add a nineteenth lesson, because the failure is not a missing lesson.
- **The most valuable four minutes in this session were spent running a script instead of
  reading it.** Every unexercised mechanism I have flagged — sync, release lanes, gates — was
  flagged from reading. This one was resolved by execution, and the payoff was a defect that
  reading could not have surfaced.

## Residual risk accepted

- The fork path is proven to start clean, not to work end to end.
- One stack profile of several tested; `sync-platform.sh` still unexercised.
- Next external sample review due: 2026-10-01.
