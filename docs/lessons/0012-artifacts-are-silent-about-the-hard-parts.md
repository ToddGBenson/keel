# L0012: A spec is silent about exactly the parts that break

**Date:** 2026-08-08 · **Source:** first end-to-end feature run (notekeeper) · **Class:** promotable
**Applies to:** any intake from a wireframe, mockup, PDF spec, or API schema
**Landed as:** the `artifact-intake` skill's interrogation checklist · `/spec`
**Related:** [L0011](0011-unexecuted-code-is-a-plan.md)

## What happened

The platform was run end to end for the first time on a real feature: a spec document → G1
story → G2 threat model → TDD implementation → G3/G4 verification. Working code, 12 passing
tests.

The spec was ordinary and looked complete: two wireframes, five REST endpoints, three bullet
points of notes. **Extracting it yielded 8 stated requirements and 9 unspecified ones**, and
the unspecified list contained every genuinely dangerous decision:

- **Can user A fetch user B's note by id?** The spec showed `GET /notes/{id}` and said "list
  the user's notes" — and never stated an ownership rule. Textbook IDOR, invisible unless you
  go looking.
- "Titles should be reasonably short" — no number, so no validation and no test.
- "It should feel fast" — no number, so no NFR.
- Error shape: undefined across all five endpoints.
- Empty state, delete semantics, concurrency, pagination: absent.

The artifact described the happy path in one state for one role. Everything that decides
whether the feature is *safe* was in the silence.

## The rule

**Intake is interrogation, not transcription.** Anyone can list the buttons. The value is a
systematic pass over what the artifact *cannot* say — states, validation boundaries,
permissions, concurrency, lifecycle, non-functionals — because that is what G1 rejects on and
what G4 discovers expensively.

Keep three sections **visibly separate**: Extracted (stated, with source), Inferred (your
reading, not stated), Unspecified (blocks G1). A requirement you invented but presented as
extracted gets built unquestioned; a gap you flagged gets a two-minute conversation.

## How you would know you hit this

You read a spec, felt it was clear, and started building. Or: your acceptance criteria contain
"fast", "reasonable", "secure", or "handled gracefully" — each one is an unasked question
wearing a confident word.

## What the run also proved

- The gates work on real code, not just meta-work: G2 allocated AC-3 to a named component, and
  G3/G4 verified it in the implementation.
- Putting authorization **in the store** rather than a route middleware made complete
  mediation structural — a new route cannot forget it.
- **Mutation-testing the control is worth the 60 seconds.** Removing the ownership check
  failed exactly 3 tests, proving the negative-case tests constrain behaviour rather than
  asserting shape. A control test you have not seen fail is a control test you are assuming.
