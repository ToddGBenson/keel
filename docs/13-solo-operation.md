# 13 — Solo Operation

**Applies when:** one person holds every role. **Controls:** AC-5, CM-5, CM-3, CA-2
**Configured by:** `scripts/configure-github.sh --solo`

## State the gap first

A single operator **cannot satisfy AC-5 separation of duties literally.** Producer and
approver are the same human. No configuration changes that.

This document exists so that fact is *declared, compensated, and recorded* rather than
quietly worked around. The failure mode we are avoiding is not "solo operation" — it is a
control map that claims separation of duties while one person merges their own work.

**Recorded as POAM-008.** Cite it in the SSP under AC-5. Do not claim enforced separation of
duties while operating in this mode.

## What changes, and what does not

Exactly one control is relaxed.

**One control is relaxed. It takes three GitHub settings to express it**, because GitHub
enforces independent approval in three places and any one of them left on makes merging
impossible for a single owner.

| Setting | Team | Solo | Why |
|---|---|---|---|
| `required_approving_review_count` | 1 | **0** | GitHub forbids approving your own PR |
| `require_code_owner_reviews` | ✔ | **false** | Code-owner approval is required *regardless of the count* — discovered the hard way when a fully-green PR stayed `BLOCKED` |
| `require_last_push_approval` | ✔ | **false** | Requires an approval after the final push; same impossibility |

CODEOWNERS still **routes and auto-requests** review — it is advisory rather than blocking.
The file keeps doing its documentation and notification job.

| Other controls | Team mode | Solo mode | Why |
|---|---|---|---|
| No admin bypass | ✔ | ✔ | **Unchanged.** Relaxing this would disable everything at once |
| Required status checks | ✔ | ✔ **+ all of them** | The machine takes over what the reviewer did |
| Signed commits | ✔ | ✔ | Attribution is unaffected by team size |
| Linear history, no force-push, no deletion | ✔ | ✔ | Unchanged |
| Conversations resolved | ✔ | ✔ | Unchanged |
| **Self-review artifact** | optional | **required** | New. See below |
| **Cooling-off before merge** | — | **required** | New. See below |

The single most important line: **`enforce_admins` stays true.** The tempting shortcut is to
let the admin bypass protection "just for solo work." That does not relax one control; it
removes all of them simultaneously, including the ones that still worked.

## The three compensating controls

A human reviewer provided three things. Each is replaced by something a machine can require.

### 1. Independent analysis → `/self-review`

The reviewer's value was **reasoning uncorrelated with the author's.** A fresh agent
invocation that has not seen the implementation reasoning provides a genuine, if weaker,
version of that — the correlation this breaks is real, which is the whole basis of AIC-2.

`/self-review <PR>` spawns reviewers with only the diff, the story, and the threat model as
input. It produces `evidence/<issue>/g3/self-review.md`, which is the artifact that stands
where a reviewer's approval would have been.

**This is weaker than a second human.** It catches mechanical defects, missed controls, and
untested paths well. It catches *misunderstood requirements* poorly, because it reads the
same requirements the author did.

### 2. A second look in time → cooling-off

A PR opened and merged in the same working session has not been reviewed; it has been
re-read by the person who just wrote it, while they still hold the same mental model.

**Rule: do not merge a PR the same session you opened it.** Overnight is better. The
detection value of a cold read is the cheapest review capacity a solo operator has, and it is
free.

For security- or AI-flagged changes, extend to a full day.

### 3. Accountability → the self-review record

The approval record disappears; the *evidence* must not. Every PR merged in solo mode carries
a self-review section stating **what was verified independently** — not "reviewed", but the
specific claims checked and how.

`pr-governance.yml` requires it. A PR with no approving review and no self-review record
fails the check and cannot merge.

## What this does not fix

Be honest with yourself about the residual risk:

- **You will not catch your own misunderstandings.** If you misread the requirement, both the
  code and your self-review encode the misreading. Agents will not save you — they read the
  same requirement.
- **You will not catch your own blind spots.** The class of bug you habitually write is the
  class you habitually do not look for.
- **Social pressure is gone in both directions.** Nobody is watching, which cuts both the
  performative work and the useful discipline.

The mitigations are real but partial: the cooling-off period, the agent's different vantage,
and the periodic external review below.

## Periodic external review — the one thing you should actually pay for

**Quarterly, have a competent human outside the project review a random sample** of merged
changes. Three PRs, chosen by `shuf`, not by you.

This is the closest a solo operator gets to genuine separation of duties, and it is the
compensating control an assessor will find most credible — because it is the only one
involving an independent human.

Record it in `evidence/assessments/<quarter>/external-review.md`. If you skip it for two
consecutive quarters, the compensating control has lapsed and POAM-008 should be re-rated.

## Growing out of it

The moment a second person joins:

```bash
bash scripts/configure-github.sh --team
```

Restores `required_approving_review_count: 1`. Then close POAM-008 with evidence, and update
the SSP. Do this on day one of the second person, not when it next comes up — the window
where the team has grown but the controls have not is exactly when the assumption "someone
reviewed this" becomes false without anyone noticing.

## Free upgrade worth considering

Environment reviewers and secret-scanning push protection are **free on public repositories**
and require a paid plan on private ones. If the repository can be public, making it public
*strengthens* your controls at no cost and closes POAM-005 and POAM-006 outright.

That is a disclosure decision, not a technical one — but it is worth making deliberately
rather than defaulting to private.
