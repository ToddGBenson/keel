# Setup — Turning the Controls On

Most of this platform is files. Some of it is **GitHub settings**, and a repository cannot
configure its own branch protection. Until this page is complete, the separation-of-duties
and release-authorization controls are documentation rather than controls.

That gap — a clean-looking governance repo with no enforcement behind it — is the most
common way one of these programs produces false assurance. Work through it in order.

---

## 1. Branch protection on `main` — AC-5, CM-5, AIC-2

Settings → Branches → Add rule for `main`:

| Setting | Value | Why |
|---|---|---|
| Require a pull request before merging | ✅ | No direct-to-main change |
| Required approvals | **1+** | The producer is never the approver |
| Dismiss stale approvals on new commits | ✅ | An approval covers the diff it saw, not later ones |
| **Require review from Code Owners** | ✅ | This is what makes `.github/CODEOWNERS` real |
| Require conversation resolution | ✅ | An unanswered review question is not an approval |
| Require status checks to pass | ✅ | See §2 |
| Require branches up to date | ✅ | Green on a stale base proves nothing |
| **Require signed commits** | ✅ | Cryptographic attribution — SI-7, CM-14 |
| Require linear history | ✅ | A readable, attributable audit trail |
| **Do not allow bypassing the above** | ✅ | **The one that matters most** |
| Allow force pushes | ❌ | History is the AU-12 audit trail |
| Allow deletions | ❌ | |

**"Do not allow bypassing" is the difference between a control and a documented
intention.** With admin bypass enabled, everything above is advisory and an assessor will
say so. If a genuine emergency needs it, that is the emergency change procedure with its
own record — not a quiet click.

## 2. Required status checks

Add each as required once it has run at least once:

```
Process compliance                    (pr-governance.yml)  ← CM-3, CM-5, AIC-6
Dependency review (SR-3, SR-4, AIC-7) (pr-governance.yml)
Build / Lint & static typing / Test & coverage   (ci.yml)
SAST — CodeQL (SA-11(1))              (security.yml)
Secret scanning (IA-5)                (security.yml)
SCA — dependency vulnerabilities      (security.yml)
IaC & configuration (CM-6, CM-7)      (security.yml)
Suppression audit                     (security.yml)
Eval suite vs. baseline               (ai-evaluation.yml)  ← if you ship AI features
Guardrail verification                (ai-evaluation.yml)
```

## 3. The `production` environment — **this is gate G5**

Settings → Environments → New environment → `production`:

- **Required reviewers:** the humans authorized to release. *Without this, `release.yml`
  deploys with no human in the loop and G5 does not exist.*
- **Wait timer:** optional; a few minutes creates a deliberate pause before production.
- **Deployment branches:** `main` only.
- **Environment secrets:** deploy credentials live here, scoped to this environment, never
  as repo-wide secrets.

Also create `staging` with no required reviewers.

The approval GitHub records here — identity and timestamp — **is** the CM-3 change-approval
evidence. It is not a copy of the evidence; it is the artifact itself.

## 4. Teams and CODEOWNERS

Create the teams referenced in `.github/CODEOWNERS`, then replace the `@your-org/*`
placeholders with your real team slugs:

`engineering` · `engineering-leads` · `security` · `ai-risk` · `compliance` · `platform` ·
`data`

**Small team?** A team can have one member. What must not happen is a person approving
their own work — record the role compression in the SSP under AC-5 with its compensating
control (independent agent invocation for produce/review separation, or an external
reviewer on a cadence). A recorded compression is defensible; a fictional org chart is not.

## 5. Repository security settings

Settings → Code security and analysis — enable all of:

Dependency graph · Dependabot alerts · Dependabot security updates · Secret scanning ·
**Secret scanning push protection** · CodeQL (default or advanced via `security.yml`) ·
Private vulnerability reporting.

Push protection is the cheapest control here and it stops the failure that is most
expensive to unwind — a credential in history requires rotation, not deletion.

## 6. Actions permissions

Settings → Actions → General:

- Workflow permissions: **Read repository contents** (elevate per job, never globally — AC-6)
- ❌ Allow GitHub Actions to create and approve pull requests — *an agent-approved PR
  defeats AC-5 entirely*
- Allowed actions: restrict to the SHA-pinned set this repo uses

## 7. Install hooks and run the self-test

```bash
bash scripts/install-hooks.sh     # git pre-commit + commit-msg, and chmod the guards
bash .claude/hooks/selftest.sh    # 20 assertions against the agent guardrails
```

The self-test exercises each guard by **attempting the thing it should block** and confirming
it blocks — and confirming it does *not* block legitimate work. Expect `20 passed, 0 failed`.

**Run it after any edit to a guard hook.** Three real defects in these hooks were found only
by using them, not by reading them (POAM-002/003/004) — including one where the guard blocked
edits that *removed* a secret. Four of the assertions are regression tests for those.

A control you have not seen block anything is a control you are assuming.

## 8. Install gitleaks

```bash
# https://github.com/gitleaks/gitleaks
```

The pre-commit hook falls back to a coarse regex without it. Server-side CI re-runs
everything, so a local bypass is **detected** rather than trusted.

## 9. Adapt the workflows

Every `run:` step marked `ADAPT:` needs your build, test, and scan commands. The structure
is the control; the shell is yours.

Do not weaken these while adapting:

- **Fail on *new* findings, not total.** Gating on absolute counts makes the pipeline red
  forever and everyone learns to ignore it — at which point it stops being a control.
- **Least-privilege `permissions:` per job**, never a global elevation.
- **Third-party actions pinned to full commit SHAs**, never tags. A tag is mutable, and a
  compromised action tag compromises everything it touches.
- **Never `pull_request_target`** on untrusted input; fork PRs never receive secrets.
- **Signature verification enforced in the deploy path**, not only produced at build time.

## 10. Seed the compliance artifacts

- `docs/compliance/ai-inventory.md` — enumerate every AI system and every agent. *An
  organization that cannot enumerate its AI systems cannot govern them, and this is the
  first artifact an AI assessor asks for.*
- `docs/compliance/ssp-outline.md` — instantiate per system. Record role compressions
  honestly.
- `docs/compliance/poam.md` — every 🟡 in the control map gets an entry with an owner and
  a date.

---

## Verification — prove the controls actually block

A control you have not tested is a hypothesis. Run each of these and confirm it is refused:

| Test | Expected | Control |
|---|---|---|
| Open a PR with no linked issue | `Process compliance` fails | CM-3, CM-5 |
| Open a PR with no AI-authorship declaration | `Process compliance` fails | AIC-6 |
| Approve your own PR | GitHub refuses | AC-5 |
| Push directly to `main` | Rejected | CM-5 |
| Commit unsigned | Rejected | SI-7 |
| Add a suppression with no issue ref or expiry | `Suppression audit` fails | SA-11 |
| Trigger `release.yml` | Blocks awaiting a human reviewer | CM-3, G5 |
| Ask an agent to `git commit --no-verify` | `guard-bash.sh` blocks | AIC-3 |
| Ask an agent to approve a PR | `guard-bash.sh` blocks | AIC-2 |

Record the results in `evidence/assessments/<quarter>/`. This is your first control
assessment, and testing beats examining — a control that examines well and fails when
tested is exactly the finding that matters.
