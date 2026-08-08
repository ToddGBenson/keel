---
description: Independent multi-agent review of a PR for solo operators, producing the evidence artifact that replaces a second reviewer's approval
argument-hint: <PR number or issue number>
allowed-tools: Read, Grep, Glob, Bash, Task, Write
---

# Self-review: `$ARGUMENTS`

The solo-operator substitute for a second reviewer. Produces
`evidence/<issue>/g3/self-review.md`, which `pr-governance.yml` requires before a PR with no
approving review can merge.

**Read `docs/13-solo-operation.md` first.** This is a compensating control for a declared gap
(POAM-008), not an equivalent to independent human review. Treating it as equivalent is the
mistake this whole document exists to prevent.

## The independence rule

Spawn **fresh agent invocations** that have not seen the implementation reasoning. Pass them
only:

- the diff
- the story and its acceptance criteria
- the threat model and control allocation, if G2 ran

Do **not** pass the implementation rationale, your notes, or the reasoning that produced the
code. The entire value is reasoning uncorrelated with the author's. An agent told *why* the
code is right will confirm that it is right.

## Run three passes, in parallel

Different lenses, because a single reviewer — human or agent — has one blind spot and
applies it consistently.

**1. `developer` — correctness and maintainability.** Load `secure-code-review`. Does it do
what the AC says, including the paths the happy case does not exercise? Watch for the
plausible-but-wrong catalogue: inverted conditions, off-by-one at a boundary, a `catch` that
swallows, authorization on the route rather than the object.

**2. `security-engineer` — controls and failure behaviour.** Load `control-verification`.
Every control the threat model allocated: find it in the code, find its negative-case test,
read it adversarially. Then: what happens when the dependency is slow rather than down, when
two requests race, when the input is hostile?

**3. `qa-engineer` — test quality.** Load `test-strategy`. Mentally delete the
implementation — which tests fail? If a plausible bug leaves them green, the tests are
decorative and they inflate coverage.

Where the change is AI-relevant, add **`ai-risk-officer`** with `eval-design`.

## Then read it yourself, cold

**After the agents, and after a break.** The agents find mechanical defects well. They find
*misunderstood requirements* poorly, because they read the same requirement you did.

Ask the two questions only you can:

- **Did I build what was actually asked for**, or what I decided it meant on Tuesday?
- **What did I not want to look at?** There is usually one thing. Look at it.

## The artifact

Write `evidence/<issue>/g3/self-review.md`:

```markdown
# Self-review — #142

Mode: solo (POAM-008)
PR: #17   Author: <you>   Date: 2026-08-09
Opened: 2026-08-08 16:40   Reviewed: 2026-08-09 09:15   Cooling-off: 16h ✅

## Verified independently
- AC-1..3 traced to tests; confirmed each goes red with the implementation stubbed
- AC-3 authz at DraftAuthorizer:47; negative test api_test:212; export path at
  export.py:23 also routes through it (checked — it did not in the first draft)
- CI run #4821 read, not just green-badged: 142 passed, coverage 84% (+1)

## Agent findings
- developer:         1 minor (naming), 0 correctness
- security-engineer: 1 MEDIUM — quota check non-transactional, drafts.py:88 → fixed in a1b2c3d
- qa-engineer:       flagged test_quota_eviction asserts ordering, not behaviour → rewritten

## Not verified
- Performance NFR — no load environment. UNVERIFIED, not passed.

## Cold-read notes
- Re-read AC-2. "Declining discards permanently" — I implemented a soft delete.
  That is not what it says. Filed #23; this PR does not claim AC-2.

## Residual risk accepted
- Single-identity review. No independent human read this diff.
  Next external sample review due: 2026-10-01.
```

The **"Not verified"** and **"Cold-read notes"** sections are what make the rest credible. A
self-review with nothing in either is a self-review that did not happen — you are not that
good, and neither is anyone else.

## Rules

- **Never write that you verified something you did not.** In solo mode there is nobody to
  catch it, which makes it more important, not less.
- **"Unverified" is a valid and expected outcome.** Say it.
- **If the agents find nothing at all**, be suspicious of the setup rather than pleased —
  usually the diff was passed without its context, or the charter was too narrow.
- **Do not run this in the same session you wrote the code.** The cooling-off period is part
  of the control, and `pr-governance.yml` records the interval.

## Then

Merge via GitHub. Required status checks still block; `enforce_admins` is still on. The only
control relaxed in solo mode is the approval count — everything else that would have stopped
a bad change still stops it.
