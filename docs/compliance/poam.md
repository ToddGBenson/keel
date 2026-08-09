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
| POAM-005 | GitHub secret scanning + push protection unavailable (private repo, Free plan) | IA-5, SI-7 | Medium | Todd Benson | 2026-08-08 | **Closed** — repo made public; verified enabled |
| POAM-006 | `production` environment has no required reviewers — **G5 is not technically enforced** | CM-3, AC-5 | **High** | Todd Benson | 2026-08-08 | **Closed** — public repo; environment reviewer set and verified |
| POAM-007 | Verification routine in `configure-github.sh` reported 5 false failures | CA-2 | Medium | *unassigned* | 2026-08-07 | **Closed** — fixed + re-verified |
| POAM-008 | **Solo operation — AC-5 separation of duties cannot be satisfied** | AC-5, CM-5 | **High** | Todd Benson | on 2nd team member | Open — accepted with compensating controls |
| POAM-009 | Commit signing not registered with GitHub — SI-7/CM-14 unsatisfied | SI-7, CM-14 | Medium | Todd Benson | 2026-08-08 | **Closed** — key registered; GitHub verifies commits; required_signatures enabled |

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
