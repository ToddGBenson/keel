# Plan of Action and Milestones (POA&M)

**Owner:** Compliance Officer · **Control:** CA-5 · **Reviewed:** weekly, formally quarterly

The register of known gaps. Its value is entirely in being **honest and current** — a POA&M
that lists only comfortable findings is worse than none, because it produces documented false
assurance that everything else relies on.

## Entry format

| Field | Notes |
|---|---|
| ID | `POAM-<n>` |
| Weakness | What is actually wrong, specifically |
| Source | Assessment, scan, pentest, incident, red-team, self-identified |
| Control(s) | 800-53 / AIC reference |
| Risk | Critical / High / Medium / Low, with reasoning |
| Affected | Systems, components, data |
| Remediation plan | What will be done |
| **Owner** | A named person, never a team |
| Resources required | Be honest — "none" is usually false and hides the real blocker |
| Milestones | Dated intermediate steps |
| Scheduled completion | Per severity SLA |
| Status | Open / In progress / Risk accepted / Completed |
| Compensating control | What reduces exposure meanwhile |
| Evidence of closure | Required to close — a rescan, a test, an assessment result |

## Register

| ID | Weakness | Control | Risk | Owner | Due | Status |
|---|---|---|---|---|---|---|
| POAM-001 | Agent write-scope boundaries are prompt-enforced, not tool-enforced | AIC-3, AC-6 | Low | *unassigned* | review quarterly | Open — compensating controls in place |
| POAM-002 | Secret guard used keyword matching; blocked all security tooling | AIC-5, IA-5 | Medium | *unassigned* | 2026-08-07 | **Closed** — fixed + regression test |
| POAM-003 | Secret guard matched its own patterns; blocked its own repair | AIC-5 | Medium | *unassigned* | 2026-08-07 | **Closed** — fixed + regression test |
| POAM-004 | Without `jq`, guard scanned `old_string`; blocked removing a secret | AIC-5, IA-5 | **High** | *unassigned* | 2026-08-07 | **Closed** — fixed |
| POAM-005 | GitHub secret scanning + push protection unavailable (private repo, Free plan) | IA-5, SI-7 | Medium | Todd Benson | 2026-11-12 | **REOPENED 2026-08-13** — repo made private; measured `unavailable` |
| POAM-006 | `production` environment has no required reviewers — **G5 is not technically enforced** | CM-3, AC-5 | **High** | Todd Benson | 2026-09-12 | **REOPENED 2026-08-13** — private repo dropped the rule; measured |
| POAM-007 | Verification routine in `configure-github.sh` reported 5 false failures | CA-2 | Medium | *unassigned* | 2026-08-07 | **Closed** — fixed + re-verified |
| POAM-008 | **Solo operation — AC-5 separation of duties cannot be satisfied** | AC-5, CM-5 | **High** | Todd Benson | on 2nd team member | Open — accepted with compensating controls |
| POAM-009 | Commit signing not registered with GitHub — SI-7/CM-14 unsatisfied | SI-7, CM-14 | Medium | Todd Benson | 2026-08-08 | **Closed** — key registered; GitHub verifies commits; required_signatures enabled |
| POAM-010 | **G5 release authorization weakened by the move to Concourse** — reopens POAM-006 | CM-3, AC-5 | **High** | Todd Benson | 2026-09-12 | **REOPENED 2026-08-13** — its fix depended on POAM-006, which the private switch undid |
| POAM-011 | GitHub attestation store unreachable from Concourse — provenance/SBOM attestations lost | SR-4(3), CM-14 | Medium | Todd Benson | 2026-11-11 | Open |
| POAM-012 | CodeQL SARIF from Concourse does not reach GitHub code scanning | SA-11(1) | Low | Todd Benson | 2026-08-13 | **Closed** — the lane that discarded SARIF was deleted; SAST on main now ingests both languages to Mykronos |
| POAM-013 | Monthly monitoring cadence approximated by a weekly trigger | CA-7 | Low | Todd Benson | 2026-11-11 | Open — accepted, detection is loud |

### 2026-08-13 — the repository was made private, and three entries reopened

**Decision.** The system owner directed that the repository be made private, having been shown
the cost first. It was made private at 2026-08-13. The regressions below are the accepted
consequence, not a surprise — and each was **measured after the change**, not predicted.

| | Before (public) | After (private, Free plan) |
|---|---|---|
| Secret scanning | `enabled` | **`unavailable`** |
| Push protection | `enabled` | **`unavailable`** |
| GitHub Advanced Security | n/a | **`unavailable`** |
| `production` protection rules | `required_reviewers`, 1 reviewer | **`branch_policy` only, 0 reviewers** |

**The one that matters is the last row.** The required-reviewers rule was not merely
unenforced — it was **removed**. Environments with protection rules need Pro/Team/Enterprise
on private repositories, so the G5 gate stopped being a technical control the moment the
switch was flipped. POAM-006 reopens, and POAM-010 with it, because POAM-010 was closed *by
relying on* POAM-006's fix.

**What still holds.** Branch protection is intact: 12 required status checks, `enforce_admins`
on, no force-push, no deletions, linear history. CodeQL still runs on pull requests and still
passes — verified on #51 after the change. The `Dependency review` job already detected the
private case and skips loudly, which is why it did not simply break.

**Also observed, and not caused by the visibility change:** repository-level Actions were
found `enabled: false` shortly afterwards, which stopped all 12 required checks reporting and
left every pull request unmergeable. Re-enabled, per the decision to keep the three
PR-triggered workflows live. Worth knowing that this failure mode is silent — the checks do
not fail, they simply never appear.

**Closing any of these requires one of:** making the repository public again, or a GitHub plan
that provides environments and Advanced Security on private repositories. There is no
configuration-only path.

---

### POAM-010 — G5 release authorization weakened by the move to Concourse ⚠️ REOPENED 2026-08-13

**Closed before the change that opened it ever merged.** Release authorization was moved
back to GitHub Actions rather than accepted as a weakening; `release.yml` is the live G5
path and the Concourse release lane was deleted. See ADR-0003 § D2.

**What made the decision.** The compensating guard written for this entry —
`authorize-production` refusing to run when no triggering human was recorded — was what
made the gap concrete rather than theoretical. It could establish that *a* human pressed
the button. It could not establish that they were entitled to, or that they were not the
author. POAM-006 had closed this same gap five days earlier; accepting this entry would
have reopened it to avoid a split pipeline.

**Evidence of closure.** `.github/workflows/release.yml` retains the `production`
environment with required reviewers (verified enabled under POAM-006 on 2026-08-08);
`ci/pipeline.yml` contains no release jobs and `ci/tasks/release.yml` and
`ci/scripts/release.sh` are deleted.

**Residual, tracked under POAM-011:** the artifact is now built by Concourse, so
`release.yml`'s `cosign verify` must match Concourse's signing identity and
`gh attestation verify` cannot work at all. The verify steps are ADAPT stubs and must be
adapted before the first real release — a verification that passes against the wrong
identity is worse than none.

<details>
<summary>Original finding, retained for the audit trail</summary>

**Weakness.** CI/CD execution moved from GitHub Actions to Concourse (#42). The production
release gate was a GitHub `production` environment with required reviewers: the deploy job
**physically could not start** until a named human approved in the GitHub UI, and that
approval record — identity, timestamp, bound to the specific run — **was** the CM-3 change
approval evidence.

Concourse has no equivalent. The replacement is a manually triggered job. It is weaker in
three specific ways:

1. **No approval workflow.** Triggering and approving are the same action, so there is no
   record of a decision distinct from an act.
2. **No second-identity requirement.** The person who wrote the change can release it —
   which is precisely what AC-5 exists to prevent.
3. **Team-level authorization.** Concourse authorizes per team, not per job, so anyone with
   pipeline access can trigger a production release.

**This reopens POAM-006**, closed 2026-08-08 by setting an environment reviewer. That fix
still exists in `.github/workflows/release.yml`, which is kept on disk deliberately and is
the strongest form of this control the repository has ever had.

**Source.** Self-identified during the port, before it shipped.

**Compensating controls, in place now.**
- `authorize-production` has no trigger of any kind — a human must start it.
- The job **refuses to run** when `BUILD_CREATED_BY` is empty. The only authorization
  control on it is that a human starts it, so a build with no recorded human has no
  authorization at all, and deploying anonymously is worse than failing.
- `deploy-staging` must pass first, and it must have passed `release-preflight`, so the
  evidence checks still gate the path.
- The build record captures the triggering user, the commit, and the change record.

**Remediation options, in preference order.**
1. **Move release authorization back to GitHub.** Re-enable `release.yml`, keep Concourse for
   everything upstream of G5. This closes the gap outright and costs a split pipeline.
2. Gate the Concourse job on a signed approval record committed to the repository — a real
   second artifact, verifiable, produced before the trigger.
3. Restrict the Concourse team so release authorization is a distinct identity from the
   pipeline's normal operators.

**Owner.** Todd Benson. **Due.** 2026-09-12 (High, 30 days).

**Evidence of closure.** A demonstration that a production deploy cannot proceed without an
approval record attributable to an identity other than the change author — tested by
attempting it, not by reading the config.

</details>

---

### POAM-011 — GitHub attestation store unreachable from Concourse

**Weakness.** `actions/attest-build-provenance` and `actions/attest-sbom` write to GitHub's
attestation store and are only invocable from Actions. Artifacts built by Concourse have no
entry there, so `gh attestation verify` — the documented verification path — returns nothing
for them.

**Risk.** Medium — **and the original wording of this entry was wrong.** It claimed "cosign
keyless signing and cosign attestations carry over and cover the same SR-4/SR-4(3) ground;
this is a loss of one verification surface, not of provenance itself."

Independent review established that nothing carries over as executable code. `cosign sign`,
`cosign attest` and `cosign verify` in `ci/scripts/supply-chain.sh` are `echo "ADAPT: ..."`
lines. The Actions workflow they replaced ran `anchore/sbom-action`,
`actions/attest-build-provenance` and `actions/attest-sbom` for real.

**Accurate statement: after the port, artifact provenance is zero, not degraded.** Nothing
is signed and nothing is attested. SBOM generation for the artifact lane was also lost and
has been restored (the `build-and-attest` job now runs syft in-job); signing and attestation
have not been, because this repository does not yet build a deployable artifact.

It becomes High the moment an artifact ships, or if anything downstream verifies via
`gh attestation verify` — that call returns nothing for a Concourse-built artifact and must
not be read as a pass.

**Remediation.** Repoint every verification path at `cosign verify-attestation`, and confirm
by attempting to verify an artifact that was never signed — the check must refuse it.

**Owner.** Todd Benson. **Due.** 2026-11-11 (Medium, 90 days).

---

### POAM-012 — CodeQL SARIF no longer reaches GitHub code scanning ✅ CLOSED 2026-08-13

**Closed by deleting the lane rather than by accepting the gap.** The Concourse `sast` job
ran CodeQL over javascript-typescript a second time — after the pull request had already run
it — and wrote the SARIF to a build volume Concourse garbage-collects. Results reached
nothing.

`mykronos-sast` now runs both languages and ingests both to Mykronos, which is the designated
system of record for findings. PR-time CodeQL continues to populate the GitHub Security tab
for both languages. So SAST results now land in exactly two places, both of them durable, and
one duplicate analysis per merge disappeared.

**The stale-results warning below still stands** and is the reason to read this entry.

<details>
<summary>Original finding, retained for the audit trail</summary>

**Weakness.** The code scanning upload API is reachable only from Actions. The keel-owned
`sast` lane now emits SARIF as a build artifact with a printed finding summary instead of
populating the GitHub Security tab.

**Risk.** Low. Mykronos is the system of record for findings, and the `mykronos-sast` lane
still ingests the same SARIF through the same uploader. What is lost is a second view of the
same data, not the data.

**Watch for.** The Security tab now shows *stale* CodeQL results from before the port rather
than none. Stale results that look current are worse than an empty tab. Dismiss the existing
alerts or add a banner, and do not cite that tab as SA-11(1) evidence for any commit after
2026-08-13.

**Owner.** Todd Benson. **Due.** 2026-11-11.

</details>

---

### POAM-013 — Monthly monitoring cadence approximated

**Weakness.** Concourse's bundled `time` resource supports interval, start/stop, and
day-of-week. It has no day-of-month. Expressing a true monthly trigger would require a
third-party resource type, which the pipeline deliberately avoids (SR-3, SR-4).

The `compliance-monthly` job is therefore driven by a 7-day interval and executes only when
the day of the month is 7 or lower.

**Believed once per calendar month; not proven.** The arithmetic holds for fires spaced
*exactly* 168h apart: any such sequence lands in a 7-day window exactly once. Concourse's
`time` resource treats `interval` as a *minimum*, so real spacing is 168h + ε and drifts. A
gap straddling the day-7/day-8 boundary skips a month, and pausing or re-setting the
pipeline resets the phase. An earlier version of this entry asserted it "cannot double up or
skip a month" — that claim was not supportable and has been withdrawn.

A skipped month is silent: the not-due builds are green and the missing one leaves no trace.
**Detection gap, not yet closed:** record the last successful monthly run and alert if it is
more than ~40 days old.

**Risk.** Low, and deliberately mitigated by making the no-op loud: a build that is not due
prints that nothing was assessed and that the run must not be cited as CA-7 evidence for the
month. A silent no-op here would be the exact defect class this repository keeps
rediscovering (L0007, L0008), which is why it is not one.

**Accepted** rather than remediated, pending either day-of-month support upstream or a
vetted resource type.

**Owner.** Todd Benson. **Review.** 2026-11-11.

---

### POAM-008 — Separation of duties under solo operation

**Weakness.** One person holds every role. Producer and approver are the same human, so
AC-5 cannot be satisfied literally. `required_approving_review_count` is set to **0**,
because GitHub forbids approving your own PR and a value of 1 would make merging impossible.

**Decision.** Risk accepted by the system owner, 2026-08-07, to enable solo operation.
Reviewed at every quarterly assessment, and **closed immediately upon a second team member**
joining — not at the next convenient moment. The window where the team has grown but the
controls have not is exactly when "someone reviewed this" becomes false without anyone
noticing.

**Scope of the relaxation — one control, three settings.** GitHub enforces independent
approval in three places (`required_approving_review_count`, `require_code_owner_reviews`,
`require_last_push_approval`); all three are structurally impossible for a single owner and
all three are cleared. Still enforced: `enforce_admins` (no admin bypass), CODEOWNER
routing (advisory), linear history, no force-push, no deletion, conversation resolution,
and **10 required status checks**. Commit signing is separately unsatisfied — see POAM-009. Letting the admin bypass protection
was considered and **rejected**: it would remove every control simultaneously rather than
the one that is structurally impossible.

**Compensating controls.**

| # | Control | Enforcement |
|---|---|---|
| 1 | `/self-review` artifact — independent agent passes with only the diff, story, and threat model as input | **`pr-governance.yml` blocks the merge without it** |
| 2 | Cooling-off — no merge in the session the PR was opened | Warned by CI with the measured PR age |
| 3 | All status checks required — the machine absorbs what the reviewer did | Branch protection |
| 4 | **Quarterly external review of a random sample** by a competent human outside the project | Manual; recorded in `evidence/assessments/` |

Control 4 is the one an assessor will find most credible, because it is the only one
involving an independent human. If it lapses for two consecutive quarters, the compensating
set has failed and this entry must be re-rated.

**Residual risk, stated plainly.** Agent review catches mechanical defects, missed controls,
and untested paths well. It catches **misunderstood requirements poorly**, because it reads
the same requirement the author did. A solo operator will not catch their own misreading, and
no configuration fixes that.

**Note.** Publishing the repository (done 2026-08-08) closed POAM-005 and POAM-006. It does
not touch this entry — separation of duties needs a second person, not a plan change.

**Reference:** `docs/13-solo-operation.md`

---

### POAM-009 — Commit signing capability incomplete ✅ CLOSED 2026-08-08

**Weakness.** An SSH signing key is generated and git is configured, but the key is not
registered with GitHub — `gh ssh-key add --type signing` requires the
`admin:ssh_signing_key` OAuth scope, which needs an interactive `gh auth refresh`.
GitHub therefore reports `verified=false reason=unknown_key`.

**Status of the control.** `required_signatures` is deliberately **not** enabled. Per L0010,
enabling a control the operator cannot satisfy makes every PR permanently unmergeable. The
script probes the capability and refuses. SI-7/CM-14 are honestly unsatisfied rather than
falsely claimed.

**Remediation — DONE 2026-08-08.** The OAuth device flow proved unusable in this
environment (it hung twice). The key was registered instead through the **web UI**
(`https://github.com/settings/ssh/new`, Key type = Signing Key), which needs **no CLI scope
at all** — a simpler path that was available the whole time.

**Evidence of closure:** GitHub reports `verified=true, reason=valid` on commit `faa2af5`;
`gpg.ssh.allowedSignersFile` configured so local verification also passes (`%G? = G`);
`required_signatures` enabled and verified against the live API (9/9 controls).

**Defect found while closing it.** The capability probe tested `gh api user/ssh_signing_keys`
— i.e. *can I list keys*, which needs `admin:ssh_signing_key`. A correctly registered key
therefore reported as MISSING whenever that read scope was absent, conflating "I lack a
scope" with "the control is unsatisfiable". Now tests the thing that actually matters:
does GitHub mark a real signed commit as verified. Needs only `repo`.

### POAM-005 — Server-side secret scanning unavailable ✅ CLOSED 2026-08-08

**Weakness.** GitHub secret scanning and push protection require GitHub Advanced Security,
which is free only on **public** repositories. This repo is private on a Free plan, so
`security_and_analysis` is null.

**Compensating controls.** `gitleaks` runs in the pre-commit hook (full staged diff) and in
`security.yml` over the **full history** on every PR and daily. `guard-write.sh` blocks
credential-shaped content at the agent layer. Coverage is good; what is missing is the
server-side *push* block — the last line of defence if a contributor skips local hooks.

**Remediation — DONE.** Repository made public 2026-08-08. Secret scanning, push protection,
Dependabot security updates, and vulnerability alerts verified enabled via the API. The
server-side push block — the last line of defence if a contributor skips local hooks — now
exists. **Evidence of closure:** `configure-github.sh` CIS check 1.5.1 reports ok.

### POAM-006 — G5 human authorization is not technically enforced ✅ CLOSED 2026-08-08

**Weakness.** Required reviewers on a deployment environment need a paid plan for private
repositories. The `production` environment could not be created with a reviewer gate, so the
deploy job in `release.yml` would **not** block awaiting human approval.

**Why High.** G5 is the control the entire release chain terminates in. Without the
environment gate, "a human authorizes every production deployment" is a documented intention
rather than a mechanism — precisely the overstatement `docs/lessons/0006` warns about.

**Compensating controls.** `release.yml` is `workflow_dispatch`-only, so a deploy requires a
deliberate human trigger. `guard-bash.sh` blocks agents from triggering releases. Branch
protection prevents un-reviewed code reaching `main`.

**Remediation — DONE.** Repository made public 2026-08-08. The `production` environment now
has a required reviewer, so the deploy job in `release.yml` blocks awaiting human approval
and the approval record is the CM-3 evidence. **G5 is now technically enforced.**
**Evidence of closure:** environment created and reviewer confirmed via the API.

### POAM-007 — Control verifier reported false failures

**Weakness.** The verification step in `configure-github.sh` contained a leftover no-op API
call and an eval-based JSON walk that returned null for every field. It reported five failing
controls that were, in fact, correctly applied.

**Why it matters.** A verifier that cries wolf gets distrusted and then ignored — after which
it verifies nothing. This is the third recurrence of the pattern in `docs/lessons/0007`, and
the second time it appeared in my own tooling.

**Fixed.** Rewritten with jq paths and a Python fallback; re-ran and confirmed 8/8 controls
verified true against the live API.

---

### POAM-002/003/004 — Secret guard defects found by dogfooding

**Source.** Self-identified 2026-08-07 while writing `scripts/install-hooks.sh`. The guard
blocked the write, then blocked its own repair, then blocked the repair of the repair. Three
distinct defects surfaced in sequence.

**POAM-002 — keyword matching (Medium).** `guard-write.sh` matched bare keywords such as the
AWS secret-key parameter name. Those strings appear legitimately in secret-*detection* code:
this hook, `scripts/install-hooks.sh`, `.github/workflows/security.yml`, and the
`scanner-triage` skill. The control blocked all security tooling work in the repo.
**Fixed:** named credentials now require an assignment *and* a plausible value; opaque token
formats remain value-shaped.

**POAM-003 — self-matching patterns (Medium).** The detection patterns matched their own
source text, so any edit to the hook was blocked — **including the fix for POAM-002.** A
control that cannot be repaired through the normal path forces either a bypass or an
exception, and both are worse than the original defect.
**Fixed:** `[x]` character classes match identically but cannot self-trigger. Preserved with
a comment so a future edit does not reintroduce it.

**POAM-004 — fallback scanned removed text (High).** `jq` is not installed in this
environment. The fallback set `content="$payload"`, i.e. the *entire* hook payload including
`old_string`. The guard therefore scanned the text being **removed** — meaning **an edit that
takes a secret out of a file was blocked.** That is precisely the operation you most need to
perform after a leak, and the guard forbade it while appearing to protect you.
Rated High because it makes remediation impossible during exactly the incident it exists for.
**Fixed:** Python fallback extracting only new content; if no parser is available the hook
now **fails open with a warning** rather than blocking every edit, since CI secret scanning
is authoritative.

**Evidence of closure.** `.claude/hooks/selftest.sh` — 20 assertions, including four
regression tests named for these defects. Run: 20 passed, 0 failed.

**Lesson recorded.** Three of these were only findable by *using* the control, not reading
it. This is the `control-assessment` skill's central claim demonstrated on our own
infrastructure: **test beats examine.** A control that examines well and fails when exercised
is the finding that matters. `selftest.sh` is now the standing test, and it runs at
quarterly assessment.

---

### POAM-001 — Agent write-scope is not technically enforceable

**Weakness.** `docs/compliance/ai-inventory.md` § Section B assigns each agent an expected
write scope (e.g. `product-owner` writes issues and product docs, not source). That boundary
exists only in the agent's role prompt. A confused or adversarial model can write outside it.

**Source.** Self-identified during platform build, 2026-08-07.

**Verification performed.** Claude Code agent frontmatter grants tool *types* (`Write`,
`Edit`), not path scopes. `settings.json` permissions are project-wide, not per-agent. The
`PreToolUse` hook payload was probed directly and carries `cwd`, `session_id`, `tool_name`,
`tool_input`, `permission_mode`, `prompt_id`, `tool_use_id`, `transcript_path` — and **no
field identifying the acting subagent**. No enforcement layer currently available can scope
writes per agent.

**Risk: Low.** The high-consequence boundaries — approve, merge, push, production, secrets —
*are* enforced by `guard-bash.sh`, `settings.json` deny rules, and branch protection. What
remains unenforced is role hygiene: the wrong agent authoring the right artifact. That is
caught downstream by human review before anything merges.

**Compensating controls.**
1. G3 review by a non-author — a human sees every source diff before merge
2. CODEOWNERS routes source paths to engineering review regardless of author
3. AI-authorship declaration (AIC-6) names the producing agent on every PR
4. Monthly agent audit (AIC-12) samples merged PRs for role/artifact mismatch

**Remediation plan.** No action available today. Re-evaluate each quarter against Claude Code
releases; if agent identity becomes available to hooks, implement path scoping in
`guard-write.sh` and upgrade the enforcement table in `docs/11-ai-agent-controls.md`.

**Why this is recorded rather than quietly tolerated.** The platform's own rule (PD-7) is
that a false compliance claim is worse than an open finding. The inventory originally implied
this boundary was enforced; it is not. A documented weak control is defensible at assessment.
An overstated one is the finding that costs credibility on every other control in the map.

---

## Rules

**Every Other-Than-Satisfied assessment result becomes an entry.** No exceptions, including
for gaps discovered close to a release.

**Due dates come from severity** (`docs/10-definitions.md`): Critical 7d · High 30d ·
Medium 90d · Low next planned cycle.

**Closure requires evidence of remediation** — a passing rescan, a new test, a reassessment.
Closing on assertion is how a POA&M becomes fiction.

**Risk acceptance is not closure.** It is a status, with a human approver, an expiry date, a
named compensating control, and a review. Indefinite acceptance is not acceptance; it is a
decision to carry the risk permanently, and it should be written that way if that is what is
meant.

## The three signals to watch

1. **Entries past due** — report first, every time.
2. **Entries extended more than once** — that is not a schedule problem. It is a resourcing
   or a will problem, and naming it as one is the Compliance Officer's job.
3. **Entries closed without evidence** — audit a sample of closures every quarter. This is
   where a register quietly stops being true.

## Escalation

Past-due Critical or High → escalate to a human immediately, do not wait for the weekly
review. Twice-extended entries → escalate with the resourcing question stated plainly.
