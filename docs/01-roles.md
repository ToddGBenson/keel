# 01 — Roles, Accountability, and Separation of Duties

Nine roles. Each is an agent in `.claude/agents/`. Each has a mandate, an explicit
boundary, and a set of artifacts it alone may author.

The boundaries matter more than the mandates. A role that can do everything provides no
assurance — separation of duties (NIST AC-5) is the reason an independent reviewer's
approval means anything at all.

---

## The roster

### Product Owner — `product-owner`
**Mandate.** Owns *what* and *why*, and the order of the backlog. Converts raw ideas into
problem statements, epics into INVEST stories, and vague wishes into testable acceptance
criteria. Accepts or rejects completed work against those criteria.

**Authors:** idea records, epics, stories, acceptance criteria, prioritization rationale,
release notes (business-facing portion).

**Boundary.** Does not design solutions, estimate on the team's behalf, or override a
security or QA rejection. May accept business risk; may **not** accept security risk —
that requires the risk-acceptance path in `08-operate-and-respond.md`.

**Gates:** approves G0, co-approves G1.

---

### Architect — `architect`
**Mandate.** Owns *how it fits together*. Technical approach, non-functional requirements,
system decomposition, and the allocation of security controls to components. Writes ADRs
for decisions that are expensive to reverse.

**Authors:** ADRs, design notes, NFR specifications, control allocation matrix, interface
contracts.

**Boundary.** Does not implement. Does not approve their own designs through G2 alone —
Security co-approves. An architect who writes the code loses the independent-design-review
property the gate exists to provide.

**Gates:** co-approves G2.

---

### Developer — `developer`
**Mandate.** Turns a G1-ready story into working, tested, reviewed code. Writes the failing
test first. Implements the smallest change that satisfies the acceptance criteria. Raises
the PR with complete DoD evidence.

**Authors:** source code, unit and integration tests, PR descriptions, implementation notes,
AI-authorship declarations.

**Boundary.** **Does not review, test-verify, or release their own work.** Does not change
acceptance criteria — that is a conversation with the Product Owner, recorded on the issue.
Does not suppress a scanner finding; suppression requires Security sign-off with a
documented rationale.

**Gates:** produces the G3 candidate. Never approves G3 on their own PR.

---

### Security Engineer — `security-engineer`
**Mandate.** Owns threat identification and control verification. Runs STRIDE on designs,
verifies that allocated controls are actually implemented (not merely intended), triages
scanner output into real findings, and maintains the finding backlog and POA&M entries.

**Authors:** threat models, security findings, control verification evidence, security
exceptions, penetration test scope and results.

**Boundary.** Does not write the feature code they later verify. Has authority to **block**
a release for an unmitigated Critical or High finding, and that block is not overridable by
the Product Owner — only by documented, time-boxed, human-approved risk acceptance.

**Gates:** co-approves G2, co-approves G4.

---

### QA Engineer — `qa-engineer`
**Mandate.** Owns *evidence that it works*. Defines test strategy per story, writes the
test cases that trace to acceptance criteria, executes and records verification, and hunts
the cases the developer's happy path missed — boundaries, error paths, concurrency, and
data that looks nothing like the demo data.

**Authors:** test plans, test cases, exploratory charters, verification records, defect
reports, traceability matrix (AC → test → result).

**Boundary.** Does not fix the defects they find. Does not accept on the Product Owner's
behalf. Rejects on evidence, and the rejection names the specific criterion that failed.

**Gates:** co-approves G4.

---

### AI Risk Officer — `ai-risk-officer`
**Mandate.** Owns AI-specific risk in two directions: the AI features this team *ships*,
and the AI agents this team *uses to build*. Runs AI impact assessments, defines and
maintains eval suites, commissions red-teaming, monitors for drift, and verifies that
guardrails exist and function.

**Authors:** AI impact assessments, model cards, eval plans and results, red-team reports,
AI incident records, the AI system inventory.

**Boundary.** Does not build the model or the feature. Has the same blocking authority as
Security for AI-specific Critical/High findings. Cannot be the same identity that authored
the AI feature under assessment.

**Gates:** mandatory co-approver of G2 and G4 for any AI-relevant change. See
`12-ai-feature-governance.md`.

---

### Delivery Lead — `delivery-lead`
**Mandate.** Owns *flow*. Removes impediments, facilitates the gates without owning them,
protects work-in-progress limits, runs retrospectives, and keeps the process honest by
surfacing where it is being routed around.

**Authors:** impediment log, retro records, flow metrics, process improvement proposals,
sprint records.

**Boundary.** Does not assign work, estimate for others, approve technical or security
gates, or commit the team to scope. Facilitates; does not decide.

**Gates:** co-approves G1 (readiness of the *process*, not the content).

---

### Release Manager — `release-manager`
**Mandate.** Owns *change control*. Assembles the change record, verifies every included
item cleared G4, confirms rollback is tested and viable, and presents the release for human
authorization. Executes the deployment through the pipeline — never by hand.

**Authors:** change records, release notes, rollback plans, deployment records, post-deploy
verification results.

**Boundary.** Does not authorize their own release — a human operator does. Does not
include un-gated work "just this once." Does not have standing production credentials;
the pipeline identity deploys.

**Gates:** prepares G5, human authorizes.

---

### Compliance Officer — `compliance-officer`
**Mandate.** Owns *the mapping and the truth of it*. Maintains the control map, verifies
that evidence exists and is intact for every claimed control, runs periodic control
assessments, maintains the POA&M, and keeps the SSP current.

**Authors:** control map, evidence index, assessment reports, POA&M, SSP sections,
continuous monitoring reports.

**Boundary.** Does not implement controls and does not approve delivery gates. Assesses;
does not build. Critically: **reports control gaps as they are**, including gaps that
embarrass the team or delay a release.

**Gates:** none directly — audits all of them.

---

### Technical Writer — `tech-writer`
**Mandate.** Owns *comprehensibility*. User-facing documentation, runbooks, API references,
and the internal docs that keep this process usable rather than ceremonial.

**Authors:** user docs, runbooks, API docs, onboarding material, changelogs.

**Boundary.** Does not invent behavior — documents what exists, and files a defect when the
behavior and the intent disagree.

---

## Separation-of-duties matrix

The rule in one line: **the producing identity is never the approving identity.**

| Artifact | Produces | Reviews | Approves |
|---|---|---|---|
| Story / acceptance criteria | Product Owner | Delivery Lead, Developer | Product Owner + Delivery Lead (G1) |
| ADR / design | Architect | Developer, Security | Architect + Security (G2) |
| Threat model | Security Engineer | Architect | Security + Architect (G2) |
| AI impact assessment | AI Risk Officer | Security, Architect | AI Risk + Security (G2) |
| Source code | Developer | **A different Developer identity** | Reviewer (G3) |
| Test plan / results | QA Engineer | Developer, Product Owner | QA (G4) |
| Security verification | Security Engineer | Compliance Officer | Security (G4) |
| Eval results | AI Risk Officer | Security, QA | AI Risk (G4) |
| Change record | Release Manager | Security, QA, Compliance | **Human operator (G5)** |
| Control evidence | The role that performed the control | Compliance Officer | Compliance (assessment) |
| Process change | Anyone | Delivery Lead | Human operator |

### How it is enforced

Convention is not enforcement. The mechanisms:

- **CODEOWNERS** (`.github/CODEOWNERS`) routes required reviews by path. Security-relevant
  paths require the security owner; workflow files require both security and release.
- **Branch protection** on `main`: required status checks, required reviews, dismiss stale
  approvals on new commits, no force-push, no bypass for administrators.
- **GitHub Environments** with required reviewers gate the production deploy job — the
  human authorization at G5 is a technical control, not an email.
- **Signed commits** required, so the producing identity is cryptographically attributable
  (SI-7, CM-14).
- **Agent tool scoping** — each agent definition grants only the tools its role needs. The
  `product-owner` agent cannot write source files; the `developer` agent cannot approve.
  This is the AI-layer expression of the same principle (see `11-ai-agent-controls.md`).

### Where a human is non-negotiable

> **Narrowed 2026-08-15 (ADR-0005).** Routine gate transitions are no longer on this list —
> `delivery-lead` approves G0–G5 on the evidence other roles produce. What remains below is
> where an agent's approval is least defensible, and it remains human. **POAM-017** records the
> reduction; it is a weakening, not a refinement.

Agents now execute *and* record gate transitions. A human being must still personally approve:

1. **Production release** — a deployment reaching real users or real data. `delivery-lead` may
   approve G5 for a change that ships nothing to production (a tagged template release, an
   internal artifact); it hands over when a release leaves the building.
2. **Risk acceptance** — any decision to ship with a known unmitigated High or Critical
   finding, security or AI. `delivery-lead` cannot approve past a live block.
3. **Security exceptions** — any time-boxed deviation from a control.
4. **Process changes** — amendments to this document, the gates, or the control map.
5. **Scope or criteria changes** on in-flight work that alter what "done" means.
6. **Anything touching production data, credentials, or customer-facing communication.**

The reasoning is accountability, not distrust: NIST's control model assumes a responsible
individual. **An agent cannot hold accountability** — it cannot be answerable for an outcome,
and nothing about giving it approval authority changes that. What moving gate approval to
`delivery-lead` actually did was relocate the accountability, not discharge it: the human who
configured the orchestrator now answers for every transition it records, without having read any
of them. That is a real transfer of risk to a named person, and it is why the list above stops
where it does.

## RACI

Ownership answers *whose call is it*. RACI answers *who should have been asked* — which is the
question actually being got wrong whenever work goes backwards through a gate.

**R** = does the work · **A** = accountable, one per row, and it is the approver ·
**C** = consulted before, and their input changes the outcome · **I** = informed after.

| Activity | PO | Delivery Lead | Architect | UX | Security | Devs | QA | Release | AI Risk | Compliance |
|---|---|---|---|---|---|---|---|---|---|---|
| Idea intake (G0) | **R** | **A** | I | I | I | I | I | I | I | I |
| Requirements & criteria (G1) | **R** | **A** | C | C | C | I | C | I | C | I |
| Sprint planning | C | **A/R** | I | I | I | C | C | I | I | I |
| Architecture & ADRs (G2) | C | **A** | **R** | C | C | C | I | I | C | I |
| UX design & accessibility (G2) | C | **A** | C | **R** | I | C | C | I | I | I |
| Threat model (G2) | I | **A** | C | I | **R** | C | C | I | C | I |
| AI impact assessment (G2) | C | **A** | C | I | C | C | I | I | **R** | I |
| Implementation (G3) | I | **A** | C | C | C | **R** | I | I | C | I |
| Code review (G3) | I | **A** | C | I | C | **R** | C | I | I | I |
| Test creation & execution (G4) | I | **A** | I | C | C | C | **R** | I | C | I |
| Security verification (G4) | I | **A** | C | I | **R** | C | C | I | C | C |
| Eval & red-team (G4, AI) | I | **A** | I | I | C | C | C | I | **R** | I |
| Build & package | I | **A** | I | I | C | **R** | C | C | I | I |
| Release readiness (G5) | C | **A** | I | I | C | I | C | **R** | C | C |
| Production deployment | I | C | I | I | C | I | C | **R** | I | I |
| Monitoring & observability | I | C | C | C | C | C | C | **R** | C | I |
| Incident response | C | C | C | I | **R** | **R** | C | C | C | I |
| Control assessment & POA&M | I | C | C | I | C | I | C | I | C | **A/R** |
| Continuous improvement | C | **A/R** | C | C | C | C | C | C | C | C |

**Read the A column first.** `delivery-lead` is accountable for every gated row and does the work
in none of them — that is PD-2 expressed as a table. The two rows where it is only *consulted*
are the ones that reach production, where accountability sits with `release-manager` and, above
them, a human.

**A row with no C is a warning sign.** It means one role can complete that activity without
anyone's input, and every gate rejection worth studying in this repository traces back to a
consultation that should have happened and did not.

## Role assignment in a small team

One person may hold several roles; that is normal and workable. Two constraints survive
any amount of hat-swapping:

- **Never author and approve the same artifact**, even wearing different hats. If you
  wrote it, someone else — human or a separately-spawned agent identity — approves it.
- **Security and AI Risk blocking authority stays intact.** If you hold both the developer
  and the security hat, spawn the `security-engineer` agent fresh, with only the diff and
  the threat model as input, so the assessment is genuinely independent of the reasoning
  that produced the code.

When the roster is thin, the honest move is to record the compression in the SSP under
AC-5 and note the compensating control (independent agent invocation, external review
cadence) rather than pretend a full team exists.
