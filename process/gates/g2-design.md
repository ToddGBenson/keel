# G2 — Designed & Threat-Modeled

**Recommends:** Architect + Security Engineer + UX (+ AI Risk Officer if AI-relevant) ·
**Approves:** Delivery Lead (ADR-0005) · **Command:** `/design` · **Reference:** `docs/04-development.md` Part A
**Controls:** SA-8, SA-11(2), SA-15, SA-17, PL-8, RA-3, AI RMF MAP 1–5

## When required

Mandatory when the story is flagged **security-relevant, privacy-relevant, or AI-relevant**,
or when the change is expensive to reverse. Otherwise the skip is **recorded with its
reason** — a silent skip is what an assessor finds.

## Checklist

| # | Item | Evidence |
|---|---|---|
| 1 | Technical approach documented; alternatives considered and rejection reasons given | Design note |
| 2 | ADR written **if** the decision is costly to reverse (or explicitly deemed unnecessary) | `docs/adr/` |
| 3 | Threat model run on the **delta** using STRIDE | Threat model doc |
| 4 | **Every threat has a recorded disposition** — mitigate / transfer / accept / eliminate | Threat model |
| 5 | Every mitigation names its **verification method** | Threat model |
| 6 | Accepted risks have human approval, a POA&M entry, and a review date | POA&M |
| 7 | Control allocation matrix complete — each control names a **file or component** | Allocation matrix |
| 8 | Each allocated control names how it is verified and the evidence artifact | Allocation matrix |
| 9 | SA-8 secure design principles addressed — where each holds in *this* design | Design note |
| 10 | Attack surface change identified and justified (SA-15(5)) | Design note |
| 11 | NFRs specified with numbers and verification methods | Design note |
| 12 | Data classification and handling stated (if personal/regulated data is touched) | Design note |
| 13 | **AI Impact Assessment complete** (if AI-relevant) | AIA doc |
| 14 | AI risk tier assigned; tier-appropriate requirements identified | AIA doc |
| 15 | Guardrail design specified (if AI-relevant) | AIA doc |
| 16 | Human oversight point designed — including **what the human is shown** | AIA doc |
| 17 | Independence held: the design's author is not its sole approver | Approval record |
| 18 | **UX design exists for every UI surface** — flow, states, and the failure states named: empty, loading, error, offline, permission-denied | `docs/design/wireframes/` |
| 19 | **Accessibility review recorded** against the G1 criteria, with any conflict between usability and a security control decided explicitly rather than silently | `docs/design/a11y/` |

## Judgment notes

**Item 4** — an undispositioned threat fails this gate. "We'll think about it" is not a
disposition.

**Item 5** — "we will validate input" is an intention until someone can name the test that
proves it. Mitigations without verification methods become unverifiable claims at G4.

**Item 7** — "implemented in the application layer" is not an allocation. The developer
cannot act on it and QA cannot verify it. Name the file.

**Item 9** — applied, not recited. Say *where* least privilege lives in this design, not
that least privilege is important.

**Item 13** — start with the question people skip: *what is the non-AI alternative, and why
is it insufficient?* If a deterministic solution works, that is usually the better
engineering answer. AI carries a permanent assurance cost.

**Item 16** — a human oversight point where the human sees only the output and not its basis
is oversight in name only. State what they see and what they can actually do.

**Item 17** — run `architect`, `security-engineer`, and `ai-risk-officer` as **separate agent
invocations**. A single reasoning chain producing both the design and its critique produces
neither (AIC-2).

## Fail conditions

- An undispositioned threat
- A mitigation with no verification method
- A control allocated to "the application" rather than a component
- AI-relevant with no completed impact assessment
- Risk tier assessed as **Prohibited** → escalate to a human; do not negotiate the tier down
- The architect approving their own design alone

## Exit

**Pass** → artifacts written to `evidence/<issue>/g2/`; story eligible for `/implement`.
**Fail** → returns to design with the specific unresolved items named.
