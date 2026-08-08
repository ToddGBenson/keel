# Self-review — doc consolidation (refactor/3)

**Mode:** solo (POAM-008) · **Agent:** claude-opus-5 · **Date:** 2026-08-08

## What this is
Deduplication, not deletion. Four phase docs (03/04/05/09) re-printed method that skills now
own authoritatively — the exact drift-prone duplication fixed everywhere else in the repo.
Compressed the repeated method to skill pointers; kept every rationale, gate mapping, and
control reference. 50% off those four docs (4791 → 2352 words).

## Verified personally
- Control references preserved — spot-checked SA-11, AC-3, AIC-8, CP-10, SR-3 all still present.
- Every skill the compressed docs point to exists on disk (14 checked, 0 missing).
- The severity SLA table 05 now defers to is canonical in 10-definitions (removed a duplicate).
- `./keel check` green; `./keel evals` structural assurance holds; validate-platform passes.
- No files deleted, moved, or renamed — content compressed in place, so no reference breaks.

## What I deliberately did NOT cut, and why
- **Agents / commands / skills** — load-on-demand, each cheap; removing agents damages the
  SoD model. The effective surface is already 5 commands (OPERATING.md).
- **12-ai-feature-governance, 06-cicd, 01-roles** — more unique than duplicative. Compressing
  them is churn for marginal gain, and 12 is the AI content the owner emphasized.
- **Compliance maps, gates, lessons, templates, hooks** — the audit value and the enforcement.
  Never touch these to save words.

Knowing when to stop subtracting is part of the skill (docs/09). I stopped at the clear wins.

## Not verified
- I have not re-read every downstream doc for a now-dangling cross-reference beyond the
  skill/control spot-checks. The refcheck covers file-level refs, not prose mentions.

## Residual risk
Single-identity review. No independent human read this. A compression that dropped a nuance
would not be caught by the automated checks — only by a human noticing the doc says less than
it should. Next external sample review: 2026-11-08.
