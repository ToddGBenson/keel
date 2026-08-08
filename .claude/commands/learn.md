---
description: Convert retro or postmortem output into actual committed diffs — process docs, CI checks, agent definitions, control updates
argument-hint: <retro id, incident id, or a described lesson>
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, Task
---

# Learn: `$ARGUMENTS`

`/retro` produces the record. **`/learn` produces the diff.** This command exists because
intentions decay and diffs do not.

## 1. Read the source

The retro record at `evidence/retros/<id>/retro.md`, the postmortem at
`evidence/incidents/<id>/postmortem.md`, or the lesson described in the argument.

## 2. Classify each action — twice

**First: what artifact does it change?**

| If the lesson is... | The change goes in... |
|---|---|
| A rule or expectation changed | `docs/`, `process/gates/` |
| Something a machine should check | `.github/workflows/`, `.claude/settings.json` hooks |
| An agent behaved wrongly | `.claude/agents/`, `.claude/commands/`, `.claude/skills/` |
| A control or evidence gap | `docs/compliance/`, POA&M entry |
| Work that must be done | GitHub issue, owner, date |

**Second: does it travel?**

> **Would a team on a completely different stack, in a different domain, hit this same wall?**

| Answer | Class | Action |
|---|---|---|
| Yes | **promotable** | Write it to `docs/lessons/`, then run **`/promote`** |
| No | **project-local** | Land the artifact change here and stop |
| Unsure | **project-local** | Note it; promote later if it recurs |

This second classification is what turns a fork into part of a platform rather than an
isolated copy. Without it, every fork learns the same lessons independently — the exact
duplication the platform exists to prevent.

Bias toward project-local when unsure. A wrongly promoted lesson becomes noise in every fork,
and noise is what stops people reading the ledger at all.

**Promotable smells like:** a control design principle · a defect in the platform's own
tooling · a gate that consistently misfires · a skill whose method is wrong · a process step
every project works around.

**Project-local smells like:** anything naming your stack, customers, domain, team shape, or
a specific dependency version.

**Prefer an automated check over a documented rule, every time.** A rule requires someone to
remember; a check does not. If a lesson can be expressed as a CI check, express it that way
and skip the doc edit — a doc that duplicates an enforced check is maintenance debt.

## 3. Improving the agents

This is the part with no human-process equivalent, and it compounds fastest. When an agent
produced a bad outcome, the fix belongs in its **definition**, not in a correction delivered
once in chat and lost:

| Observed | Fix |
|---|---|
| Security agent repeatedly missed a finding class | Add the class explicitly to its checklist |
| Dev agent skipped test-first under time pressure | Strengthen the constraint; add a hook checking for a failing test in history |
| PO agent wrote untestable acceptance criteria | Add the negative examples to the prompt |
| An agent tried to self-approve | **Tighten the tool grant so it cannot**, and keep the prompt rule as defense in depth |
| An agent followed instructions embedded in issue text | Reinforce PD-6; add injection detection to the command |

**Prefer the tool grant over the prompt.** Per the enforcement table in
`docs/11-ai-agent-controls.md`, a prompt-only control is advisory — a sufficiently confused
model ignores it. Ask not "what should the agent be told" but **"what makes the unwanted
action impossible."**

## 4. Write the diffs

Make the actual edits. Small, specific, reviewable. For each, state what it changes and what
observation motivated it — the motivation is what lets a future reader judge whether the rule
still earns its place.

## 5. Consider subtraction

Adding is the reflex; subtraction is the skill. On every `/learn`, ask whether this lesson
means some existing gate, check, or document should be **removed** — because it was not
catching anything, because it duplicates a new check, or because it was the friction that
caused the workaround in the first place.

A process that only accretes becomes one people route around, and that is worse than a
smaller process people follow.

## 6. The lessons ledger

Every **promotable** lesson gets a file in `docs/lessons/` before it is promoted. Format and
rules in `docs/lessons/README.md`. Two fields carry the weight:

- **Landed as:** the artifact that now encodes the rule. Mandatory. A lesson with no landed
  artifact is a note, and nothing was actually learned.
- **How you would know you hit this:** the symptom, written for someone who does not yet know
  they need this lesson. It is what makes the ledger findable rather than archival.

Then run **`/promote`** to open the upstream PR.

Prune as you go: a lesson whose rule is now enforced by an automated check has done its job —
mark it superseded and stop carrying it. The ledger is a working set, not an archive.

## 7. Raise the PR

```
chore(process): split CI to cut PR feedback below 10 min

Retro sprint-23 found 3 emergency-path uses caused by a 40-min CI run —
the normal path was slower than the incident clock. Widening the emergency
door would have been the wrong fix.

- ci.yml: affected tests on PR, full suite on merge
- docs/06-cicd.md: record the 10-minute target and the reasoning
- REMOVED: the duplicate lint job in security.yml (ci.yml covers it)

Refs: #221, retro sprint-23
AI-Assisted: <model> (drafting)
```

## Governance

A process change is a change. **PR, human review, human approval** — no exception, including
for changes to this command.

**Watch this specifically:** an agent-definition change that *relaxes* a control requires the
same approval as a pipeline change that relaxes a gate. It is the quietest way to weaken the
system, and it is the thing to flag loudly when you see it (AIC-8).
