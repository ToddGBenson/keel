# 16 — Sprint Automation

**Command:** `./keel sprint` · **Runner:** `scripts/sprint.sh` · **Schedule:** `.github/workflows/sprint.yml`
**Controls:** CM-3 (traceability) · AIC-11 (bounded autonomy) · AC-5 / POAM-008 (a human merges)

Describe an idea in `sprint/inbox/`. The runner takes it through the pipeline and leaves you a
tested PR.

## The boundary — read this before enabling the schedule

The runner automates everything **up to a PR**. It does **not** merge, deploy, or handle
credentials.

That is not timidity. A human authorizing the change is the control that separates this
platform from a system that writes code unsupervised, and it is the entire basis of the
POAM-008 risk acceptance. Automate the merge and every claim this repo makes about AC-5
becomes false.

## How autonomy is bounded

Prompt instructions are advisory (AIC-3) — a sufficiently confused model ignores them. So the
limits that matter are **structural**:

| Limit | How it is enforced |
|---|---|
| Cannot modify the controls | The runner **diffs its own output** and abandons the branch if it touched `.github/workflows/`, `.claude/hooks/`, `.claude/agents/`, `process/gates/`, `docs/compliance/`, or `configure-github.sh` |
| Cannot deploy or publish | The workflow token omits `packages`, `deployments`, and `id-token`. Not "told not to" — *cannot* |
| Cannot merge or force-push | `guard-bash.sh` blocks it, and branch protection backs that up |
| Cannot run forever | 45-minute job timeout; `concurrency` prevents overlapping runs |
| Cannot proceed past a real decision | Writes `sprint/done/<slug>.BLOCKED.md` and comments on the issue instead |

**Stopping is a success state.** A `.BLOCKED.md` file means the runner hit something a human
should decide — a High finding, a needed credential, scope creep, or a blocking question with
no safe default. That is the system working, not failing.

## The flow

```
sprint/inbox/thing.md
      │
      ▼  issue created first — no work without a work item (CM-3)
      ▼  branch feat/<issue>-<slug>
      │
   artifact-intake ─▶ Extracted / Inferred / Unspecified (+ chosen defaults)
   story-splitting ─▶ thin vertical slices, binary criteria
   G1 ─────────────▶ Definition of Ready
   G2 ─────────────▶ threat model, if security-/privacy-/AI-relevant
   test-first ─────▶ failing test, then the smallest implementation
   G3/G4 ──────────▶ traceability, control verification, mutation check
      │
      ▼  protected-path check — abandon if it touched a control
      ▼  keel check
      ▼  PR with evidence, self-review, AI declaration
      │
      ▼  ← YOU merge
```

## Enabling the schedule

1. **Add `ANTHROPIC_API_KEY`** as a repository secret — Settings → Secrets and variables →
   Actions. **You do this, not an agent**: agents never handle credentials (AIC-5). Without
   it the workflow exits early and says so rather than failing obscurely.
2. Adjust the cron in `.github/workflows/sprint.yml`. Default is weekly (Monday 06:00 UTC);
   `'0 6 * * *'` makes it daily.
3. **Watch the first run.** Do not schedule it unattended until you have seen one complete.

Locally: `./keel sprint` (whole inbox) or `./keel sprint --one sprint/inbox/x.md`.

## Reviewing an autonomous PR

Read these first, in this order:

1. **Unspecified → defaults chosen.** Every assumption the runner made, listed. This is where
   a wrong guess hides, and overruling one is a comment, not a rebuild.
2. **Not verified.** What it could not confirm.
3. **What I made worse.** The honest cost.

**Give autonomous PRs *more* scrutiny than hand-written ones, not less.** The self-review in
an autonomous PR is written by the same agent that wrote the code — one reasoning chain
produced both, which makes it the weakest form of the POAM-008 compensating control. It
catches mechanical defects well and misunderstood requirements poorly.

## Honest limits

- **The runner has not been proven end to end.** Its pipeline has been run manually,
  step by step. Given this project's record — nine defects on `bootstrap.sh`'s first real
  execution, four on the dashboard's — expect friction on the first live run (L0011).
- **Prompt-driven orchestration is less predictable than code.** The runner hands a long
  prompt to `claude -p`; the structural checks around it exist precisely because the prompt
  itself cannot be relied upon.
- **Cost is unbounded per run** beyond the timeout. A complex description can consume
  significant tokens. Start with small, well-scoped descriptions.
