# L0018: "Merged" is not "landed"

**Date:** 2026-08-15 · **Source:** #69 · **Class:** promotable
**Applies to:** any repo using squash merges, and any repo where PRs are ever stacked
**Landed as:** `scripts/validate-merges.py` · a step in `pr-governance.yml`

## What happened

Two pull requests, one stacked on the other:

```
#66 merged to main   05:16:09Z   (squash)
#68 merged           05:16:48Z   -> into feat/65-..., 39 seconds too late
```

A **squash** merge creates a *new* commit on the default branch. The source branch is not
merged into anything — it is summarised and abandoned. So the moment #66 landed, its branch
stopped leading anywhere, and #68 — whose base *was* that branch — merged into a dead end.

**490 lines across 8 files never reached `main`.** Both pull requests showed **merged**. Every
required check was **green**. The branch protection rules all held. Nothing was broken; the
content simply was not there.

It was found because someone asked an unrelated question about the CI pipeline, three hours
later. Nothing in the repository would have surfaced it.

## Why it matters

Every check in that repository verified that things were **correct**. None verified that they
were **there**.

That gap is invisible by construction: a check runs against the code in front of it, so code
that is absent is code no check will ever examine. The absence is not a failing test — it is the
*silence* of a test that was never invited. And "merged" is the single strongest signal a
reviewer has that work is done, which is exactly what makes it dangerous when it is wrong.

The generalisation is the uncomfortable part: **a green pipeline says nothing about work that
never entered it.** Coverage, gates, scanners, approvals — all of them measure the diff you gave
them.

## The rule

**Verify arrival, not just approval.**

- **Ask the forge which commit a merge produced, and whether that commit is on the branch.** This
  is authoritative. Do not match `(#N)` in commit subjects — the first version of this check did
  and flagged five healthy PRs whose merge method never wrote the number, which is how a checker
  earns being muted (see [[0007-checkers-that-cry-wolf-get-muted]]).
- **Treat a merged PR whose base is not the default branch as a finding by default.** It is
  sometimes legitimate; it is always worth a sentence explaining why.
- **When stacking PRs under squash merges, re-target the child to the default branch *before*
  the parent merges.** Not after — after is too late, and there is no error to tell you so.
- **Reconcile, do not suppress.** A strand that a later PR genuinely re-landed should stop being
  reported, with a record naming the PR that carried it. That record is also the audit trail
  showing somebody checked rather than silenced it.

## Related

- [[0007-checkers-that-cry-wolf-get-muted]] — the first cut of this check flagged five healthy
  PRs; fixing the heuristic mattered more than shipping it
- [[0016-a-check-answers-the-question-it-asks]] — same family: the summary line claimed something
  the loop did not check
- [[0011-unexecuted-code-is-a-plan]] — code that never landed is the limiting case
