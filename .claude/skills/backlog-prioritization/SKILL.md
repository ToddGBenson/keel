---
name: backlog-prioritization
description: Rank an open backlog and group the top of it into a coherent epic. Use when deciding what to build next, running /plan, grouping stories for batched verification, or when asked to prioritize issues. Covers ranking from existing RICE scores, coherence over raw rank, and what makes a group verifiable together.
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

The backlog already carries a **RICE score set at G0** (`/idea`). Use it. Do not open a fresh
estimation exercise — re-scoring is where planning turns into ceremony, and the second score is
rarely better than the first.

```
Reach × Impact × Confidence / Effort
```

Then adjust for three things RICE cannot see:

| Adjustment | Why |
|---|---|
| **Dependency order** | A high-RICE story blocked by a low-RICE one is not actually next. Order beats score. |
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

| # | Story | RICE | Flags | Why in this group |
|---|-------|------|-------|-------------------|

Batch-eligible: yes/no — <if no, which stories and why>

## Deferred
| # | Story | Reason (lower value / blocked / not coherent — leads next) |
```

Then stop and ask for approval.

## Controls

SA-3 (lifecycle), SA-4 (requirements), RA-3 (risk assessment), PM-11 (mission/business
process), CM-3 (traceability — the epic is an issue, so parentage is auditable).
