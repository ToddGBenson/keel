# Self-review — #67

Mode: solo (POAM-008)
PR: #68   Author: Todd Benson (claude-opus-5, AI-authored)   Date: 2026-08-15
Stacked on #66 (`feat/65-agentic-sdlc-spec`) — both touch `poam.md` and the control map.

Recording that 14 controls were marked satisfied on gates that have never run, and building the
check that would have caught it.

## Verified independently

- **The finding is a measurement, not a characterisation.** I had called this a "character
  weakness" in conversation. Counting `evidence/*/g<n>` gave the real shape: **G3 has 12 records
  and every other gate has zero.** The phrase was vague; the number is not, and it is worse.
- **The 14 rows were read before being downgraded**, not pattern-matched blindly. Two cite
  evidence paths that provably do not exist — SA-11 points at `evidence/<issue>/g4/` (zero such
  directories) and CP-10 at G5 rollback rehearsal records. Every one of the 14 rests on G1, G2,
  G4 or G5.
- **The check was made to fail, twice, before it was committed** — the exact discipline whose
  absence is the finding:
  - re-marked SA-11(2) satisfied on a dead gate → exit 1, naming the control
  - moved `evidence/` aside so G3 went dark → exit 1, naming G3 and its previous count
  - restored both → exit 0
- **My own manifest validator caught my new file.** `.control-liveness.json` was flagged as
  ungoverned on the first run after `git add`. That is yesterday's fix (#58) working on today's
  change, and it is the only thing in this session that has now caught a real defect twice.
- All validators pass; `platform-integrity.sh` parses.

## Agent findings

**None — no three-pass agent review.** Consistent with every PR since #48.

**If one thing gets an independent read, make it the decision to downgrade all 14 rather than
some.** A case could be made that SA-15 or PL-8 are partly satisfied by artefacts that exist
outside the gates. I judged that any row whose *stated* justification is a gate that never ran is
overstated as written — but that is a judgement about what a control map claims, and someone
could reasonably draw the line differently.

## Not verified

- **The liveness check measures gates, not checks.** It counts evidence directories. It does not
  know whether `sast` has ever failed, whether the PR gate has ever rejected anything, or that
  `container-scan`, `release-preflight` and `authorize-release` have zero builds — those three
  were measured **by hand** for this PR and are not covered by the automated check. The most
  important number in the finding is the one the tool does not yet collect.
- **The staleness detector has never fired**, and cannot for 120 days. It is the same class of
  unexercised control this PR is about, introduced by this PR. I could not think of an honest way
  to test it without faking a commit date, and I would rather record that than pretend.
- **Nothing here makes a dead gate live.** POAM-018 says so in its own remediation section: only
  giving keel a real workload does that, and this PR does not.
- **The regression tests were run by hand, not written as tests.** There is no
  `test/control-liveness.test.py`. The evidence they happened is this record and the terminal
  output, which is exactly the weaker form of evidence keel's own G4 criteria would reject.

## Cold-read notes

- **What I did not want to look at:** yesterday I added UX criteria to G1 and G2 and approval
  authority across all six gates. **Five of those gates have never run.** I spent a day
  elaborating machinery that has never been switched on, and I only noticed because I was asked
  a direct question about a phrase I had used. Nothing in the process surfaced it — the change
  passed every check, because every check measured existence.
- **The pattern behind the pattern.** POAM-017's compensating controls are all detective. So is
  this one. Detective controls can be written without a workload; preventive controls need
  something to prevent. keel keeps producing the former because it has nothing to do — that is
  the same root cause wearing a different hat, and I think it is the most useful sentence in
  this PR.
- **This check could become the thing it detects.** It is a control about controls, and if the
  baseline is updated reflexively whenever it complains, it degrades into a file that records
  whatever happened. The staleness rule is the only defence I built, and it is weak.
- **The honest framing of this whole PR:** it makes an absence visible and stops it growing. It
  does not reduce it. A reader should not come away thinking the problem is addressed.

## Correction made before merge

The system owner read the remediation and asked: *if this repository becomes a project, what is
the baseline for the next project?* There would not be one. **POAM-018's first remediation —
"give keel a real workload" — would have destroyed the template**, and I had already written the
principle that forbids it: ADR-0004 §D3, "inert lanes are inherited, not dead", one day earlier.
I applied it to pipeline lanes and not to gates.

Corrected in this PR: the remediation is now scope-the-claim plus prove-it-in-a-reference-fork,
the control map carries a provided-here/demonstrated-downstream scope note, and L0017 records the
class. The 14 downgrades are unchanged — a claim citing a directory that does not exist is false
whoever's gates ought to fire.

**Recording the sequence rather than the conclusion**, because the conclusion looks like
foresight and it was not: I wrote a fix that would have cost more than the finding, and it was
caught by a question, not by any check in this repository.

## Residual risk accepted

- 14 control claims downgraded; the underlying gates remain unexercised.
- The liveness check covers gates only, and its own staleness rule is untested.
- Hand-run regression tests, not automated ones.
- Next external sample review due: 2026-10-01.
