# System Security Plan — Outline

**Owner:** Compliance Officer · **Control:** PL-2 · **Status:** template, to be completed
per system

An SSP describes how controls are **actually implemented** for a specific system. This is
the outline; each system gets its own instance.

The failure mode to avoid: an SSP describing an aspirational organization. A plan that
describes a full team, complete automation, and controls nobody has verified will fail its
first real assessment, and it will fail it in a way that damages credibility on the controls
that *were* real.

---

## 1. System identification

Name, unique identifier, version. System owner (a named person). Authorizing official.
Security categorization per FIPS 199 / SP 800-60 — confidentiality, integrity, availability
impact levels, with the reasoning. Operational status. Deployment model.

## 2. System description

Purpose and business function. Users and user types. Data types processed, including personal
and regulated data. System boundary — **state explicitly what is inside and what is not**;
ambiguous boundaries are where control gaps hide. Architecture diagram. External
dependencies and interconnections.

## 3. AI systems (if applicable)

Reference `docs/compliance/ai-inventory.md`. For each AI component: purpose, risk tier, model
and version, provider and contractual data terms, data flows into and out of the model,
guardrails, human oversight points, eval suite location, last red-team date.

Also declare the **AI development tooling** — the agents in this repo — as part of the
development environment, with `docs/11-ai-agent-controls.md` as their control description.
Assessors increasingly ask; declaring it proactively is better than being asked.

## 4. Control implementation

Per control, per `nist-800-53-control-map.md`:

- **Implementation status** — Implemented / Partially / Planned / Alternative / Not Applicable
- **Control origination** — system-specific, inherited, hybrid, or provided by a service
- **Implementation narrative** — how it actually works here, specifically. Not the control
  text restated.
- **Responsible role**
- **Evidence reference**

**"Not Applicable" requires a written justification.** Unjustified N/A is the most common way
a control catalog gets hollowed out, one reasonable-sounding exclusion at a time.

## 5. Roles and separation of duties

Roles per `docs/01-roles.md`, with the actual people holding them.

**Where roles are compressed** — one person holding several — record the compression here
under AC-5, with the compensating control stated: independent agent invocation for
produce/review separation, external review cadence, or a human approver outside the delivery
team. Do not describe a team that does not exist. A recorded compression with a compensating
control is a defensible position; a fictional org chart is not.

## 6. Development lifecycle

Reference this repository. The gates, their approvers, and the evidence each produces
constitute the SA-3 / SA-11 / CM-3 narrative.

## 7. Continuous monitoring

Per `docs/08-operate-and-respond.md` and `docs/06-cicd.md` § Stage 7. Metrics, frequencies,
thresholds, and who reviews what.

## 8. Incident response

Reference `docs/08-operate-and-respond.md`. Contacts, escalation, notification obligations
and their clocks.

## 9. Contingency

RTO and RPO per service. Backup schedule and **restore test** schedule. Rollback capability
and its limits — including any forward-only migrations and their windows.

## 10. Risk posture

Open findings by severity. POA&M summary. Accepted risks with expiry dates. Known limitations.

## 11. Appendices

Control map · POA&M · assessment reports · AI inventory · evidence index · glossary.

---

## Maintenance

The SSP is a living document. Update on: architectural change, new control implementation,
assessment results, incidents that reveal a gap, role changes, **any AI system or model
change**, and quarterly at minimum.

An SSP that has not changed in a year describes a system that has not changed in a year, or
an SSP nobody maintains. It is nearly always the second.
