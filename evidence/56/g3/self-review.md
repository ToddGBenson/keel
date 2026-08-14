# Self-review — #56

Mode: solo (POAM-008)
PR: #57   Author: Todd Benson (claude-opus-5, AI-authored)   Date: 2026-08-14

Re-governing keel as a template rather than a deployable service.

## Verified independently

- **The gap is real and was measured, not asserted.** `scripts/validate-manifest.py` on the
  unmodified repository reported **9 tracked paths classified by no bucket**: `keel`,
  `evals/`, `.gitattributes`, `.gitleaks.toml`, `LICENSE`, `NOTICE`, `OPERATING.md`,
  `SECURITY.md`, `sprint/`. Exit 1.
- **The check passes after classifying them**, and exits 0 — so it is a check that can both
  fail and pass, which is the minimum bar and one I have failed to clear before in this repo.
- **The project_owned nuance was verified, not assumed.** `platform_owned` and
  `merge_required` have **0** entries pointing at nothing; `project_owned` has 11, all
  forward-looking placeholders for a fork's code (`src/`, `app/`, `package.json`). The check
  requires existence only for the buckets upstream actually ships — otherwise it would demand
  the template be an application.
- **Nothing else broke:** `fly validate-pipeline` clean, `validate-pipeline.py` clean,
  `validate-platform.py` clean, shellcheck clean across all scripts, `bash -n` on the rewritten
  `release.sh`.
- **The claim that keel has no prod was checked, not inferred:** `release-preflight`,
  `deploy-staging` and `authorize-production` had **no builds at all**, and
  `registry`/`staging_url`/`production_url` are empty strings.

## Agent findings

**None — no three-pass agent review.** Consistent with #48, #50 and #52, and I am less
comfortable with it here than on any of those: this change alters governance framing, rewrites
the release lane, and re-scopes a POA&M entry. Those are judgement calls, and judgement is
exactly what an independent read is for.

**If one thing gets reviewed, make it D4** — the decision to re-scope POAM-006/010/011 rather
than close them. Marking them not-applicable would be defensible on a literal reading and I
think it would be wrong, but that is an argument, not a fact.

## Not verified

- **`scripts/sync-platform.sh` has not been run.** The manifest is now validated as a
  *document* — every path classified, every shipped entry present. Nothing has confirmed that
  sync actually delivers according to it. A dry-run against a scratch fork is the obvious next
  check and is **not** in this PR, so the contract is verified and the mechanism is not.
- **No fork has received any of this.** The nine newly-classified paths — including the CLI —
  have never been delivered to anyone. Whether the classifications are *correct* will only be
  known when a fork syncs.
- **The template release lane has still never run.** `release-preflight` and
  `authorize-release` have no builds. I rewrote them; I have not executed them.
- **`sprint/` as project_owned is a judgement call.** It holds a fork's own sprint state, so
  project-owned is right — but the platform seeds `sprint/README.md`, which a fork will now
  never receive updates to. I decided the state matters more than the README; a reviewer might
  disagree.
- POAM-014 is untouched and still Critical.

## Cold-read notes

- **What I did not want to look at:** that the "9 unclassified paths" finding is partly mine.
  `ci/` was unclassified because I added it and did not classify it; I caught that by accident
  a day earlier and did not then ask whether anything *else* was unclassified. The check I
  wrote today would have found it on the day I introduced the problem.
- **The framing change is doing real work, not relabelling.** Before, the honest answer to "is
  everything in prod?" was "no, and it can't be", which reads as failure. After, it is "that is
  the wrong question, and here is the delivery mechanism that *is* the answer, which had no
  check until today." Those are very different states, and only the second one is actionable.
- **The most useful sentence I wrote is D3** — inert lanes are inherited, not dead. I had been
  treating `container-scan` and `build-and-attest` as embarrassing scaffolding for several
  turns, and was close to deleting them. For a template they are the point.

## Residual risk accepted

- Single-identity review, no agent passes, on a change that alters governance framing.
- The delivery mechanism itself remains unexercised; only its contract is checked.
- Next external sample review due: 2026-10-01.
