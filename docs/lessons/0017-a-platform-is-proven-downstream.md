# L0017: A platform's controls are proven downstream, not in itself

**Date:** 2026-08-15 · **Source:** #67 · **Class:** promotable
**Applies to:** any repo that ships a framework, template, library, or shared pipeline
**Landed as:** the scope note in `nist-800-53-control-map.md` · POAM-018's corrected remediation

## What happened

A liveness check found that five of six gates in this repository had **never produced a single
evidence record**, and that fourteen compliance controls were marked satisfied on those gates.
The finding was real and the downgrades were right.

The **remediation** was wrong: *"give keel a real workload — run one genuine story through
G0→G5."*

The system owner asked the question that broke it: *if this repository becomes a project, what is
the baseline for the next project?* There would not be one. Putting product code into a template
is not a workload; it is the end of the template. **The proposed fix cost more than the finding.**

And the correct principle was already written down, one day earlier, in this repository's own
ADR:

> **Inert lanes are inherited, not dead.** A lane that does nothing here is what a fork gets on
> the day it first ships an image.

`container-scan` is inert because the template has no image, and that was argued as *the point*.
Gates G2 and G4 are inert for the same reason — no product to design, no system to verify. The
reasoning was applied to pipeline lanes and not to gates twenty-four hours later, by the author
of the lesson about fixing the class rather than the instance.

## Why it matters

A template that exercises its own machinery has stopped being a template. But a template that
*claims* compliance it has never demonstrated is worse — that is documented false assurance.

Both failures come from asking one question where there are two:

| Question | Answered by |
|---|---|
| Does the mechanism exist and work? | the platform |
| Has it been exercised against real risk? | the adopting project |

Conflating them produces one of two errors, and which one you get is arbitrary. Either you fill
the template with a product to make the numbers move, or you inherit an assessment full of green
ticks nobody has earned.

## The rule

**Ship the mechanism; scope the claim; prove it downstream.**

- **Say which controls are provided versus demonstrated.** "Provided by the platform,
  demonstrated in the adopting project" is a complete and honest status. It is not a weaker
  claim than a green tick — it is a *different* claim, and it is the true one.
- **Never add product code to the platform to make its own metrics look alive.** If a number can
  only be improved by destroying the thing being measured, the number is measuring the wrong
  subject.
- **Get one real adopter, and treat its evidence as the platform's proof.** A reference fork is
  the only artefact that closes this class of finding, and it lives outside the repository that
  has the finding.
- **Keep the ratchet at home.** The platform still measures its own liveness — not to force the
  number up, but to stop new claims being added to a pile that cannot be substantiated here.
- **When a principle is stated, go looking for its other instances immediately.** This one was
  written, published, and then contradicted the next day in the same repository. Stating a
  principle does not apply it.

## Related

- [[0014-fixing-the-instance-is-not-fixing-the-class]] — the same failure, one level up: this is
  an instance of L0014 committed by the author of L0014
- [[0016-a-check-answers-the-question-it-asks]] — the liveness check that surfaced this measured
  *use* rather than *existence*, which is why it found anything at all
- [[0011-unexecuted-code-is-a-plan]] — a gate that has never run is a plan; the correction is
  about **where** it stops being one
