# Self-review — #63

Mode: solo (POAM-008)
PR: #64   Author: Todd Benson (claude-opus-5, AI-authored)   Date: 2026-08-14

Retiring the self-hosted runner from the documentation, and recording the failure modes that
caused it to be retired early.

## Verified independently

- **The runner is actually gone, not just unused.** `actions/runners` returns `count=0`, the
  `keel-actions-runner` scheduled task does not exist (`schtasks /query` errors), and
  `config.cmd remove` reported `Removed .credentials` and `Removed .runner`.
- **The gate still holds without it.** Branch protection still lists all three checks with
  `enforce_admins` on, and they were confirmed green on `GitHub Actions` hosted runners
  (`runner=GitHub Actions 1000014450/1/2`) **before** the runner was removed. The order was
  deliberate: at no point were the required checks unserved.
- **The retirement order is the one now written in the runbook**, because I executed it and it
  worked: delete `KEEL_RUNNER_LABELS` → confirm hosted checks green → unregister task →
  `config.cmd remove`.
- **Every stale claim was hunted, not remembered.** `git grep -nI "self-hosted"` across
  `docs/`, `.github/` and `ci/` found five, of which four were wrong and are fixed; the fifth
  (`ci/vars.example.yml`) is about Concourse workers and untouched.
- **The failure modes in the runbook are transcribed from what happened**, including the exact
  exception text (`TaskAgentSessionConflictException`) and the force-cancel endpoint that broke
  the deadlock. Nothing in that table is hypothetical.
- Validators clean: manifest, platform, pipeline; the workflow still parses with all three jobs.

## Agent findings

**None — no three-pass agent review.** Consistent with #48, #50, #52, #56, #58 and #61.

**If one thing gets an independent read, make it `ci/README.md`.** I rewrote its top banner from
"nothing gates a merge" to a description of the current split, and a banner that overstates
safety is worse than one that overstates danger.

## Not verified

- **The runbook's install path has not been re-run against the edited text.** I changed the
  framing and added a failure-mode section; I did not rebuild a runner from the document to
  confirm the instructions still work end to end. They worked this morning, and the setup steps
  are unchanged.
- **The wedge itself is undiagnosed.** I recorded that the listener died after a socket abort
  and never recovered. I do not know *why* — whether it is a network condition on this host, a
  runner bug, or something about being launched from a scheduled task. The runbook says what to
  do, not what causes it, and it presents it as a known failure mode rather than a solved one.
- **No fork has read any of this.** Same standing gap as #56 and #58: `sync-platform.sh` is
  still unexercised, so the runbook's value to a fork remains theoretical.
- **`ci/README.md` describes the Mykronos lanes and PR #60's reasoning is now partly stale**
  (`ubuntu-latest` was the deciding argument there and no longer applies). Noted in the POA&M;
  not resolved here.

## Cold-read notes

- **What I did not want to look at:** I built the runner this morning and argued for keeping it
  this afternoon. Removing it the same day looks like churn, and the temptation was to leave it
  registered and idle — harmless, and a way of not admitting the recommendation had a short
  shelf life. An idle registered runner is not harmless: it is a credentialed agent on a host
  running Vault, kept alive for the appearance of consistency.
- **The recommendation was not wrong, and the caveat was the load-bearing part.** I recommended
  keeping the gate and said plainly the runner was a bridge rather than a destination. The
  bridge lasted about eight hours, which is roughly what "bridge" should mean.
- **The most useful artifact here is the failure-mode table**, and it exists only because the
  same symptom appeared three ways in one day. A runbook written before the trouble would have
  documented the setup — which is the easy part — and none of the diagnosis.
- **The `KEEL_RUNNER_LABELS` indirection paid off in a way I did not anticipate.** I introduced
  it so forks would not have to reconcile a hard-coded `runs-on` in a merge_required file.
  What it actually bought was a one-variable retirement with no diff at all, mid-incident.

## Residual risk accepted

- Single-identity review, no agent passes.
- A documentation change describing infrastructure that no longer exists to test against.
- The wedge's root cause is unknown and recorded as such.
- Next external sample review due: 2026-10-01.
