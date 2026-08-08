# 02 — Intake & Discovery (→ G0)

**Owner:** Product Owner · **Command:** `/idea` · **Gate:** `process/gates/g0-intake.md`

## The point

Ideas arrive as solutions ("add a save button"). Discovery's job is to walk them back to
the problem ("users lose 12 minutes of work when a session expires, ~40 times a week"),
because the stated solution is usually not the best one and is never the *cheapest* one.

An idea leaves intake as a **problem statement with evidence and a size**, or it leaves
rejected with a recorded reason. It does not leave as an unranked wish.

## Intake sources

| Source | Route | Notes |
|---|---|---|
| Customer / user request | `idea` issue form | Capture the request verbatim before interpreting it |
| Support ticket trend | `idea` issue, linked tickets | Volume is the evidence |
| Production incident | `bug` or `idea` (if systemic) | Postmortem actions enter here, never skip intake |
| Security finding | `security-finding` form → POA&M | Bypasses backlog prioritization; SLA-driven |
| AI eval regression | `ai-finding` → AI Risk Officer | Treated as a defect class, not a tuning task |
| Dependency / EOL notice | `chore` | SA-22 unsupported components; scheduled, not deferred |
| Team / process friction | `process` label | Feeds `/retro` and `/learn` |
| Compliance gap | POA&M entry → issue | Compliance Officer files; has a due date by definition |

## The discovery record

Produced by `/idea`, stored as a GitHub issue using `.github/ISSUE_TEMPLATE/idea.yml`:

1. **Problem statement** — who, what they cannot do, what it costs them. No solution words.
2. **Evidence** — data, tickets, telemetry, interviews. "Someone asked for it" is evidence
   of a request, not of a problem; say which you have.
3. **Affected population** — how many, which segment, how often.
4. **Current workaround** — what people do today. If there is no workaround and no
   complaint, question whether the problem is real.
5. **Success measure** — the metric that moves if this works, with a current baseline.
   *Without a baseline you cannot later tell whether you succeeded.*
6. **Constraints** — regulatory, technical, contractual, timing.
7. **Relevance flags** — security-relevant? privacy/PII? AI-relevant? These flags determine
   which gates apply and must be set at intake, not discovered at G4.
8. **Options considered** — at least two, including "do nothing" and its cost.

## Sizing for prioritization

Use **RICE** at intake — it is coarse on purpose; precision here is false precision.

```
Score = (Reach × Impact × Confidence) / Effort

Reach       users affected per quarter
Impact      3 massive · 2 high · 1 medium · 0.5 low · 0.25 minimal
Confidence  100% have data · 80% some evidence · 50% informed guess
Effort      person-weeks, rough order of magnitude
```

Two mandatory adjustments:

- **Risk-reduction items** (security findings, EOL components, compliance gaps) are not
  RICE-ranked against features. They enter with an SLA-driven due date from
  `docs/10-definitions.md` § Severity, and the backlog is built around them.
- **Confidence below 50%** routes to a **spike** before it can be ranked. A spike is
  time-boxed, produces a written answer, and produces no production code.

## G0 decision

Product Owner decides, human confirms. Three outcomes, all recorded on the issue:

- **Accept** → enters the backlog, ranked, ready for refinement.
- **Reject** → closed with a reason. Rejection reasons are an asset; they prevent the same
  idea re-entering every quarter. Never close silently.
- **Park** → real problem, wrong time. Given a review date. Parked with no review date is
  rejection wearing a disguise.

**Control mapping:** SA-3(1) (SDLC integration of security), RA-3 (risk assessment inputs),
PM-30 (supply chain risk consideration at intake), and — when the AI-relevant flag is set —
NIST AI RMF **MAP 1–5** (context and impact established before development).
