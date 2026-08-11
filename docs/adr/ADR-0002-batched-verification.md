# ADR-0002: Epics as the batching unit for selection and verification

**Status:** Accepted
**Date:** 2026-08-11
**Deciders:** platform owner (human), with agent-drafted analysis
**Related:** ADR-0001, `process/gates/g4-verified.md`, `docs/14-fast-lane.md`,
`docs/19-batched-verification.md`, issue #34

## Context

Two problems turned out to have one answer.

**Nothing produced an epic.** `/refine` takes `<idea id, epic id, or issue number>` and the
`story-splitting` skill opens with "Split an epic or oversized story". Both consumers expect
an epic to arrive; no command created one. The backlog had a per-item path (`/idea` → G0 →
`/refine` → `/ready` → G1) and no pass that looked across items and decided what was next.

**Verification cost was not risk-proportional.** G4 runs per story: threat model, control
verification, exploratory charter, scan triage. For a story touching no security-, AI-, or
privacy-relevant path, that verification costs more than the implementation. `docs/09` already
names the consequence — a process too expensive for its smallest unit is a process people
route around, and a routed-around process is worse than a smaller one that is followed.

`docs/14` had already established **tiered rigor** for trivial changes (the fast lane). What
was missing was a tier between "docs typo" and "full ceremony": ordinary behavioural change
that is not security-relevant.

## Decisions

### D1 — The epic is the batching unit for both selection and verification

An epic is a GitHub issue with its stories attached as **native sub-issues**, produced by
`/plan` from the open backlog and approved by the human before creation.

It carries two jobs, and it is deliberate that they are the same object: the group of stories
you decided to build together is the group whose combined attack surface is worth reviewing
together. Splitting selection from verification would create two batching boundaries that
drift apart.

**Rejected:** milestones (imply a date), a label (no parent/child, no rollup), task lists
(not queryable). Native sub-issues give queryable parentage and a progress summary.

### D2 — Verification moves from per story to per epic, for eligible stories only

| Runs | What | Cost |
|---|---|---|
| Every commit | secrets, dependency vetting, guard hooks, unit + functional tests | seconds, no tokens |
| Per epic | combined threat surface, control verification, exploratory testing, accumulated scan triage | one agent session for N stories |
| Before G5 | deeper testing as the epic warrants | as needed |

The reasoning is not only cost. **An agent reviewing five related stories together sees
interactions that per-story review structurally cannot.** Emergent risk lives in the seams —
story 3's new endpoint consuming story 1's unvalidated field is invisible when each is
reviewed alone. Batching the review is how that is found.

Batching also stops paying fixed context-loading overhead N times, which is most of the token
cost of a small story.

### D3 — Automated scans are NOT what gets reduced

Stated explicitly because the intuition runs the other way. Scanners run as CI jobs: they cost
wall-clock minutes and **zero tokens**. Reducing them saves nothing that matters and removes
the cheapest controls in the system — including secret scanning, where the failure mode is
unrecoverable. A leaked credential cannot be un-leaked.

What is batched is **agent-driven verification**. That is where the tokens are.

### D4 — Flagged stories are ineligible, and that is enforced mechanically

Any story labelled `security-relevant` or `ai-relevant` is ineligible for batching. It gets
G2 up front and its own G4.

This is enforced by `scripts/check-batch-eligibility.sh`, which reads the epic's children from
the API and fails the gate if any carries a disqualifying flag. **It is not enforced by a
sentence in a checklist.** Prompt- and prose-level constraints are advisory (AIC-3), and this
platform has already shipped defects that a prose constraint failed to prevent (POAM-002/003/
004, and the over-broad gitleaks allowlist in #32 that read as narrow and was not).

The triage that sets those flags already exists in `/refine`. This decision gives it teeth: the
flag is now what determines whether verification is paid per story or per epic.

### D5 — Batch size is capped at 5

A review of ten stories is a formality wearing a review's clothes. Five is roughly the point
where an agent can still hold the combined surface in one context, and it bounds how much
merged-but-undeeply-verified code accumulates. Enforced by the same script.

### D6 — No time-boxing, no velocity, no points

An epic is a *grouping*, not an iteration. It has no date, no capacity, and no burn-down.
ADR-0001 and `docs/00-overview.md` exclude velocity and story points as anti-metrics because
measuring them corrupts the estimates the gates depend on; nothing here reopens that.

If "what shipped in August" is wanted later, that is a query, not a ceremony.

## Consequences

**Accepted risk.** Code merges to `main` having passed only the cheap checks, and sits there
until its epic's verification pass. Two things contain it: nothing *releases* without G5, which
is unchanged and still requires the full evidence chain; and the deferred checks are the deep
ones, not the unrecoverable ones.

**A finding at epic level may span three merged stories**, so the fix is larger than if it had
been caught in story one. That is the trade being bought, and it is the main argument for the
cap in D5.

**The `security-relevant` triage at G1 becomes load-bearing.** Previously a missed flag meant a
G2 that should have happened did not. Now it also routes a story into the cheaper lane. A story
mis-triaged as unflagged is verified less deeply than it should be. `/refine` already says
"when uncertain, flag it — an unnecessary G2 costs an hour, a missed one costs a release";
that guidance now protects more than it did.

**This is a gate-model change and is recorded as one.** `process/gates/g4-verified.md` gains a
batched mode. The gate did not get weaker: the same items are assessed, over a group rather
than an item, with an eligibility test that did not exist before.
