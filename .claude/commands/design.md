---
description: Run G2 — technical design, ADR, STRIDE threat model, control allocation, and AI impact assessment if applicable
argument-hint: <issue number>
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, WebSearch, Task
---

# G2 — Design & Threat Model: `$ARGUMENTS`

Run the gate in `process/gates/g2-design.md`, per `docs/04-development.md` Part A.

## Required when

The story is flagged security-relevant, privacy-relevant, or AI-relevant, **or** the change
is expensive to reverse. If none apply, record the skip with its reason and stop — a silent
skip is what an assessor finds.

## Run these agents, in parallel where independent

1. **`architect`** — technical approach, ADR if warranted, NFRs, control allocation.
2. **`security-engineer`** — STRIDE threat model on the delta.
3. **`ai-risk-officer`** — AI Impact Assessment. **Required and blocking** if AI-relevant.

Spawn them as **separate agent invocations**. Do not have one agent produce all three — the
independence is the control (AIC-2), and a single reasoning chain producing both the design
and its critique produces neither.

## Skills

Each agent loads its own method — do not restate them here:

- `architect` and `security-engineer` → **`threat-modeling`**
- `ai-risk-officer` → **`ai-impact-assessment`**
- All three, when recording the outcome → **`evidence-writing`**

## Deliverables

**Technical approach** — how it will be built, what changes, what stays. Alternatives
considered and why rejected.

**ADR** (`docs/templates/adr.md`) only if the decision is costly to reverse. Do not write
one otherwise — ADR sprawl devalues the records that matter.

**Threat model** (`docs/templates/threat-model.md`) — per the `threat-modeling` skill.

**Control allocation matrix** — for each control: the **file or component** implementing it,
how it is verified, the evidence artifact.

**Secure design principles (SA-8)** — state where each holds in *this* design, or why it
does not apply. Applied, not recited.

**AI Impact Assessment** (`docs/templates/ai-impact-assessment.md`) if AI-relevant — per the
`ai-impact-assessment` skill.

## Output

```
G2 RESULT: PASS | FAIL
Artifacts: ADR-007, threat-model #142, control-allocation #142, AIA #142
Threats identified: 6  (mitigated 5, accepted 1 → POA&M-023, expires 2026-11-01)
Controls allocated: 4 — all with named component and verification method
Unresolved: none
Approvers required: architect + security-engineer  [+ ai-risk-officer if AI-relevant]
```

## Then

Write artifacts to `evidence/<issue>/g2/`. **Architect and Security co-approve; a human
records it.** Neither approves alone, and the architect does not approve their own design.
