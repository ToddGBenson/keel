---
description: Promote a project-local lesson or process improvement upstream to the platform base repo, so every fork receives it
argument-hint: <lesson id, retro id, or a described improvement>
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, Task
---

# Promote: `$ARGUMENTS`

Carries a lesson from **this fork** back to the **platform base repo**, so every other
project built on it receives the improvement on their next `sync-platform.sh`.

This is the half of the learning loop that `/learn` does not cover. `/learn` closes the loop
inside a project; `/promote` closes it across projects. Without it, ten forks learn the same
thing ten times.

## 1. Classify — the decision that matters

> **Would a team on a completely different stack, in a different domain, hit this same wall?**

| Answer | Class | Where it goes |
|---|---|---|
| Yes | **promotable** | Upstream, via this command |
| No | **project-local** | Stays here. `/learn` already landed it |
| Unsure | **project-local** | Write it locally; promote later if it recurs |

Bias toward project-local when uncertain. A lesson wrongly promoted becomes noise in every
fork, and noise is what makes people stop reading the ledger — which costs more than the
lesson was worth.

**Promotable smells like:** a control design principle · a defect class in the platform's own
tooling · a gate that consistently misfires · a skill whose method is wrong or incomplete · a
process step that every project works around.

**Project-local smells like:** anything naming your stack, your customers, your domain, your
team's shape, or a specific dependency version.

## 2. Check it is not already known

```bash
grep -ril "<key phrase>" docs/lessons/
```

If a lesson already covers it, **strengthen that lesson** rather than adding a near-duplicate
— add the recurrence, the new context, the better test. A ledger with two entries saying
almost the same thing is a ledger people stop trusting.

## 3. Write the lesson

`docs/lessons/NNNN-kebab-slug.md`, following `docs/lessons/README.md`. Required fields:

- **Class:** promotable
- **Applies to:** the conditions under which a reader would hit this
- **Landed as:** the artifact that now encodes the rule — **mandatory**
- **How you would know you hit this** — the symptom, written so someone who does not yet know
  they need this lesson can recognise it

A lesson with no landed artifact is a note. If nothing changed, nothing was learned.

## 4. Make the artifact change

The lesson explains; the artifact enforces. Change the real thing:

| Kind of lesson | Change |
|---|---|
| A method is wrong or incomplete | `.claude/skills/<skill>/SKILL.md` |
| An agent behaves badly | `.claude/agents/<agent>.md` |
| A gate misfires | `process/gates/g<n>-*.md` |
| A control design principle | `docs/11-ai-agent-controls.md` (GP-n) |
| A check is missing | `.github/workflows/`, `scripts/`, `.claude/hooks/` |
| A guard defect | Fix it **and every sibling implementation** (L0008) |

**Prefer an automated check over a documented rule.** A rule needs remembering; a check does
not.

## 5. Open the upstream PR

```bash
git remote get-url upstream || {
  echo "No upstream configured — cannot promote"; exit 1; }

git fetch upstream
git switch -c promote/<slug> upstream/main
# apply ONLY the platform-owned changes — never project code
git commit -m "feat(lessons): L00NN <short title>

Learned in <project>. <One line on what it prevents.>

Landed as: <artifact>
Refs: #<local issue>
AI-Assisted: <model> (drafting)"

gh pr create --repo <upstream-owner>/<upstream-repo> \
  --title "L00NN: <short title>" --body-file <(cat <<'BODY'
## What was learned
## Where it happened
## Why it generalises
## What changed
## How a reader would know they hit this
BODY
)
```

**Only platform-owned paths** go in a promotion PR — see `platform/MANIFEST.yml`. Project
code, your POA&M, your evidence, and your ADRs stay in your fork. A promotion PR carrying
project files will be rejected upstream and should be.

## 6. Governance

A promotion is a **process change to every downstream project**. It gets the full weight:

- Human review and approval upstream — not self-merged
- A change that **relaxes** a control needs the same scrutiny as relaxing a pipeline gate
  (AIC-8). This is the quietest way to weaken every fork at once, and it is the specific
  thing an upstream reviewer should be looking for.
- Downstream forks receive it on their next `sync-platform.sh`, review the diff, and merge
  deliberately — a sync is a Normal change under CM-3, not an automatic update.

## Then

Record the promotion in this fork's retro output, and note the upstream PR link on the local
lesson so the trail is complete in both directions.
