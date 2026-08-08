# 15 — Tracking the Backlog and Pipeline Visually

**Command:** `./keel dash` · **Generator:** `scripts/dashboard.py`

Three views, each for a different question. Use the cheapest one that answers yours.

| Question | View | Live? |
|---|---|---|
| What needs me *right now*? | `./keel dash` | snapshot |
| Where is each work item against the gates? | GitHub Projects board | live |
| Why did that run fail? | GitHub Actions tab | live |

## 1. `./keel dash` — the operator's view

Generates `dashboard.html` from live `gh` data plus local files, and opens it.

Sections, in the order they matter:

- **Needs a human** — first, always. Green PRs waiting to merge, blocked PRs, unowned or
  High-risk findings. If this is empty, nothing is waiting on you.
- **At a glance** — open PRs, issues, findings, unowned findings, CI pass rate, required
  checks, lessons, agent evals. Each tile carries a **severity stripe**, so a problem reads at
  a glance without parsing the number.
- **CI/CD** — recent run outcomes and a pass-rate bar.
- **Controls on `main`** — admin bypass, linear history, force-push, conversations, signed
  commits, required-check count. Read straight from the branch-protection API, so it shows
  what is *actually* enforced rather than what the docs claim.
- **Open findings** — the POA&M, with unowned entries flagged.

**It is a snapshot and says so.** A dashboard that looks live while being hours stale is worse
than one with a visible timestamp. Regenerate to refresh; it is a sub-second operation.

The file is gitignored — it is derived state, and committing it would churn every diff.

## 2. GitHub Projects — the live gate board

The right home for the backlog itself: live, shared, and it auto-adds issues and PRs.

**Setup** (one-time; needs a scope you must grant interactively):

```bash
gh auth refresh -h github.com -s project,read:project
gh project create --owner <you> --title "keel delivery"
```

Then in the project's settings:

1. Add a **single-select field `Gate`** with options: `G0 intake` · `G1 ready` ·
   `G2 designed` · `G3 code complete` · `G4 verified` · `G5 released`.
2. Switch the view to **Board**, grouped by `Gate`. That is your gate flow, visually.
3. Add a **built-in workflow**: *item added to repo → set Gate = G0 intake*, and
   *PR merged → set Gate = G5 released*.

The middle transitions stay manual on purpose. A gate is passed by producing evidence, not by
a card moving — automating the move would let the board claim a gate that never ran.

Useful extra fields: `Flags` (security / AI / privacy — the ones that make G2 mandatory) and
`Risk` for findings.

## 3. GitHub Actions — the pipeline detail

The dashboard tells you *that* CI is healthy; the Actions tab tells you *why* a run failed.
Nothing to build — but two habits are worth having:

- Read the **job summary**, not just the badge. The scan jobs write an explicit
  "SKIPPED — the control is NOT satisfied" note when there is nothing to scan, and a green
  badge over a skipped scan is exactly the false assurance the platform is built to avoid.
- Watch the **required-check count** on the dashboard. If it drops, a control was removed.

## What deliberately has no view

**Velocity, story points, per-person commit counts.** They are trivially gamed, and measuring
them corrupts the estimates the process depends on. The dashboard tracks flow and risk, not
output volume — see `docs/00-overview.md` § Anti-metrics.
