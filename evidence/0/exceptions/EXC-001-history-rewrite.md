# Security Exception EXC-001 — Pre-publication history rewrite

**Requested by:** claude-opus-5 (agent) · **Approved by:** Todd Benson (system owner)
**Date:** 2026-08-08 · **Controls affected:** AU-12, SI-7, CM-5, AIC-3
**Related:** publication of the repository to public visibility

## 1. What control is not being met?

Three, briefly and simultaneously:

- **AU-12 / SI-7** — git history is an immutable, attributable audit trail. Rewriting it
  destroys the existing record.
- **CM-5** — `allow_force_pushes: false` on the default branch.
- **AIC-3** — `guard-bash.sh` blocks force-push and history rewrite by agents.

## 2. Why

Four commits carry the owner's personal email address (`tgbenson602@gmail.com`) as author
and committer. Publishing the repository makes that address permanently scrapable, and
publication is a **one-way door** — GitHub does not un-index a public commit history.

Rewriting is cheap now (4 commits, no forks, no stars, PR unmerged) and impossible later.

## 3. Risk of granting

**Low.** The audit trail being destroyed covers two days of pre-publication bootstrap by a
single author. There is no external party relying on it, no release references it, and no
compliance obligation attaches to a repository that has never been published.

The residual risk is loss of the intermediate commit record — the sequence of defect fixes
made during the build. **Mitigated:** every one of those is documented in `docs/lessons/`
(L0001–L0010) and in the POA&M, which are more durable and more useful than the commit
messages they came from.

## 4. Risk of NOT granting

Permanent publication of a personal email address to an unbounded audience. Not reversible
by any subsequent action.

## 5. Compensating controls

1. The rewrite is performed **before** publication — no external party has fetched the
   history.
2. Branch protection is lifted for the minimum interval and **re-applied and re-verified**
   immediately after (`configure-github.sh --solo`, 9/9 checks).
3. The agent does **not** perform the force-push. `guard-bash.sh` refuses it, and that
   refusal is respected — the human operator executes it directly.
4. The resulting history is a single, signed, clean initial commit whose provenance is
   fully documented here and in the PR record.

## 6. Scope and duration

**Strictly limited to:** one force-update of `main` prior to first publication.
**Duration:** the minutes required to push and re-apply protection.
**Expires:** on completion, 2026-08-08. Not renewable — after publication this exception
would be denied, because the risk calculus inverts entirely.

## 7. What happens at expiry

Branch protection re-applied and verified. `allow_force_pushes` returns to `false`,
`enforce_admins` to `true`. No further history rewrite is permitted on this repository.

## 8. Approval

| Role | Name | Decision | Date |
|---|---|---|---|
| Requesting agent | claude-opus-5 | requested | 2026-08-08 |
| Security Engineer | *(solo — role held by owner)* | recommend | 2026-08-08 |
| **Human operator** | Todd Benson | **approved** (selected the rewrite option explicitly) | 2026-08-08 |

## 9. Note on the agent boundary

The agent prepared the rewritten history but did **not** execute the force-push, because
`guard-bash.sh` blocks it and an approved exception is not a reason for an agent to evade a
control it is subject to. Writing a wrapper script to slip past the guard would have worked
and would have been wrong — it establishes that guards are evadable when inconvenient, which
is the precise failure mode L0001 warns about from the other direction.

The human operator executed the blocked step. That is the boundary working as designed.
