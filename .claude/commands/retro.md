---
description: Run a retrospective that ends in at most two committed changes, not a list of intentions
argument-hint: <sprint id, release version, or incident id>
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, Task
---

# Retrospective: `$ARGUMENTS`

Delegate facilitation to the `delivery-lead` agent. Per
`docs/09-retrospective-and-improvement.md`.

**Load `retro-facilitation`** — it carries the structure, the facilitation moves, and the
anti-patterns. For an incident, load **`blameless-postmortem`** instead.

## The rule

> **A retro ends in a merged pull request, or it did not happen.**

Every actionable item converts into one of five things, or it is a feeling:

| Change type | Lands in |
|---|---|
| Process rule | `docs/`, `process/gates/` |
| Automated check | `.github/workflows/`, `.claude/settings.json` |
| Agent behavior | `.claude/agents/`, `.claude/commands/` |
| Control / evidence gap | `docs/compliance/`, POA&M |
| Work to do | A GitHub issue with an owner and a date |

Feelings are worth hearing — they are how the problem gets found. But the retro is not over
until each has been converted or consciously recorded as accepted.

## 1. Gather data — facts before opinions

Otherwise the loudest opinion becomes the fact. Pull actual numbers:

- **Flow**: deployment frequency, lead time, change failure rate, time to restore, queue
  time by state
- **Quality**: escaped defects, **gate rejection rate by gate**, flaky tests, PR review latency
- **Security**: new findings by severity, MTTR, anything past SLA
- **AI assurance**: eval pass rate, drift events, agent gate rejections, red-team findings
- **Process health**: emergency changes used, exceptions raised, gates skipped and why
- **Timeline**: what actually happened, including the parts nobody enjoyed

## 2. Generate insight

The part usually rushed, and the only part that matters. Take the two or three most costly
items and ask *why* until you reach a **condition you can change**. Stop at conditions, never
at people.

Three questions that reliably surface real material:

- **What did we get away with?** Where were we lucky rather than good? Luck is not a control
  and will not recur.
- **What did we work around?** A routed-around process is a broken process advertising
  itself. Route-arounds are evidence, never misconduct.
- **What surprised us?** Surprise is the gap between the model and reality.

Plus the sharpest question this process asks of itself:

- **What reached production that a gate should have stopped — and which gate was it?**

## 3. Decide

**Pick at most two.** Teams that leave with eight complete none; teams that leave with two
complete both and compound. Each gets an owner, a due date, an issue, and the named artifact
it will change.

## 4. Close the previous loop

Review the last retro's actions **first-class**: done, not done, or **dropped** — and dropped
is a legitimate answer said out loud. Carrying dead items forward is how the list becomes
wallpaper.

## Blameless

For incident retros especially: the analysis stops at conditions, not at people. "The
engineer deployed without checking" is a restatement of the event, not a cause. The causes
are what made that action easy, what made the wrong outcome invisible, and what let a single
mistake reach production. Those have fixes. Blame does not.

## Output

Write to `evidence/retros/<id>/retro.md`:

```
RETRO: sprint-23

Data:
  Lead time 4.2d (↑ from 3.1)  |  CFR 18% (↑ from 9%)  |  MTTR 42min
  Gate rejections: G1 2/9, G3 4/9, G4 1/9  |  Escaped defects: 2
  Emergency changes: 3 (↑ from 0)  ← signal

Insight:
  Emergency path used 3× because staging deploys were queued behind a 40-min
  CI run; the normal path was slower than the incident clock. The emergency
  door is being used because the normal door is too slow — widening it would
  be the wrong fix.

Actions (2):
  1. Split CI: run affected tests on PR, full suite on merge.
     Owner: <name>  Due: 2026-08-21  Artifact: .github/workflows/ci.yml  Issue: #221
  2. Add a stop-condition to the developer agent for repeated CI timeouts.
     Owner: <name>  Due: 2026-08-14  Artifact: .claude/agents/developer.md  Issue: #222

Previous actions: 1 done, 1 dropped (deliberately — the problem stopped recurring)
```

## Then

Run **`/learn`** to convert these into actual diffs. A retro record with no follow-on PR is
the failure mode this whole structure exists to prevent.
