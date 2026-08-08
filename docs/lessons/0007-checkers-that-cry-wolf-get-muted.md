# L0007: A checker with false positives gets muted

**Date:** 2026-08-07 · **Source:** platform build · **Class:** promotable
**Applies to:** linters, validators, CI gates, any automated reporter
**Landed as:** comments in `scripts/validate-platform.py` · GP-5

## What happened

The platform validator's first run reported seven failures. Five were a normalisation
mismatch — the inventory used the shorthand `Web` while agent frontmatter spelled out
`WebSearch` / `WebFetch`. Two were commented-out example lines in a workflow being read as
real unpinned actions.

**Zero were real.** Had it shipped that way, the natural response would have been to stop
reading its output — and the first genuine drift it caught would have gone unnoticed.

## The rule

A checker's false-positive rate is not cosmetic; it determines whether the checker functions
at all.

- **Skip comments.** Documentation showing a bad pattern is not the bad pattern.
- **Normalise both sides** before comparing. Shorthand in one source and full names in
  another is drift in the checker, not in the system.
- **Fix false positives before adding coverage.** A narrow checker people read beats a broad
  one they ignore.

## How you would know you hit this

People can tell you what your checker complains about *and* why it doesn't matter. That
fluency is the sound of a control that has stopped being one.

## Related

Same root as the fail-on-new-not-total decision in the security pipeline: gating on absolute
finding counts makes the pipeline permanently red, and permanently red is operationally
indistinguishable from off.
