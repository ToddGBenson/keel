# Sprint intake — describe it, come back to a tested PR

Drop a description in `sprint/inbox/`. At the scheduled time the runner picks it up, takes it
through the whole pipeline, and leaves you a **PR with working, tested code and complete gate
evidence**.

```
sprint/inbox/link-checker.md         ← you write this
        │
        ▼  ./keel sprint  (scheduled, or on demand)
        │
   /spec → /refine → /ready → /design → /implement → tests → PR
        │
        ▼
  PR #42  ✅ 11 checks green, evidence attached, self-review written
        │
        ▼  ← YOU merge. One click. This step is not automated, on purpose.
```

## Writing a description

Prose is fine. Vague is fine — the runner's first job is to **interrogate what you left
unsaid** (`artifact-intake`) and record it, rather than quietly inventing requirements.

```markdown
# Link checker

Build a tool that reads a list of URLs from a file and reports which are
broken, with the status code and how long each took.

Stack: python
```

Optional front-matter lines the runner understands: `Stack:`, `Schedule:`, `Priority:`,
`Constraints:`.

## What the runner does

| Step | Produces |
|---|---|
| Intake | `Extracted` / `Inferred` / `Unspecified` — with defaults chosen for the blockers |
| Refine | Vertical-slice stories with binary acceptance criteria |
| G1 | Definition of Ready check; stops if a design-changing question is open |
| G2 | Threat model + control allocation — **mandatory** if security-relevant |
| Implement | Failing test first, then the code, per story |
| G3/G4 | Traceability, control verification, mutation check |
| PR | Branch, evidence, self-review, AI declaration |

## What it will NOT do — bounded autonomy (AIC-11)

The runner **stops and leaves a note** rather than proceeding when:

1. A **High or Critical** finding appears
2. The work needs a **secret, credential, or production access**
3. The change would touch `.github/workflows/`, `.claude/hooks/`, `process/gates/`, or
   `docs/compliance/` — the controls themselves
4. Blast radius exceeds the description (scope creep by agent is still scope creep)
5. An unspecified question is genuinely **blocking** and no safe default exists
6. It has failed the same step three times

It **never** merges, deploys, force-pushes, or handles credentials — the guard hooks block
those regardless of what any prompt says.

## Reviewing the result

The PR is where you spend your time, and it is written to be quick:

- **What I made worse** — the honest cost
- **Not verified** — what it could not confirm, stated plainly
- **Unspecified → defaults chosen** — every assumption it made, listed for you to overrule

If the defaults are wrong, say so on the PR and re-queue; the description is still in
`sprint/done/` with the intake record beside it.

## Scheduling

```bash
./keel sprint                 # run the queue now
./keel sprint --dry-run       # show what it would pick up
```

Scheduled runs: `.github/workflows/sprint.yml` (needs `ANTHROPIC_API_KEY` as a repo secret —
**you** add it; agents never handle credentials), or a local cron calling `./keel sprint`.
See `docs/16-sprint-automation.md`.
