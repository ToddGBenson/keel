---
description: Run the G1 Definition of Ready gate against a story and fail loudly with specific, actionable gaps
argument-hint: <issue number>
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, Task
---

# G1 — Definition of Ready: `$ARGUMENTS`

Run the gate in `process/gates/g1-ready.md`. Delegate to `product-owner` for content and
`delivery-lead` for process adherence.

**Skill:** `writing-acceptance-criteria` — items 9–11 and 18 are judged against it.

## How to run this

This is a **gate, not a formality**. Assess each item as satisfied or not, and for anything
unsatisfied, state the specific gap and what would close it.

A team that passes 100% of stories on the first attempt is rubber-stamping. Expect
rejections. Report the rejection rate as a health signal.

## Checklist

| # | Item | Evidence to point at |
|---|---|---|
| 1 | Traces to a G0-accepted idea with a problem statement | Linked idea issue |
| 2 | User, value, and outcome stated | Story narrative |
| 3 | **I**ndependent — ships without another unfinished story | Dependency list |
| 4 | **N**egotiable — states need, not locked implementation | AC wording |
| 5 | **V**aluable — beneficiary named | Story narrative |
| 6 | **E**stimable — team knows enough to size it | Estimate present |
| 7 | **S**mall — ≤ ~3 developer-days | Estimate |
| 8 | **T**estable — QA can prove it true or false | AC wording |
| 9 | AC in Given/When/Then, binary and observable | AC list |
| 10 | AC covers happy path, ≥1 error path, ≥1 boundary | AC list |
| 11 | Non-functional criteria attached **with numbers** | NFR section |
| 12 | Security relevance triaged and flagged | Flag field |
| 13 | AI relevance triaged and flagged | Flag field |
| 14 | Privacy relevance triaged and flagged | Flag field |
| 15 | Dependencies identified and resolved | Dependency list |
| 16 | Estimated by the team | Estimate |
| 17 | Test approach agreed with QA | Test approach line |
| 18 | **No open question exists whose answer would change the design** | Open questions section |

## Judgment calls, not box-ticking

- **Item 9** is where most stories fail. Read each criterion and ask: could a reasonable
  person argue this passed when it did not? If yes, it is not binary.
- **Item 11**: "response is fast" fails. "p95 < 200 ms under 100 concurrent users" passes.
- **Items 12–14**: apply `docs/10-definitions.md` literally. Any flag set ⇒ note that **G2
  is now mandatory** and name the required co-approver.
- **Item 18** overrides everything. A story can satisfy 17 items and still not be Ready.

## Output

```
G1 RESULT: READY | NOT READY

Satisfied:   n/18
Gaps:
  - Item 10: no error-path criterion. Add one covering quota-exceeded behavior.
  - Item 11: "should be responsive" — replace with a p95 threshold.
Gates now required: G2 (security-relevant: touches session handling)
Required co-approvers: security-engineer
```

## Then

**A human, plus the Delivery Lead, confirms G1.** Agents do not pass gates. If NOT READY,
the story returns to refinement with these specific gaps — never "needs work".
