---
name: retro-facilitation
description: Facilitate a retrospective that ends in committed changes rather than intentions. Use when running a sprint retro, release retro, gate-failure analysis, or process health review, or when asked to reflect on how work went. Covers the data-first structure, the three surfacing questions, and the cap-at-two rule.
---

# Retro facilitation

Consumers: `delivery-lead`, `/retro`, `/learn`,
`docs/09-retrospective-and-improvement.md`.

## The rule that makes it work

> **A retrospective ends in a merged pull request, or it did not happen.**

Retros fail everywhere for the same reason: they produce sentiment and intentions, intentions
decay, the same problems recur, and within a quarter people treat the meeting as a tax.

The fix is structural, not motivational. Every actionable item converts into one of five
things:

| Change type | Lands in |
|---|---|
| Process rule changed | `docs/`, `process/gates/` |
| An automated check added | `.github/workflows/`, `.claude/settings.json` |
| An agent's behavior corrected | `.claude/agents/`, `.claude/commands/`, `.claude/skills/` |
| A control or evidence gap closed | `docs/compliance/`, POA&M |
| Work to be done | A GitHub issue with an owner and a date |

If an item cannot be one of those five, it is a feeling. Feelings are worth hearing — they are
how the problem gets found — but the retro is not over until each has been converted or
consciously recorded as accepted.

## Structure — 60 to 75 minutes

### 1. Set the stage (5 min)

State the frame aloud: **we examine the system, not the people.**

Then check safety honestly. If the last three retros produced **no criticism of the process
or of leadership**, the retro is not safe and the data coming out of it is worthless. Name
that out loud rather than proceeding to collect polite noise.

### 2. Gather data (15 min)

**Facts before opinions**, or the loudest opinion becomes the fact. Bring numbers:

- **Flow** — deployment frequency, lead time, change failure rate, time to restore, **queue
  time by state**
- **Quality** — escaped defects, **gate rejection rate by gate**, flaky tests, PR review latency
- **Security** — new findings by severity, MTTR, anything past SLA
- **AI assurance** — eval pass rate, drift events, agent gate rejections, red-team findings
- **Process health** — emergency changes used, exceptions raised, gates skipped and why
- **Timeline** — what actually happened, including the parts nobody enjoyed

Queue time is usually the most revealing number and the one nobody tracks. In most systems it
dwarfs work time.

### 3. Generate insight (25 min)

The part that gets rushed and the only part that matters. Take the **two or three most costly
items** and ask *why* until you reach a condition you can change. Stop at conditions, never at
people.

Three questions that reliably surface real material:

**What did we get away with?** Where were we lucky rather than good? Luck is not a control and
will not recur.

**What did we work around?** A routed-around process is a broken process advertising itself.
Route-arounds are always evidence, never misconduct — and treating one as misconduct once
guarantees you never hear about another.

**What surprised us?** Surprise is the gap between the model and reality. Close the gap.

Plus the one this process asks of itself: **what reached production that a gate should have
stopped, and which gate was it?**

### 4. Decide (20 min)

**Pick at most two.**

Teams that leave with eight actions complete none; teams that leave with two complete both
and compound. This is the single highest-leverage facilitation decision, and it will feel
wrong every time — there will be six good candidates. Pick two anyway.

Each gets: owner (a named person), due date, an issue, and the **named artifact it will
change**.

### 5. Close (5 min)

Review the previous retro's actions **first-class**: done, not done, or **dropped** — and
dropped is a legitimate answer said out loud, far better than carrying dead items forward
until the list becomes wallpaper.

Then rate the retro itself. A retro nobody finds useful should be changed or stopped.

## Facilitation moves that work

**Silent writing before discussion.** Everyone writes for three minutes before anyone speaks.
Kills anchoring and gets the quiet people's material into the room.

**Ask the quiet person directly**, by name, once. Not repeatedly — once, with a real question.

**"Say more about that"** on the item said quickly and moved past. That is usually the one
that matters.

**Convert complaints into conditions.** "Reviews take forever" → "what specifically waits, and
on what?" → a measurable queue time and a fixable cause.

**Interrupt problem-solving during data gathering.** The room will want to fix the first
thing mentioned. Note it, park it, keep collecting — the first thing mentioned is rarely the
most expensive.

## Anti-patterns

**The blame retro.** Once someone is criticised by name, honest data stops. Permanently.
**The complaint session.** Venting without conversion produces learned helplessness.
**The action-item graveyard.** No owner, no date, no issue. Cap at two.
**Skipping it when busy.** Busy is precisely when the process is breaking down.
**The same facilitator forever.** Rotate; every facilitator has blind spots.
**Only reviewing failures.** What went well erodes silently unless deliberately protected.
**The compliance-only retro.** If it exists to generate CA-7 evidence, it will generate
evidence and no improvement. The evidence is a by-product of doing it for real.

## Then

Write the record to `evidence/retros/<id>/retro.md`, then run **`/learn`** to convert the
actions into actual diffs.

Remember that agent-definition changes which **relax** a control need the same approval as
relaxing a pipeline gate — that is the quietest way to weaken the system (AIC-8).

## Controls

CA-7 (continuous monitoring) · SA-15 (development process improvement) · PM-31 ·
AI RMF GOVERN 4.3, MANAGE 4.1.
