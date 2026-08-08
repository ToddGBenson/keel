# 09 — Retrospective & Continuous Improvement

**Owner:** Delivery Lead · **Commands:** `/retro`, `/learn` · **Method:** `retro-facilitation`,
`blameless-postmortem` · **Controls:** CA-7, SA-15, PM-31, AI RMF GOVERN 4.3 / MANAGE 4.1

## The one rule

> **A retrospective ends in a merged pull request, or it did not happen.**

Retros fail everywhere the same way: they produce intentions, the intentions decay, the
problems recur, and the meeting becomes a tax. The fix is structural — the output is a **diff**
against one of five things:

| Change type | Lands in |
|---|---|
| Process rule | `docs/`, `process/gates/` |
| Automated check | `.github/workflows/`, `.claude/settings.json` |
| Agent behavior | `.claude/agents/`, `.claude/commands/`, `.claude/skills/` |
| Control / evidence gap | `docs/compliance/`, POA&M |
| Work to do | A GitHub issue with an owner and a date |

If an item can't become one of those, it's a feeling — worth hearing, but the retro isn't over
until it's converted or consciously recorded as accepted.

**The structure** (data before opinions; ask *why* to a condition not a person; the three
questions — *what did we get away with, work around, get surprised by*; **pick at most two
actions**) is in the `retro-facilitation` skill. Incidents use `blameless-postmortem`.

## Cadence

| Type | Trigger |
|---|---|
| Sprint retro | Each sprint |
| Incident postmortem | SEV1/2, near-misses |
| Gate-failure analysis | Monthly — why items were rejected, *and what escaped* |
| AI assurance review | Monthly + per AI incident (`./keel evals`) |
| Process health review | Quarterly (below) |

*(Solo: same rhythm, shorter. The retro is you reading the metrics honestly and shipping one
or two fixes. `/learn` turns the finding into the diff.)*

## Improving the agents

The part with no human-process equivalent, and it compounds fastest. A bad agent outcome is
fixed in the **definition**, not a chat correction that's lost:

| Observed | Fix |
|---|---|
| Security agent misses a finding class | Add it to the checklist; add a seeded eval case (`evals/agents/`) |
| Dev agent skips test-first under pressure | Strengthen the constraint; hook-check for a failing test in history |
| PO agent writes untestable AC | Add negative examples to the prompt |
| An agent tried to self-approve | **Tighten the tool grant so it can't**; keep the prompt rule as defense in depth |
| An agent followed injected issue text | Reinforce PD-6; add injection detection |

Agent definitions are versioned change-controlled artifacts. **An agent change that relaxes a
control needs the same approval as relaxing a pipeline gate (AIC-8)** — the quietest way to
weaken the system, and the one to watch.

## Does the process earn its keep? (quarterly)

The questions that keep this from accreting — ask them honestly, and **remove** what fails:

- **Gate rejection rate non-zero and non-total?** Never-rejects is ceremony; rejects-most is
  misplaced.
- **Escaped defects trending down?** If gates aren't catching things, they're cost without benefit.
- **Lead time flat or down while quality holds?** Rising lead time at flat quality means weight
  accumulating without return.
- **Emergency changes and exceptions rare and closing?** Rising means the normal path is too slow.
- **Could a newcomer be productive in a week?** If not, it's too heavy.

Adding process is the reflex; **subtraction is the skill.** Every gate, check, and doc should
justify its cost or be deleted — this document included. Anti-patterns (the blame retro, the
action-item graveyard, the compliance-only retro) are in the `retro-facilitation` skill.
