# L0005: Test the control; reading it finds nothing

**Date:** 2026-08-07 · **Source:** platform build · **Class:** promotable
**Applies to:** every control, every assessment
**Landed as:** GP-5 · the `control-assessment` skill · `.claude/hooks/selftest.sh` (25 assertions)

## What happened

Four defects (L0001–L0003, L0008) existed in guard hooks that had been written carefully,
reviewed, and documented accurately in the control map. **All four were invisible on
reading. All four surfaced within minutes of actually using the control.**

One — the High-severity one — meant the guard blocked the *removal* of a secret. It sat in
the repo, described as working, for the entire build.

## The rule

SP 800-53A offers examine / interview / **test**. Test beats examine, always, where testing is
possible. For anything gate-shaped, testing means attempting the thing the control should
block and confirming it blocks.

Then the half everyone skips: **also test that it does not over-block.** A guard with false
positives gets bypassed, and a bypassed control still shows green.

## How you would know you hit this

Your controls have never been observed blocking anything. Nobody can point at the moment one
fired.

## Practice

`.claude/hooks/selftest.sh` — 25 assertions: 15 prove blocking, 10 prove legitimate work
passes, six of them named regression tests for L0001–L0003 and L0008. Runs in CI on every PR
and at quarterly assessment.

Any control worth having is worth a test that proves it works. **If writing that test is
hard, that is information about the control** — usually that its trigger condition is not as
crisp as the documentation implies.
