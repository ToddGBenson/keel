# Postmortem — INC-<n>: <short title>

**Severity:** SEV<n> · **Date of incident:** · **Author:** · **Published:** *(within 5
business days)* · **Controls:** IR-4, IR-5, CA-7

> **Blameless.** The analysis stops at conditions, not at people. "The engineer deployed
> without checking" is a restatement of the event, not a cause. The causes are what made that
> action easy, what made the wrong outcome invisible, and what let a single mistake reach
> production. Those have fixes. Blame does not — and it guarantees the next postmortem gets
> less honest data.

## Summary

Three sentences. What broke, who was affected, how long.

## Impact

| | |
|---|---|
| Users affected | number and segment |
| Duration | detection → mitigation → full resolution |
| Data impact | loss, exposure, corruption — or none, stated explicitly |
| Financial / contractual | SLA breach, credits, obligations |
| Regulatory | notification assessed? outcome? |

## Timeline

Recorded **as it happened** by the scribe, not reconstructed afterward — reconstruction is
where the truth quietly changes.

| Time (UTC) | Event | Source |
|---|---|---|
| | Change deployed | |
| | First user impact | |
| | **First detection** | |
| | Incident declared, IC assigned | |
| | Mitigation applied | |
| | Full resolution | |

**Detection gap:** impact → detection = ____. This number is usually the most actionable one
in the document.

## What happened

The technical narrative. Enough for a reader who was not there to follow the mechanism.

## Contributing conditions

**Plural.** Single-cause incidents are rare; if you found one, the search probably stopped
early. Ask *why* until you reach something changeable.

| # | Condition | Why it existed | Changeable? |
|---|---|---|---|
| 1 | | | |

Useful lenses: what made the wrong action easy · what made the wrong outcome invisible · what
allowed one mistake to reach production · what monitoring should have caught it · **which
gate should have stopped this, and why did it not?**

## What went well

Name it deliberately. Things that worked are protected by being noticed; they erode silently
otherwise.

## What was luck

**The most important section, and the one most often omitted.** Where were we lucky rather
than good? Luck is not a control and will not recur.

Examples: "it happened at 2 p.m., not 2 a.m." · "the on-call engineer happened to have
context on that subsystem" · "the blast radius was limited because a feature flag was still
partially rolled out."

## Where the process worked or failed

- Did the gates catch anything? Should they have?
- Was the runbook accurate and findable?
- Did alerting fire, and was it actionable?
- Was rollback available and did it work?
- If AI was involved: did guardrails fire? Did evals miss this? **Every AI incident becomes
  an eval case.**

## Action items

Every one has an owner, a due date, and an issue. Postmortem actions enter the backlog through
normal intake with elevated priority.

| # | Action | Type | Owner | Due | Issue |
|---|---|---|---|---|---|
| 1 | | detect / prevent / mitigate / process | | | |

Prefer **prevent** over **detect** over **mitigate** — but detection improvements are usually
cheaper and land faster, so do not let the perfect prevention item block the detection one.

**An action list with no issues behind it is a document that will be read once.**

## Feeding the loop

Run `/learn` against this postmortem. Every action must land as a doc change, a CI check, an
agent definition change, a compliance update, or an issue — per
`docs/09-retrospective-and-improvement.md`.
