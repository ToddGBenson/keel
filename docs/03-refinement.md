# 03 — Refinement (→ G1 Definition of Ready)

**Owner:** Product Owner + Delivery Lead · **Commands:** `/refine`, `/ready` ·
**Gate:** `process/gates/g1-ready.md`

## The point

Refinement converts an accepted problem into stories a developer can start on **today**
without asking a question that would change the answer. The measure of good refinement is
not document length; it is the absence of mid-sprint clarification requests.

## Epic → story decomposition

An epic is a problem worth several weeks. Split it into stories along **user-visible value**,
never along technical layers.

```
✗ WRONG — layer slicing. Nothing is shippable until all three land.
  #1 Create drafts DB table
  #2 Build drafts API endpoint
  #3 Wire up the autosave UI

✓ RIGHT — thin vertical slices. Each ships and is independently valuable.
  #1 Editor state survives an accidental tab close within the same session
  #2 Editor state survives session expiry and is offered on next sign-in
  #3 User can browse and restore any of their last 5 recovered drafts
```

Legitimate split axes: workflow step · happy path vs. error path · CRUD operation ·
data variation · user role · platform · performance target (make it work, then make it
fast as a separate, measurable story).

## INVEST

Every story is checked against these. The gate rejects on any failure.

| | Test | Common failure |
|---|---|---|
| **I**ndependent | Can it ship without another unfinished story? | Hidden ordering dependencies |
| **N**egotiable | Does it state the need, not a locked implementation? | AC written as a technical spec |
| **V**aluable | Can you name who benefits and how? | "Refactor the service layer" — real work, but a chore, not a story |
| **E**stimable | Does the team know enough to size it? | Unknowns → spike first |
| **S**mall | ≤ ~3 days for one developer | If not, split it |
| **T**estable | Can QA prove it true or false? | "Should be fast", "intuitive UI" |

## Acceptance criteria

Use Given/When/Then. Cover the happy path, at least one error path, and at least one
boundary. Criteria are **binary and observable** — a criterion an honest person could argue
either way about is not a criterion.

```gherkin
Given I am editing a document and have unsaved changes
When my session expires and I sign in again within 24 hours
Then I am offered my most recent draft with its edit timestamp
And declining the offer discards it permanently with no second prompt

Given my draft exceeds the 5 MB per-user storage limit
When autosave runs
Then the save is rejected, the oldest draft is evicted, and I see a non-blocking notice
```

### Non-functional criteria are criteria

Attach the ones that apply, with numbers. "Fast" and "secure" are not criteria.

- **Performance** — p95 latency, throughput, payload budget
- **Security** — authz rule, input validation boundary, data classification, audit event
  emitted (`AU-2`)
- **Privacy** — what personal data is touched, retention, minimization justification
- **Accessibility** — WCAG 2.2 AA for user-facing changes
- **Observability** — what log, metric, or trace this change must emit to be debuggable
- **Reliability** — failure mode, degradation behavior, rollback impact

## Security & AI triage at refinement

Every story gets triaged. This is the step that determines whether G2 is mandatory, and
getting it wrong at refinement is what causes an expensive surprise at G4.

**Security-relevant if it touches any of:** authentication, authorization, session
handling, cryptography, secrets, personal or regulated data, file upload/parsing, external
network calls, deserialization, template rendering, subprocess execution, SQL/query
construction, infrastructure or CI configuration, dependency additions.

**AI-relevant if it:** adds or modifies a model call, changes a prompt or system
instruction, alters retrieval/grounding data, adds tool/function-calling capability,
changes an autonomy boundary, processes user data through a model, or introduces
model-generated output into a decision that affects a person.

Either flag ⇒ **G2 is mandatory** and the corresponding specialist agent co-approves.

## Estimation

Relative sizing, whole team, no anchoring — the estimator states a number before hearing
others. Estimates size *uncertainty*, not effort alone: a well-understood two-day task and
a murky one-day task are not the same size.

Estimates are inputs to conversation and forecasting. They are **not** commitments,
performance measures, or anything an individual is held to. Using them that way corrupts
them within one sprint, permanently.

Wide disagreement is the valuable signal — the discussion that resolves it is where the
misunderstanding surfaces. Do not average it away.

## Definition of Ready

The full checklist is `process/gates/g1-ready.md`. In summary, a story is Ready when:

- Problem, value, and user are stated and traceable to a G0-accepted idea
- INVEST holds
- Acceptance criteria are written, binary, and cover happy/error/boundary
- Applicable non-functional criteria are attached with numbers
- Security and AI relevance triaged and flagged
- Dependencies identified and unblocked (or the story is explicitly blocked, not "ready")
- Estimated by the team
- Test approach agreed with QA at a high level
- No open question exists whose answer would change the design

**Ready is a filter, not a formality.** A team that passes 100% of stories through DoR on
the first attempt is rubber-stamping. Expect and welcome rejections; track the rejection
rate as a health metric in the retro.

**Control mapping:** SA-3, SA-4(3) (development methods), SA-8 (security engineering
principles applied at design-in), SA-15 (development process/standards), PL-8 (security
architecture inputs), and AI RMF **MAP 2.3 / MEASURE 1.1** for AI-relevant stories.
