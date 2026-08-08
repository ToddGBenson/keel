---
name: blameless-postmortem
description: Run a blameless postmortem that produces changed conditions rather than blame or intentions. Use after a SEV1 or SEV2 incident, after a near-miss, after an AI incident, or when asked to analyse what went wrong and why. Covers timeline discipline, contributing-conditions analysis, and the "what was luck" section.
---

# Blameless postmortem

Consumers: incident participants, `delivery-lead`, `/retro`, `/learn`,
`docs/08-operate-and-respond.md`, `docs/templates/postmortem.md`.

Required for SEV1 and SEV2, and worth the hour for any near-miss. Published within five
business days — later than that and the details are already reconstructions.

## What blameless actually means

Not "be nice about it". It means **the analysis stops at conditions, not at people**, because
conditions are the only thing you can change.

> "The engineer deployed without checking" is a restatement of the event, not a cause.

The causes are: what made that action easy · what made the wrong outcome invisible · what
allowed one mistake to reach production. Those have fixes. Blame does not — and blame
guarantees the next postmortem gets worse data, permanently, because everyone present learns
what happens when you volunteer detail.

**The person acted reasonably given what they knew at the time.** Start from that as a
working assumption. If it turns out to be false, that is a management conversation, not a
postmortem — do not conflate the two, because doing so destroys the postmortem's ability to
function for everyone else.

## Timeline

Recorded **as it happens** by the scribe during the incident, not assembled afterward.
Reconstruction is where the truth quietly changes: memory smooths, motives get retrofitted,
and the confusing forty minutes become a clean narrative that teaches nothing.

| Time (UTC) | Event | Source |
|---|---|---|
| 14:02 | Change deployed | run #4821 |
| 14:09 | First user impact | error rate graph |
| **14:31** | **First detection** | PagerDuty |
| 14:34 | Incident declared, IC assigned | Slack |
| 14:52 | Mitigation applied | run #4823 |
| 15:20 | Full resolution | |

**Detection gap = impact → detection.** Here, 22 minutes. This is usually the most actionable
number in the whole document, and it is frequently the one nobody calculates.

## Contributing conditions — plural

Single-cause incidents are rare. If you found one, the search stopped early.

Ask *why* until you reach something you can change. Stop at a condition, not a person.

```
Users could not save drafts
  ← the write path returned 500
    ← the connection pool was exhausted
      ← a new query held connections for 30s
        ← the query was unindexed on a table that grew 40x since the index was designed
          ← nobody re-examines index coverage as data grows      ← CONDITION
        ← the load test runs against a 10k-row fixture           ← CONDITION
      ← pool exhaustion had no alert                             ← CONDITION
```

Three conditions, three fixes, from one incident. Stopping at "bad query" would have produced
one fix and the same incident again in a different query.

Useful lenses: what made the wrong action easy · what made the wrong outcome invisible · what
let one mistake reach production · what monitoring should have caught it · **which gate should
have stopped this, and why did it not?**

That last question is the sharpest one this process asks of itself.

## What went well

Name it deliberately. Things that worked are protected by being noticed and erode silently
otherwise — the runbook that was accurate, the rollback that was rehearsed, the alert that
fired correctly. If you only ever analyse failure, you will optimise away the things that
saved you.

## What was luck

**The most important section, and the one most often omitted.**

Where were we lucky rather than good? Luck is not a control and will not recur.

> - It happened at 2 p.m., not 2 a.m. The detection gap would have been hours overnight.
> - The on-call engineer happened to have built that subsystem. The next one will not.
> - Blast radius was limited because the feature flag was still at 20% rollout — that was
>   a coincidence of timing, not a decision.

Each of those is a finding. "We were lucky the right person was on call" means the runbook is
inadequate, and that is actionable in a way that the incident's proximate cause is not.

## Action items

Every one has an **owner** (a named person, not a team), a **due date**, and an **issue**.
Postmortem actions enter the backlog through normal intake with elevated priority.

Prefer, in order: **prevent** > **detect** > **mitigate**. But do not let a perfect prevention
item block a cheap detection one — detection usually lands in days and prevention in months,
and the detection improvement protects you during the wait.

**An action list with no issues behind it is a document that will be read once.**

Be realistic about count. Five well-owned actions beat fifteen aspirational ones; the
fifteen-item list is how a team learns that postmortem actions are decorative.

## AI incidents

Same process, with the AI Risk Officer required. Additionally:

- **Every AI incident becomes an eval case.** This is how the suite earns its keep, and it is
  the difference between a system that learns and one that regresses in a new way each quarter.
- Record model version, prompt version, and grounding source version as they were at the time.
- Ask whether the guardrail fired, did not exist, or fired and was bypassed. Three different
  fixes.
- Ask whether evals should have caught it — and if they could not have, say so; that is a
  statement about the limits of the eval suite and belongs in the record.

## Security incidents

**Preserve evidence before remediating.** Snapshot, then fix. Remediating first destroys the
forensic record, and the pressure to fix immediately is exactly what makes this rule
necessary.

Assess notification obligations against the clock that applies (IR-6). The disclosure decision
belongs to a human with authority, not to the responders.

## Feeding the loop

Run `/learn` against the postmortem. Every action lands as a doc change, a CI check, an agent
definition change, a compliance update, or an issue. See
`docs/09-retrospective-and-improvement.md`.

## Controls

IR-4 (incident handling) · IR-5 (incident monitoring) · IR-6 (reporting) · IR-8 · CA-7 ·
SA-15 (process improvement) · AI RMF MANAGE 4.3.
