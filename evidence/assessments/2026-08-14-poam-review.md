# POA&M review — 2026-08-14

**Assessor:** Todd Benson (claude-opus-5, agent-performed) · **Control:** CA-5, CA-7
**Method:** every row measured against the live system today. Nothing carried forward on the
strength of what a previous entry said.

## Measured

| What | Command | Result |
|---|---|---|
| Secret scanning / push protection | `gh api repos/…/keel` | `unavailable` / `unavailable` |
| `production` protection rules | `gh api …/environments/production` | `branch_policy`, **0 reviewers** |
| Branch protection | `gh api …/branches/main/protection` | required checks **NONE**, approvals **0**, `enforce_admins` true |
| Actions | `gh api …/actions/permissions` | `enabled=true` — but **billing-blocked**, jobs fail in ~3s |
| Workflows with a live trigger | parsed all 10 | **0** |
| cosign sign/attest/verify | `ci/scripts/supply-chain.sh` | **5 ADAPT stub lines** — nothing is signed |
| Mykronos ingestion | `keel/mykronos-secrets` build | **200 on scan-run, findings and raw** — works |

## Row by row

**POAM-001 — agent write-scope is prompt-enforced.** Unchanged, Low, open. The detection half
(`validate-platform.py`) runs in Concourse `platform-integrity` on every commit and passed
today.

**POAM-005 — secret scanning unavailable.** REOPENED and confirmed by measurement. Private
repo on a plan without Advanced Security. No configuration closes this.

**POAM-006 — `production` has no required reviewers.** REOPENED and confirmed. The rule was
not merely unenforced, it was **removed**: the only remaining rule is `branch_policy` with
zero reviewers. G5 is not a technical control today.

**POAM-008 — solo operation, AC-5.** Open and accepted, **but its compensating control is
inoperative**. The acceptance rests on `Process compliance` enforcing a self-review artifact
in place of a second approver. That check is a GitHub Action; Actions cannot run. The
acceptance is therefore resting on a control that does not execute — which is exactly the
documented false assurance its own entry warns about. This is the most important sentence in
this review.

**POAM-010 — G5 weakened.** REOPENED. The Concourse release lane exists again
(`release-preflight` → `deploy-staging` → `authorize-production`, no trigger, refuses without
`BUILD_CREATED_BY`). It has **never run**. Unverified, not passed.

**POAM-011 — no provenance.** Open, and worse than the entry's original wording. `cosign
sign`, `cosign attest` and `cosign verify` are five `ADAPT:` echo lines. Nothing is signed and
nothing is attested. `verify-artifact` prints "Failure here is a hard block" having verified
nothing — the most misleading string in the pipeline, and it is still there.

**POAM-012 — SAST results reaching a system of record.** Closed 2026-08-13 on the basis that
`mykronos-sast` ingests both languages. That basis was **not testable until today**, because
the lane was paused for want of a token. The token now exists and the sibling lane
(`mykronos-secrets`) proved the ingestion path end to end — 200s on scan-run, findings and
raw. `mykronos-sast` itself is still running at the time of writing; the closure is
**supported but not yet fully demonstrated**.

**POAM-013 — monthly cadence approximated.** Accepted, unchanged. The not-due path was
verified printing its loud scope statement.

**POAM-014 — no merge gate.** Open, Critical, and confirmed exactly as filed: no required
checks, zero approvals required, no workflow with a live trigger, Actions billing-blocked.
Detection in Concourse is healthy and per-commit, but detection is not prevention.

## The honest summary

Nine entries. **Two are Critical or High and blocked on the same root cause** — the repository
being private on a plan without Advanced Security, with Actions unable to bill. POAM-005,
POAM-006, POAM-010 and POAM-014 all close, or become closable, the moment that changes.

Verification improved today in one real way: the Mykronos ingestion path went from "argument
compatible by inspection" to "observed working, including recovery from a 502". Everything
else in this review is either unchanged or worse than its entry claimed.

**Nothing in this review was closed.** A review that closes nothing is not a failed review;
a review that closes something without new evidence is.
