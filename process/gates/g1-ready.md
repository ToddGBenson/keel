# G1 — Ready (Definition of Ready)

**Approvers:** Product Owner (content) + Delivery Lead (process), confirmed by a human
**Command:** `/ready` · **Reference:** `docs/03-refinement.md`
**Controls:** SA-3, SA-4(3), SA-8, SA-15, PL-8, AI RMF MAP 2.3

A story that passes this gate can be started **today** without asking a question whose
answer would change the design.

## Checklist

| # | Item | Evidence |
|---|---|---|
| 1 | Traces to a G0-accepted idea with a problem statement | Linked idea |
| 2 | User, value, and outcome stated in the narrative | Story issue |
| 3 | **I** — ships without another unfinished story | Dependency list |
| 4 | **N** — states the need, not a locked implementation | AC wording |
| 5 | **V** — beneficiary named | Narrative |
| 6 | **E** — team knows enough to size it | Estimate present |
| 7 | **S** — ≤ ~3 developer-days | Estimate |
| 8 | **T** — QA can prove it true or false | AC wording |
| 9 | AC in Given/When/Then, **binary and observable** | AC list |
| 10 | AC covers happy path, ≥1 error path, ≥1 boundary | AC list |
| 11 | Non-functional criteria attached **with numbers** | NFR section |
| 12 | Security relevance triaged and flagged | Flag field |
| 13 | AI relevance triaged and flagged | Flag field |
| 14 | Privacy relevance triaged and flagged | Flag field |
| 15 | Dependencies identified and resolved (else the item is Blocked, not Ready) | Dependency list |
| 16 | Estimated by the team | Estimate |
| 17 | Test approach agreed with QA | Test approach line |
| 18 | **No open question exists whose answer would change the design** | Open questions section |

## Judgment notes

**Item 9** is where most stories fail. Read each criterion and ask: *could a reasonable
person argue this passed when it did not?* If yes, it is not binary. "The user sees their
draft" fails; "the most recent draft is offered with its edit timestamp" passes.

**Item 11**: "should be responsive" fails. "p95 < 200 ms at 100 concurrent users" passes. If
the number is unknown, that is a spike, not a guess.

**Items 12–14**: apply `docs/10-definitions.md` literally. **Any flag set ⇒ G2 becomes
mandatory** and the corresponding specialist becomes a blocking co-approver. Record which.

**Item 18 overrides everything.** A story can satisfy the other seventeen and still not be
Ready. If the answer to an open question would change the design, starting means building
the wrong thing efficiently.

## Fail conditions

- Any acceptance criterion that is not binary
- Non-functional criteria without numbers
- Relevance flags unassessed
- An open design-changing question
- Larger than ~3 days without a split
- Unknowns large enough that estimation is guessing ⇒ spike instead

## Health signal

**A team that passes 100% of stories on the first attempt is rubber-stamping.** Track the
rejection rate and report it in the retro. A gate that never rejects is ceremony.

## Exit

**Ready** → eligible for `/design` (if flagged) or `/implement`.
**Not Ready** → returns to refinement with the **specific gaps named**. Never "needs work".
