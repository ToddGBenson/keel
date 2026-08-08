# 00 — Lifecycle Overview

## What this process is trying to prevent

Most delivery processes fail in one of four ways, and every gate here exists to block a
specific one:

| Failure mode | Where it gets caught |
|---|---|
| Building the wrong thing, expensively | G0 Intake, G1 Ready — a problem statement and measurable acceptance criteria before a line of code |
| Building the right thing insecurely | G2 Design, G4 Verified — threat model up front, control verification before merge |
| Shipping something nobody verified | G3, G4 — independent review and test evidence, produced by identities other than the author |
| Learning nothing when it goes wrong | Retro loop — every finding must land as a committed change to a doc, a check, or an agent |

A fifth, newer failure mode — *shipping AI features whose behavior nobody characterized* —
is caught at G2 and G4 by the AI Risk Officer. See `docs/12-ai-feature-governance.md`.

## The flow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│ DISCOVER                                                                        │
│   raw idea ──▶ problem statement ──▶ opportunity sized ──▶ [G0] accepted        │
│   owner: Product Owner                            evidence: idea issue, RICE     │
└────────────────────────────────────┬────────────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ REFINE                                                                          │
│   epic ──▶ INVEST stories ──▶ acceptance criteria ──▶ sized ──▶ [G1] ready      │
│   owner: Product Owner + Delivery Lead        evidence: DoR checklist on issue   │
└────────────────────────────────────┬────────────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ DESIGN                       (required when security-relevant or AI-relevant)    │
│   approach ──▶ ADR ──▶ threat model ──▶ control allocation ──▶ [G2]             │
│   owner: Architect + Security + AI Risk       evidence: ADR, STRIDE table, AIA   │
└────────────────────────────────────┬────────────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ BUILD                                                                           │
│   failing test ──▶ implementation ──▶ self-check ──▶ PR ──▶ [G3] code complete  │
│   owner: Developer, reviewed by another identity   evidence: PR, CI run, review  │
└────────────────────────────────────┬────────────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ VERIFY                                                                          │
│   test execution ──▶ security verification ──▶ AI evals ──▶ [G4] verified       │
│   owner: QA + Security + AI Risk         evidence: results, SARIF, SBOM, evals   │
└────────────────────────────────────┬────────────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ RELEASE                                                                         │
│   change record ──▶ readiness review ──▶ [G5] human authorization ──▶ deploy    │
│   owner: Release Manager + human      evidence: CR, attestation, approval, notes │
└────────────────────────────────────┬────────────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ OPERATE                                                                         │
│   monitor ──▶ detect ──▶ respond ──▶ vulnerability + drift management            │
│   owner: whole team          evidence: alerts, incident records, scan history    │
└────────────────────────────────────┬────────────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ IMPROVE                                                                         │
│   retro / postmortem / gate-failure analysis ──▶ committed change                │
│   owner: Delivery Lead              evidence: merged PR against process artifacts│
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Gate mechanics

A gate is three things. Anything less is theater.

1. **A checklist** with binary items — each either points at an artifact or it does not.
   Lives in `process/gates/`.
2. **An approver** who is a *different identity* than the producer. Enforced by CODEOWNERS
   and branch protection, not by convention.
3. **An evidence record** written to `evidence/<work-item>/<gate>/` and indexed by the
   control it satisfies.

Gates are not stage-gates in the waterfall sense — they do not require the whole release
to move together. A single story passes G1→G5 on its own timeline. What the gate enforces
is *sequence of assurance*, not batch size.

### Tailoring

Not every item needs every gate. Tailoring is allowed, pre-declared, and recorded:

| Item type | G0 | G1 | G2 | G3 | G4 | G5 |
|---|---|---|---|---|---|---|
| Feature story | ✔ | ✔ | if security- or AI-relevant | ✔ | ✔ | ✔ |
| Bug (non-security) | — | ✔ (abbreviated) | — | ✔ | ✔ | ✔ |
| Security fix | — | ✔ | ✔ | ✔ | ✔ | ✔ (expedited path) |
| Spike / research | ✔ | ✔ | — | — | — | — (output is a doc, not code) |
| Chore / dependency bump | — | — | — | ✔ | ✔ (automated) | ✔ |
| AI feature or model change | ✔ | ✔ | ✔ **mandatory** | ✔ | ✔ **+ evals** | ✔ |

The expedited security path (`docs/07-release-and-change.md` § Emergency Change) compresses
timing but removes **no** control — post-hoc evidence is completed within 72 hours or the
change is reverted.

## Cadence

| Ceremony | Frequency | Facilitator | Output artifact |
|---|---|---|---|
| Intake triage | Weekly | Product Owner | Accepted/rejected ideas, sized |
| Refinement | Twice weekly | Product Owner | Stories at G1 |
| Planning | Per sprint | Delivery Lead | Committed sprint scope |
| Daily sync | Daily | Delivery Lead | Impediment log updates |
| Security review | Continuous + weekly sweep | Security Engineer | Findings, POA&M updates |
| Release readiness | Per release | Release Manager | Change record, authorization |
| Retrospective | Per sprint | Delivery Lead | **A merged PR**, not notes |
| Control assessment | Quarterly | Compliance Officer | Assessment report, POA&M |
| AI eval review | Per AI change + monthly | AI Risk Officer | Eval report, drift analysis |

## Metrics that actually drive decisions

Track few, act on all of them. Metrics nobody acts on are surveillance, not measurement.

**Flow (DORA):** deployment frequency · lead time for change · change failure rate ·
time to restore. Reported per sprint in the retro.

**Quality:** escaped defect rate · gate rejection rate by gate (a gate that never rejects
is not a gate) · flaky test count · mean PR review latency.

**Security:** mean time to remediate by severity (Critical ≤7d, High ≤30d, Medium ≤90d) ·
open findings aging past SLA · % of stories with completed threat models · secrets
detected pre-commit vs. post-commit.

**AI assurance:** eval pass rate per release · red-team finding count and severity ·
model/prompt drift incidents · % AI-authored code that failed review vs. human-authored
(this one is diagnostic, not punitive — it calibrates review depth).

**Anti-metrics — never track as targets:** velocity, story point totals, lines of code,
individual commit counts. They are trivially gamed and measuring them corrupts the
estimates the process depends on.

## Reading order

1. This document
2. `01-roles.md` — who is accountable for what
3. `10-definitions.md` — DoR, DoD, severity, and the vocabulary the gates use
4. `process/gates/g1-ready.md` — the gate you will meet first
5. `compliance/nist-800-53-control-map.md` — how it all maps to the catalog
