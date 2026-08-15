# G0 — Intake

**Recommends:** Product Owner · **Approves:** Delivery Lead (ADR-0005) · **Command:** `/idea`
**Reference:** `docs/02-intake-and-discovery.md` · **Controls:** SA-3(1), RA-3, PM-30,
AI RMF MAP 1

An idea leaves this gate accepted, rejected, or parked with a review date. It does not
leave as an unranked wish.

## Checklist

| # | Item | Evidence |
|---|---|---|
| 1 | Problem statement written — who, what they cannot do, what it costs. **No solution words.** | Idea issue |
| 2 | Evidence provided, and its **type labeled honestly** (data vs. request vs. anecdote) | Idea issue |
| 3 | Affected population quantified — how many, which segment, how often | Idea issue |
| 4 | Current workaround described (or its absence noted as a signal) | Idea issue |
| 5 | **Success measure named, with a current baseline** | Idea issue |
| 6 | Constraints identified — regulatory, contractual, technical, timing | Idea issue |
| 7 | Security relevance triaged | Flag field |
| 8 | Privacy relevance triaged | Flag field |
| 9 | AI relevance triaged | Flag field |
| 10 | At least two options considered, including **do nothing** and its cost | Idea issue |
| 11 | RICE score assigned with reasoning per factor | Idea issue |
| 12 | Decision recorded: Accept / Reject / Park **with a reason** | Issue state + comment |

## Judgment notes

**Item 1** is where this gate earns its cost. If the statement contains "add", "build", or a
UI element, it is a solution. Send it back.

**Item 5**: no baseline means nobody can later prove this worked. That is not a blocker, but
it must be stated explicitly rather than left implicit — "we cannot measure this" is a
legitimate, recorded decision.

**Items 7–9** determine which downstream gates apply. Under-flagging here is the cheapest
mistake to make and the most expensive to discover at G4. When uncertain, flag it.

**Item 11**: risk-reduction items (security findings, EOL components, compliance gaps) are
**not** RICE-ranked against features. They enter with an SLA-driven due date.

**Item 12**: Park with no review date is rejection in disguise. Either set a date or reject
honestly — the second is kinder and produces a reusable record.

## Fail conditions

- The idea is a solution with no identified problem
- No evidence of any kind
- Confidence below 50% ⇒ route to a **spike** instead of accepting
- Relevance flags not assessed

## Exit

**Accepted** → backlog, ranked, eligible for `/refine`.
**Rejected** → closed with a recorded reason. Rejection reasons are an asset; they stop the
same idea re-entering every quarter. Never close silently.
**Parked** → review date set.
