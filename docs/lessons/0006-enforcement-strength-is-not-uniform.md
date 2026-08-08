# L0006: State enforcement strength honestly, per control

**Date:** 2026-08-07 · **Source:** platform build · **Class:** promotable
**Applies to:** any control catalog, SSP, or compliance claim
**Landed as:** the AIC-3 enforcement table · `ai-inventory.md` § enforcement status · POAM-001

## What happened

The AI inventory stated that certain agents "cannot write source." Investigation showed the
agent framework grants tool *types*, not path scopes; project permissions are not per-agent;
and the hook payload carries no agent identity.

The boundary was real as an instruction and absent as a control. The document implied
otherwise — and the document is what an assessor reads.

## The rule

Controls are not equally strong. Record which layer enforces each one:

```
prompt / instruction   advisory      a confused or adversarial actor ignores it
tool grant             structural    the capability is simply absent
hook / CI              enforced      blocked at the point of action
server-side policy     enforced      outside the actor's reach entirely
```

Where a control is advisory, **say so**, name the compensating detection, and open a POA&M
entry with a review date.

## Why it matters more than it looks

A documented weak control is defensible at assessment. An overstated one is a finding — and
it takes down credibility on every control in the same document, including the ones that were
real. You do not get graded per row; you get graded on whether the document can be trusted.

## How you would know you hit this

Your control map has no gradations: everything is "implemented." Ask of any row: **what would
happen if the actor simply ignored this?** If the answer is "nothing stops them," it is
advisory, and the map should say so.
