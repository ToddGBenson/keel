# 09 — Retrospective & Continuous Improvement

**Owner:** Delivery Lead · **Commands:** `/retro`, `/learn`
**Controls:** CA-7 (continuous monitoring), SA-15 (development process improvement),
PM-31, AI RMF **GOVERN 4.3 / MANAGE 4.1** (feedback and improvement)

## The one rule

> **A retrospective ends in a merged pull request, or it did not happen.**

Retros fail everywhere for the same reason: they produce sentiment and intentions, the
intentions decay, the same problems recur, and within a quarter people treat the meeting as
a tax. The fix is structural, not motivational — the output artifact is a **diff**, against
one of:

| Change type | Lands in |
|---|---|
| Process rule changed | `docs/`, `process/gates/` |
| An automated check added | `.github/workflows/`, `.claude/settings.json` hooks |
| An agent's behavior corrected | `.claude/agents/`, `.claude/commands/` |
| A control or evidence gap closed | `docs/compliance/`, POA&M |
| Work to be done | A GitHub issue with an owner and a date |

If a discussion item cannot be expressed as one of those five, it is a feeling. Feelings are
worth hearing — they are how you find the problem — but the retro is not over until the
feeling has been converted into a change or consciously recorded as accepted.

## Cadence

| Retro type | Trigger | Scope |
|---|---|---|
| Sprint retro | Every sprint | Flow, quality, collaboration, the process itself |
| Incident postmortem | SEV1/SEV2, near-misses | One incident, deeply (`08-operate-and-respond.md`) |
| Gate-failure analysis | Monthly | Why items were rejected — and what escaped anyway |
| Release retro | Major releases | The release mechanics themselves |
| AI assurance review | Monthly + per AI incident | Eval trends, drift, red-team findings, agent behavior |
| Process health review | Quarterly | Is this whole thing still worth its cost? |

## Sprint retro structure (60–75 min)

**1. Set the stage (5 min).** State the prime directive aloud: we are examining the system,
not the people. Then check psychological safety honestly — if the last three retros produced
no criticism of the process or of leadership, the retro is not safe and the data is worthless.

**2. Gather data (15 min).** Facts before opinions, or the loudest opinion becomes the fact.

- **Flow:** deployment frequency, lead time, change failure rate, time to restore
- **Quality:** escaped defects, gate rejection rate *by gate*, flaky tests, PR review latency
- **Security:** new findings by severity, mean time to remediate, anything past SLA
- **AI assurance:** eval pass rate, drift events, agent gate rejections, red-team findings
- **Process:** emergency changes used, exceptions raised, gates skipped and why
- **Timeline:** what actually happened, including the parts nobody enjoyed

**3. Generate insight (25 min).** The part that is usually rushed and is the only part that
matters. Take the two or three most costly items and ask *why* until you reach something you
can change. Stop when you reach a condition, not a person.

Three questions that reliably surface real material:

- **What did we get away with?** Where were we lucky rather than good? Luck does not recur.
- **What did we work around?** A routed-around process is a broken process advertising
  itself. Route-arounds are always evidence, never misconduct.
- **What surprised us?** Surprise is the gap between the model and reality. Close the gap.

**4. Decide what to do (20 min).** **Pick at most two.** Teams that leave with eight actions
complete none; teams that leave with two complete both and compound. Each action gets:
owner, due date, an issue, and the artifact it will change.

**5. Close (5 min).** Review last retro's actions first-class: done, not done, or dropped —
and *dropped is a legitimate answer said out loud*, far better than carrying dead items
forward until the list becomes wallpaper. Then rate the retro itself.

## `/learn` — converting output into artifacts

`/retro` produces the record. `/learn` produces the diff. It reads the retro output and
proposes the concrete changes: doc edits, new CI checks, agent prompt corrections, gate
checklist amendments, memory entries.

Every process change is itself a change: PR, human review, human approval. The process is
version-controlled and its history is auditable — an assessor can see not only what the
process is, but when it changed and why (SA-15, CM-3 applied reflexively).

## Improving the agents

This is the part with no equivalent in a human-only process, and it compounds fastest.

When an agent produces a bad outcome, the fix belongs in its definition, not in a correction
you deliver once in chat and lose:

| Observed | Fix |
|---|---|
| Security agent missed a finding class repeatedly | Add the class explicitly to its checklist |
| Dev agent skipped test-first under time pressure | Strengthen the constraint; add a hook that checks for a failing test in history |
| PO agent wrote untestable acceptance criteria | Add the negative examples to the agent prompt |
| An agent tried to self-approve | Tighten the tool grant so it *cannot*, then keep the prompt rule as defense in depth |
| An agent followed an instruction embedded in issue text | Reinforce PD-6; add an injection-detection check to the command |

Agent definitions are versioned artifacts under change control like any other. Their diffs
are reviewed by a human. **An agent change that relaxes a control requires the same approval
as a pipeline change that relaxes a gate** — this is the loophole to watch, because it is
the quietest way to weaken the system.

## Measuring whether the process earns its keep

Quarterly, ask honestly:

- **Is the gate rejection rate non-zero and non-total?** A gate that never rejects is
  ceremony; one that rejects most things is misplaced — the work should not be reaching it.
- **Are escaped defects trending down?** If gates are not catching things, they are cost
  without benefit.
- **Is lead time trending flat or down** while quality holds? Rising lead time with flat
  quality means process weight is accumulating without return.
- **Are emergency changes rare and falling?** Rising means the normal path is too slow, and
  the answer is to fix the normal path.
- **Are exceptions rare, time-boxed, and closing?** A growing exception register is a process
  people no longer believe in.
- **Would a new team member be productive in a week?** If the process cannot be learned in a
  week, it will not be followed in month two.

If the answers are bad, **remove process**. Adding is the reflex; subtraction is the skill.
Every gate, check, and document here should be able to justify its cost or be deleted —
including this one.

## Anti-patterns

**The blame retro.** Once someone is criticized by name, honest data stops. Permanently.
**The complaint session.** Venting without conversion produces learned helplessness.
**The action-item graveyard.** Actions with no owner, date, or issue. Cap at two.
**Skipping it when busy.** Busy is precisely when the process is breaking down.
**Same facilitator forever.** Rotate; each facilitator has blind spots.
**Only reviewing failures.** What went well needs deliberate protection or it erodes silently.
**The compliance-only retro.** If the retro exists to generate CA-7 evidence, it will generate
evidence and no improvement. The evidence is a by-product of doing it for real.
