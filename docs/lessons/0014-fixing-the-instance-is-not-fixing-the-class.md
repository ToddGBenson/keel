# L0014: Fixing the instance is not fixing the class

**Date:** 2026-08-13 · **Source:** #44 / #46 · **Class:** promotable
**Applies to:** any predicate that stands in for a control — validators, gate checks, allowlists
**Landed as:** the header of `scripts/selfreview-check.js` · `test/selfreview-check.test.js`

## What happened

The solo-mode self-review check is the compensating control for POAM-008. With
`required_approving_review_count` at 0 it is the *entire* substitute for a second reviewer.

It was bypassed four times. Each fix closed the reported hole and left the identical shape
one level over:

1. It tested for a `## Self-review` **heading**. The PR template instructs authors to write
   that heading, so the default path through the process satisfied the control before any
   review existed.
2. Fixed to require a **record**. It then accepted *any* `evidence/**/self-review.md`. The
   pull request introducing that fix **passed its own check**, because its body cited another
   issue's record in a sentence explaining how the check had been tested.
3. Fixed to require **this issue's** record. It then took the first *linked* issue, and
   `Refs: #42` sits above `Closes #44` in nearly every body in this repository — so #42's
   genuine record satisfied a PR closing #44.
4. Fixed to prefer closing keywords. `path.normalize` then `.replace(/\\/g,'/')` left `..\`
   intact on Linux and manufactured live `../` *after* normalisation, so
   `evidence/44/..\42\g3\self-review.md` read #42's record and passed — and could escape the
   checkout entirely.

Two more were latent in the same fix: two `Closes #n` in one body silently bound to the
first, and the length floor spanned newlines so twenty-one `- x` bullets counted as substance.

## Why it happened

Each fix was aimed at the *reported input*. The question asked was "does this string still
get through?" — never "what **other** string satisfies my new predicate without the work
having happened?"

That second question is the whole of it. A control is a predicate standing in for a fact.
Every fix narrows the predicate; the class is the gap that remains between the predicate and
the fact. Narrowing without re-deriving the gap just relocates it.

The failure compounds under agentic authorship, because the author writes a confident commit
message asserting the class is closed. Three of these shipped with exactly that claim.

## The rule

**After fixing a control, do not ask whether the reported input is blocked. Ask what else
satisfies the new predicate without the work having happened — and write that down as a test
before you believe the answer.**

Two practices make it concrete:

- **Attack it, do not re-read it.** Bypasses 3, 5 and 6 were found by trying to defeat the
  check. Bypasses 2 and 4 were found by independent review. *None* were found by re-reading.
- **Verify on the platform it runs on.** Bypass 4 was invisible on Windows, where
  `path.normalize` collapses `..\`, and live on the Linux runner. A check tested only where
  it is developed is untested.

## Counter-rule

Do not read this as "predicates are hopeless, require a human". The check is a *shape check*
and cannot be more — ninety seconds of writing passes it. What it buys is that the deceit now
requires committing a file that appears in the diff, in git history, under a name stating
what it claims to be. That is a real gain over a markdown heading, and it is not the same as
"the control is enforced". Say which one you have.
