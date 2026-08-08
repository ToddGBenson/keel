---
description: Show where every work item sits against the gates, plus flow, security, and AI assurance health
argument-hint: [optional filter — issue number, label, milestone, or "risks"]
allowed-tools: Read, Grep, Glob, Bash, Task
---

# Status: `$ARGUMENTS`

Delegate to the `delivery-lead` agent. Report the system, not a list.

## Gather

From `gh` (issues, PRs, workflow runs, environments), from `evidence/`, and from
`docs/compliance/poam.md`.

## Report

### 1. Gate board

```
G0 Intake      ▸ 3 ideas awaiting triage (oldest 11d)
G1 Ready       ▸ 5 stories ready  |  2 rejected back to refinement
G2 Design      ▸ 1 in threat modeling (#142)  |  1 awaiting security co-approval (#150, 4d)
G3 Code Cmplt  ▸ 3 PRs open  |  1 awaiting review 3d  ← review latency
G4 Verified    ▸ 2 in QA  |  1 blocked on a High finding (#148)
G5 Release     ▸ v1.4.0 assembled, AWAITING HUMAN AUTHORIZATION
```

### 2. Where work is waiting

Queue time, not work time. In nearly every system queue time dwarfs work time, and it is the
signal that actually points at the bottleneck. Name the longest wait and its cause.

### 3. Flow

Deployment frequency · lead time · change failure rate · time to restore · WIP vs. limits ·
trend arrows against the previous period.

Never report velocity, story points, or per-person commit counts. They are gameable and
measuring them corrupts the estimates the process depends on.

### 4. Risk

- Open security findings by severity, **with anything past SLA called out first**
- POA&M entries past due, and any whose date has been extended more than once — that is a
  resourcing or will problem, not a schedule problem, and it should be named as one
- Open AI findings; eval trend; drift events
- Security exceptions approaching expiry

### 5. Process health

Emergency changes used this period (rising means the normal path is too slow) · exceptions
raised · gates skipped and why · **gate rejection rate by gate** — a gate that never rejects
is ceremony; one that rejects nearly everything is misplaced · retro actions outstanding.

### 6. What needs a human right now

The section to put first when anything is in it:

```
NEEDS A HUMAN
  ▸ v1.4.0 release authorization (G5) — assembled 2 days ago
  ▸ Risk acceptance decision on POA&M-024 (expires in 6 days)
  ▸ Process change PR #219 awaiting approval
```

## Tone

Lead with what is stuck and what is at risk, not with what is going well. A status report
that opens with accomplishments buries the thing the reader needed to act on.

Be specific about age. "Awaiting review" is noise; "awaiting review 3 days, blocking two
downstream stories" is actionable.

If the argument is `risks`, report only sections 4 and 6.
