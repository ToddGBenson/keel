# L0015: Duplication is not defence in depth

**Date:** 2026-08-13 · **Source:** #42 · **Class:** promotable
**Applies to:** any repo running checks in more than one place — PR vs main, two CI engines
**Landed as:** the trigger split in `ci/pipeline.yml` · the model in `ci/README.md`

## What happened

CI/CD execution moved from GitHub Actions to Concourse. The port kept every check and split
it by *engine*: Actions gates the pull request, Concourse owns `main` and everything
scheduled. That sounded principled. Measured, it meant per change:

| tool | runs |
|---|---|
| CodeQL | 2 per language (PR + main) |
| gitleaks | 3 (PR, main `secrets`, main `mykronos-secrets`) |
| grype, checkov, suppression-audit | 2 each |

And `main` could not be reached except through a pull request that had already run all of
them: `enforce_admins` on, no force-push, no deletions, linear history, twelve required
checks.

So the second run re-answered a question the first had already answered, on a tree that could
not have changed in between — and one of the duplicates (a second CodeQL pass) wrote its
SARIF to a volume Concourse garbage-collects, so its results reached nothing at all.

## Why it happened

The split was made on the axis that was easy to see — *which engine* — instead of the axis
that matters: *what question does this check answer, and can the answer change?*

"We run it in both places" **feels** like defence in depth. It is the same depth twice. It
costs minutes on every merge, and it trains people to read a red main job as a flake, which
is the real damage: the duplicate erodes the original.

## The rule

**Run a deterministic check once, where it can block. Re-run it later only if something other
than the diff can change the answer.**

Four properties justify running something after the merge. Nothing else does:

- **time-dependent** — a clean SCA scan says nothing about a CVE published yesterday, so it
  wants a *cadence*, not an echo
- **route-dependent** — two PRs each green in isolation; a protection setting changed; a merge
  that resolved badly
- **commit-keyed** — a findings lake keys to a SHA, and a squash merge produces a SHA no PR
  run ever saw
- **too slow for the PR budget** — the suite the PR deliberately skips

Applying it here moved eight lanes from a per-commit echo to a daily cadence, deleted one
duplicate outright, and *added* coverage: two of those lanes previously had no cadence at
all, only the echo. Per-commit work roughly halved.

## The tell

If a check runs in two places, ask what makes the second answer able to differ from the
first. If nothing can, the second run is not depth — it is latency, noise, and an invitation
to ignore a red build.

If the answer is "the branch protection might be wrong", say that out loud and give the check
a *cadence*, because that is a detection control with a timescale, not a repeat of a
prevention control.
