---
name: backlog-prioritization
description: Rank an open backlog and group the top of it into a coherent epic. Use when deciding what to build next, running /plan, grouping stories for batched verification, or when asked to prioritize issues. Covers ranking ideas from existing RICE scores and defects from their recorded severity (never a common scale), coherence over raw rank, and what makes a group verifiable together.
---

# Backlog prioritization

Consumers: `product-owner`, `delivery-lead`, `/plan`, ADR-0002.

## Prioritization is selection, and selection is a human decision

You produce a **ranked slate with reasoning**. A human picks. This is not deference for its own
sake — deciding what to build is a scope judgement, and scope is the boundary the unattended
runner is forbidden to cross (P2, `docs/18`). A command that ranked *and* committed would walk
back through that boundary from the other side.

Present the recommendation confidently. Do not create the epic until told.

## Rank from what you already have

Every item on the backlog arrived through an intake route, and each route records its own
ranking input. **Rank each item on the input its route recorded — never on one you made up.**
Re-scoring is where planning turns into ceremony, and a score nobody assessed is worse: it is a
fabricated input dressed as a recorded decision (PD-7).

| Kind | Intake route | Recorded input | Path |
|---|---|---|---|
| **Idea / story** | `/idea` → G0 | RICE score on the issue | `RICE` |
| **Defect** | `bug.yml` | Severity field from the bug form, plus its scope-of-impact and flags | `Severity` |
| **Security finding, compliance gap, EOL** | `security-finding` / POA&M / `chore` | SLA due date from `docs/10-definitions.md` § Severity | `SLA` |

### Ideas — RICE from G0

The backlog already carries a **RICE score set at G0** (`/idea`). Use it.

```
Reach × Impact × Confidence / Effort
```

An idea with no RICE never passed G0. It is not eligible for planning — it is eligible for
`/idea`. Say so in the slate.

### Defects — recorded severity, not RICE

A bug filed through `bug.yml` never passes `/idea`, so it never has a RICE score, and it should
not: G0 says risk-reduction work is not RICE-ranked against features. **Never back-fill a RICE
score for a defect.** Rank defects on the severity recorded on the bug form:

1. **Severity** — Blocker › Major › Minor (`docs/10-definitions.md` § Severity).
2. Within a severity, the **data loss** or **data exposed** flag ranks first.
3. Then the recorded **scope of impact** — more users, a core segment, longer-standing, first.

A defect with no recorded severity does not meet the bug Definition of Ready. Say so and route
it back to triage; do not assign one yourself to make it rankable.

A defect ticked **security-relevant** is a security finding in disguise: it takes the `SLA`
path, with severity set from realistic exploitability (`scanner-triage`), not the bug-form
dropdown.

### Security findings, compliance gaps, EOL — the SLA date

These bypass ranking (`docs/02`). They are listed in due-date order at the top of the slate as
constraints the plan must fit around, not candidates competing with features.

### No common scale across kinds

A RICE score and a defect severity measure different things. There is **no common scale** that
makes "RICE 240" comparable to "Major, ~30 users" — and inventing a conversion factor is just a
fabricated score one step removed. So:

- Rank **within each kind** only, and present the kinds as separate lists.
- State the **path** for every item in the slate, so nobody reads a mixed table as one ranking.
- **Interleaving across kinds is the human's call**, made when they approve the slate. Your
  recommendation may say which you would take first and why — in words, not in a number.

An epic may still mix kinds when they share a surface (coherence, below); the per-item path
column keeps that honest.

### Adjustments, on every path

Then adjust for three things no recorded score can see:

| Adjustment | Why |
|---|---|
| **Dependency order** | A high-ranked item blocked by a low-ranked one is not actually next. Order beats score. |
| **Risk flags** (`security-relevant`, `ai-relevant`) | These carry a mandatory G2 and cannot be batch-verified (ADR-0002). Real cost, not a tiebreak. |
| **Decay** | An issue open for months with no movement is either mis-scored or not actually wanted. Say which. |

## Coherence beats rank

**The top N by score is usually the wrong epic.** A group of unrelated high scorers is a list,
not an epic, and it produces exactly the verification problem batching is meant to solve — five
disconnected attack surfaces reviewed in one pass, with no seams worth looking at.

Prefer a group that shares a **surface**: the same component, the same data, the same user
journey, the same trust boundary. Then the batched review can ask the question only a batched
review can — *what did these do to each other?*

A slightly lower-ranked but coherent group beats a higher-ranked scatter. Say when you made
that trade and why.

## Sizing the group

Three to five stories. Below three, batching saves little over doing them individually. Above
five, the combined surface stops fitting in one review and the pass degrades into a formality
(ADR-0002 D5, enforced by `scripts/check-batch-eligibility.sh`).

Flagged stories do not count toward a batch because they are not in one — they are verified
individually. If the coherent group is mostly flagged, that is a signal the whole group belongs
in the full-ceremony lane, and saying so is the right answer.

## The deferred list is not optional

Every slate names what was **not** selected and why. A plan that shows only the chosen work
hides the decision, and the decision is the entire product of this exercise.

Three honest reasons to defer, and they are different: *lower value* · *blocked by something*
· *not coherent with this group, will lead the next one*. The third is not a demotion, and
labelling it as one loses information.

## What this deliberately does not do

**No dates. No velocity. No story points. No capacity.** An epic is a grouping, not an
iteration (ADR-0002 D6). Those metrics are excluded platform-wide because measuring them
corrupts the estimates the gates depend on — see `docs/00-overview.md` § Anti-metrics.

If asked how long the epic will take, the honest answer is the story count and their
individual sizes, not a date derived from a velocity that does not exist.

## Output shape

```
## Recommended epic — <name>
<one line: the shared surface that makes these one group>

| # | Story | Path | Score | Flags | Why in this group |
|---|-------|------|-------|-------|-------------------|

Path is `RICE`, `Severity`, or `SLA`; Score is the recorded value for that path (a RICE number,
Blocker/Major/Minor, or a due date). Never a number converted from another path.

Batch-eligible: yes/no — <if no, which stories and why>

SLA-bound items (constraints, not candidates): <# — due date>, or "none"

## Deferred
| # | Story | Path | Reason (lower value / blocked / not coherent — leads next / not rankable — why) |
```

Then stop and ask for approval.

## Controls

SA-3 (lifecycle), SA-4 (requirements), RA-3 (risk assessment), PM-11 (mission/business
process), CM-3 (traceability — the epic is an issue, so parentage is auditable).
