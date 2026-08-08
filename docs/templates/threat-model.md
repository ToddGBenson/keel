# Threat Model — <story/epic> #<n>

**Author:** security-engineer · **Reviewer:** architect · **Date:** <YYYY-MM-DD>
**Gate:** G2 · **Controls:** SA-11(2), SA-8, RA-3

> Model the **delta**, not the whole system. Full-system models go stale and stop being read.

## 1. What are we building?

Scope of this change. What is in, what is explicitly out.

**Data flow of the delta** — trust boundaries marked. A diagram, a table, or prose, whichever
is clearest. What matters is that every boundary crossing is visible.

```
[User] ──HTTPS──▶ ║ [API] ──▶ [DraftService] ──▶ ║ [Postgres]
                  ║  trust boundary              ║  trust boundary
```

**Assets.** What is worth attacking: data, credentials, availability, integrity of a decision.

**Actors.** Legitimate users and their rights; adversaries and their plausible capability.
Be realistic — a threat model against a nation-state adversary for an internal CRUD app
produces nothing actionable.

## 2. What can go wrong? — STRIDE on the delta

| # | Threat | STRIDE | Attacker | Precondition | Impact | Likelihood | Severity |
|---|---|---|---|---|---|---|---|
| T1 | | S/T/R/I/D/E | | | | | |

Prompts per category:

- **Spoofing** — can an actor claim an identity they do not hold? Session fixation, token
  replay, missing origin validation.
- **Tampering** — can data be modified in transit, at rest, or **in the pipeline**?
- **Repudiation** — can an actor deny an action we cannot prove? Missing or insufficient audit.
- **Information disclosure** — can data reach an unauthorized party? IDOR, over-broad
  responses, error messages, logs, timing.
- **Denial of service** — can availability be exhausted, by whom, at what cost to them?
- **Elevation of privilege** — can an actor gain rights beyond their grant? Missing object-level
  authz, confused deputy, path traversal.

If this change involves AI, also consider prompt injection, insecure output handling, and
tool-call abuse — and cross-reference the AI Impact Assessment rather than duplicating it.

## 3. What are we going to do about it?

**Every threat gets a disposition. An undispositioned threat fails G2.**

| # | Disposition | Control | Implemented in (file/component) | Verified by | Evidence |
|---|---|---|---|---|---|
| T1 | Mitigate | AC-3 object authz | `DraftAuthorizer` | negative integration test | test result |
| T2 | Accept | — | — | — | POA&M-<n>, expires <date>, approved by <human> |
| T3 | Eliminate | Feature removed / data not collected | — | — | — |
| T4 | Transfer | Handled by <provider> per <contract> | — | — | — |

**"Implemented in the application layer" is not an allocation.** Name the file. The developer
cannot act on a vague allocation and QA cannot verify it.

**A mitigation with no verification method is an intention.** Name the test.

**Accept** requires: human approval, a POA&M entry, an expiry date, and a named compensating
control. Indefinite acceptance is not acceptance.

## 4. Did we do a good job?

- [ ] Every trust boundary crossing examined
- [ ] Every STRIDE category considered against every boundary (even if the answer is "none")
- [ ] Every threat dispositioned
- [ ] Every mitigation names a component **and** a verification method
- [ ] Every accepted risk has approval, POA&M entry, and expiry
- [ ] Attack surface change identified and justified (SA-15(5))
- [ ] Reviewed by the architect — an identity other than the author

## 5. Assumptions

What this model assumes to be true. If an assumption breaks, the model must be re-run —
so state them, and state them as things that could be false.

Examples: "the API gateway terminates TLS and rejects unauthenticated requests" · "the
database is not directly reachable from the internet" · "session tokens are rotated on
privilege change."

## 6. Out of scope

What this model deliberately does not cover, and where that coverage lives instead.
