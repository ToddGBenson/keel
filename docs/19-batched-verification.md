# 19 — Batched Verification

**Commands:** `/plan` → `/refine` → `/ready` → … → `/qa-gate` `/security-gate`
**Check:** `bash scripts/check-batch-eligibility.sh <epic>` · **Decision:** ADR-0002
**Controls:** SA-11, CA-2, RA-3 (risk-proportional assurance)

Group work into an epic, implement and test each story cheaply, then verify the group once —
deeply — instead of paying full ceremony per story.

## The cost is not where intuition puts it

| | Runs as | Costs |
|---|---|---|
| gitleaks, CodeQL, osv, dependency review | CI jobs | wall-clock minutes, **zero tokens** |
| threat modelling, control verification, exploratory testing, red-teaming | agent sessions | **the tokens** |

Turning down scanners saves minutes and nothing else, while removing the cheapest controls in
the system — including the one whose failure cannot be undone. A leaked credential stays
leaked.

**What gets batched is agent-driven verification.** Scanners keep running on every commit.

## The three tiers

```
every commit   secrets · dependency vetting · guard hooks · unit + functional tests
               cheap, automated, never deferred          ──▶ merge on green

per epic       ONE agent pass over 3-5 stories:
               combined threat surface · control verification · exploratory
               charter · triage of everything accumulated

before G5      deeper testing as the epic warrants (DAST, red-team)
```

This is the middle tier `docs/14` was missing — between "docs typo" (fast lane) and full
ceremony. Ordinary behavioural change that is not security-relevant.

## Why the batched review is *better*, not just cheaper

A review of five related stories together can ask the question a per-story review structurally
cannot: **what did these do to each other?**

An endpoint added in story 3 consuming a field story 1 left unvalidated is invisible when each
is read alone, and obvious when they are read together. Emergent risk lives in the seams. When
running batched, look at the seams first.

You also stop paying context-loading overhead five times, which is most of the token cost of a
small story.

## The line that does not move

**Any story labelled `security-relevant` or `ai-relevant` is ineligible.** It takes G2 up front
and its own G4.

That rule is executable, not written:

```bash
bash scripts/check-batch-eligibility.sh <epic-number>
```

It fails closed, names every disqualifying story, and refuses an epic over 5 stories. It is a
script rather than a checklist line because a prose constraint is advisory (AIC-3) — and this
platform has already shipped defects that prose failed to prevent (POAM-002/003/004, and the
gitleaks allowlist in #32 that read as narrow while silently blinding the scanner).

**Removing a flag to make a group eligible is falsifying a triage decision (PD-7).** If a flag
looks wrong, re-triage it on the issue with a reason recorded.

## The flow

```
/plan                    rank the backlog (RICE from G0), find a COHERENT group,
                         propose 3-5 stories + the deferred list
     │
     ▼  ← YOU approve. Selection is scope, and scope stays human.
epic issue created, stories attached as native sub-issues
     │
/refine <epic>           decompose further if needed
/ready per story         G1 still runs PER STORY — an epic confers no readiness
     │
implement + test         per story, merge on the cheap checks
     │
check-batch-eligibility  ── refused ──▶ verify those stories individually
     │ permitted
/qa-gate + /security-gate  ONE pass over the group
     │
     ▼  G5 unchanged — full evidence chain required to release
```

## What this costs you

**Merged code sits on `main` without the deep pass** until its epic is verified. Contained by
two things: nothing *releases* without G5, and the deferred checks are the deep ones, not the
unrecoverable ones.

**A finding may span three merged stories**, so the fix is bigger than if story one had caught
it. That is the trade, and it is the argument for the cap of 5.

**The G1 risk triage becomes load-bearing.** A story mis-triaged as unflagged is now verified
less deeply, not just missing a G2. `/refine` already says *when uncertain, flag it* — that
guidance protects more than it used to.

## What has no place here

No dates, no velocity, no story points, no capacity, no burn-down. An epic is a grouping, not
an iteration (ADR-0002 D6). Those metrics are excluded platform-wide because measuring them
corrupts the estimates the gates depend on.

"How long will this epic take" has an honest answer: the story count and their sizes.
