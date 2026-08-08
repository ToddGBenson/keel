# 03 — Refinement (→ G1 Definition of Ready)

**Owner:** Product Owner (+ Delivery Lead) · **Commands:** `/refine`, `/ready`
**Gate:** `process/gates/g1-ready.md` · **Method:** `story-splitting`, `writing-acceptance-criteria`

## The point

Refinement converts an accepted problem into a story a developer can start on **today**
without asking a question that would change the answer. The measure of good refinement is not
document length — it's the absence of mid-sprint clarification requests.

**Decomposition and acceptance criteria** are in the skills. The two rules worth stating here:
split along **user-visible value**, never technical layers (a vertical slice ships; a layer
doesn't); and every criterion is **binary and observable** — if an honest person could argue
it either way, it's not a criterion.

**INVEST**, briefly: **I**ndependent (ships without another unfinished story) · **N**egotiable
(states the need, not a locked implementation) · **V**aluable (name who benefits) ·
**E**stimable (enough known to size it) · **S**mall (≤ ~3 days) · **T**estable (QA can prove it
true or false). The gate rejects on any failure.

**Non-functional criteria are criteria** — with numbers, not "fast": performance (p95,
throughput), security (authz rule, validation boundary, `AU-2` audit event), privacy (data
touched, retention), accessibility (WCAG 2.2 AA), observability (what it must emit),
reliability (failure and degradation behavior).

## Security & AI triage — the step that sets the gates

Every story is triaged here. This determines whether **G2 is mandatory**, and getting it
wrong is what produces an expensive surprise at G4.

**Security-relevant** if it touches: authn, authz, session handling, cryptography, secrets,
personal/regulated data, file upload/parsing, external calls, deserialization, template
rendering, subprocess execution, query construction, infra/CI config, or a dependency add.

**AI-relevant** if it: adds/changes a model call, prompt, system instruction,
retrieval/grounding data, tool-calling capability, or autonomy boundary; processes user data
through a model; or puts model output into a decision affecting a person.

Either flag ⇒ G2 mandatory, specialist co-approves. When uncertain, flag it — an unnecessary
G2 costs an hour, a missed one costs a release.

## Estimation

Relative sizing, no anchoring. Estimates size *uncertainty*, not effort — a well-understood
two-day task and a murky one-day task aren't the same size. They are inputs to conversation
and forecasting, **never** commitments or performance measures; used that way they corrupt
within one sprint. Wide disagreement is the valuable signal — resolve it, don't average it
away. *(Solo: you still estimate, to spot the stories hiding a spike inside them.)*

## Definition of Ready

Full checklist: `process/gates/g1-ready.md`. In summary — traceable to a G0 idea; INVEST
holds; AC binary and covering happy/error/boundary; NFRs with numbers; security/AI/privacy
triaged; dependencies resolved (or the story is Blocked, not Ready); estimated; test approach
agreed; **no open question whose answer would change the design.**

**Ready is a filter, not a formality.** Passing 100% of stories first-attempt is
rubber-stamping — track the rejection rate as a health metric.

**Control mapping:** SA-3, SA-4(3), SA-8, SA-15, PL-8; AI RMF MAP 2.3 / MEASURE 1.1.
