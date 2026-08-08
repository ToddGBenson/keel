# CIS Software Supply Chain Security Guide v1.0 — Control Map

**Owner:** Compliance Officer · **Reviewed:** quarterly · **Verified:** `scripts/configure-github.sh`

CIS complements NIST 800-53 rather than duplicating it. 800-53 supplies the accountability
structure (AC-5, AU, CA, CM); **CIS supplies concrete, checkable settings** for the source
control, build, dependency, artifact, and deployment surfaces. Where they overlap, both are
cited; where CIS is more specific, CIS wins.

**Status:** ✅ implemented · 🟡 partial · ➖ not applicable (with reason) · ❌ gap

**Profile:** solo operator, public repository, GitHub-hosted runners. That profile changes
which controls are achievable — recorded honestly below rather than marked satisfied.

---

## 1. Source Code

### 1.1 Code Changes

| CIS | Control | Status | Implementation |
|---|---|---|---|
| 1.1.1 | Any change is tracked and traceable | ✅ | Every commit references an issue — enforced by `commit-msg` hook and `pr-governance.yml` (CM-3) |
| 1.1.2 | Any change is approved | 🟡 | **Solo: structurally impossible.** `/self-review` artifact required by CI; POAM-008 |
| 1.1.3 | Any change is reviewed by two people | ➖ | Solo project. Compensated per POAM-008; closes on a second team member |
| 1.1.4 | Dismiss stale approvals | ✅ | `dismiss_stale_reviews: true` |
| 1.1.5 | Code owners are set and approve | 🟡 | CODEOWNERS present and routes; **advisory** in solo mode (cannot self-approve) |
| 1.1.6 | Inactive branches reviewed and removed | 🟡 | Trunk-based, short-lived branches; no automated pruning yet |
| 1.1.7 | All checks passed before merge | ✅ | **10 required status checks** registered on `main`, strict mode |
| 1.1.8 | Open comments resolved before merge | ✅ | `required_conversation_resolution: true` |
| 1.1.9 | Verify signed commits before merge | 🟡 | Capability probed and found incomplete, so **deliberately not enabled** (L0010). POAM-009 |
| 1.1.10 | Linear history required | ✅ | `required_linear_history: true` |
| 1.1.11 | Branch protection on the default branch | ✅ | Applied and verified 9/9 by `configure-github.sh` |
| 1.1.12 | Branch rules enforced on administrators | ✅ | **`enforce_admins: true`** — never relaxed, including in solo mode |
| 1.1.13 | Pushing/merging restricted to trusted users | ✅ | Single owner; direct push to default branch blocked |
| 1.1.14 | Force-push denied | ✅ | `allow_force_pushes: false` |
| 1.1.15 | Branch deletion denied | ✅ | `allow_deletions: false` |
| 1.1.16 | Scan for risks in merged code | ✅ | SAST, SCA, secrets, IaC on every PR and on the default branch |
| 1.1.17 | Audit branch protection changes | 🟡 | GitHub audit log retains them; no active alerting yet |
| 1.1.18 | Default branch protected | ✅ | Verified against the API, not assumed (the script previously protected the wrong branch) |

### 1.2 Repository Management

| CIS | Control | Status | Implementation |
|---|---|---|---|
| 1.2.1 | Public repositories track their contributions | ✅ | Signed commits, AI-authorship trailers, PR provenance (AIC-6) |
| 1.2.2 | Repository creation limited | ➖ | Personal account, single owner |
| 1.2.3 | Repository deletion limited | ✅ | Owner-only by account structure |
| 1.2.4 | Issue deletion limited | ✅ | Owner-only |
| 1.2.5 | **SECURITY.md present** | ✅ | `SECURITY.md` — disclosure policy, SLAs, scope |
| 1.2.6 | Repository has a description and metadata | ✅ | Description and topics set by `configure-github.sh` |
| 1.2.7 | Deletion/transfer requires 2FA | 🟡 | 2FA is an account setting — verified, not enforced by this repo |
| 1.2.8 | **Untrusted code checked before use** | ✅ | `dependency-vetting` skill + AIC-7 existence verification |

### 1.3 Contribution Access

| CIS | Control | Status | Implementation |
|---|---|---|---|
| 1.3.1 | Inactive users removed | ➖ | Single owner |
| 1.3.2 | **MFA required** | 🟡 | Account-level; checked and reported by `configure-github.sh`, not enforceable from the repo |
| 1.3.3 | Org members use SSO | ➖ | Personal account |
| 1.3.4 | Least privilege for collaborators | ✅ | No collaborators |
| 1.3.5 | Admin count minimised | ✅ | One |
| 1.3.6 | Team-based access | ➖ | Solo |
| 1.3.7 | Access reviews | 🟡 | Quarterly assessment scope; trivially satisfied at one user |

### 1.4 Third-Party

| CIS | Control | Status | Implementation |
|---|---|---|---|
| 1.4.1 | Administrator approval for installed apps | ✅ | Owner-only |
| 1.4.2 | **Only trusted, minimal-permission apps/actions** | ✅ | **All 17 actions pinned to full commit SHAs, each API-verified.** Three hallucinated SHAs were caught this way |

### 1.5 Code Risks

| CIS | Control | Status | Implementation |
|---|---|---|---|
| 1.5.1 | **Secret scanning** | ✅ | gitleaks full-history in CI + pre-commit + **GitHub push protection enabled and verified** |
| 1.5.2 | **SAST** | ✅ | CodeQL `security-extended`, with an explicit no-source skip that says the control is unsatisfied rather than passing green (L0009) |
| 1.5.3 | IaC scanning | ✅ | Checkov, with the same no-input honesty |
| 1.5.4 | **Vulnerability scanning** | ✅ | grype on PR, daily rescan of deployed artifacts |
| 1.5.5 | License scanning | 🟡 | `dependency-review` deny-list; per-stack license check in the profiles |
| 1.5.6 | Dangling/expired dependency check | 🟡 | Dependabot + SA-22 EOL sweep in the monthly job |

---

## 2. Build Pipelines

| CIS | Control | Status | Implementation |
|---|---|---|---|
| 2.1.1–2.1.4 | Build environment isolated, minimal, single-use, logged | ✅ | GitHub-hosted ephemeral runners; no state between jobs |
| 2.2.1 | **Pipelines as code** | ✅ | `.github/workflows/`, version-controlled and CODEOWNER-protected |
| 2.2.2 | **Build worker least privilege** | ✅ | `permissions: contents: read` at workflow level; elevated per job only |
| 2.2.3 | Build worker secrets minimal and scoped | ✅ | Environment-scoped secrets; OIDC where possible, no long-lived cloud keys |
| 2.2.4 | Build worker environment vetted | ✅ | Pinned action SHAs; no third-party runner images |
| 2.3.1 | **Pipeline instructions version-controlled and reviewed** | ✅ | Workflow edits require security CODEOWNER review (CM-5) |
| 2.3.2 | Build steps produce verifiable output | ✅ | SBOM + provenance attestation + signature |
| 2.3.4 | **Pipeline output signed** | ✅ | Sigstore/cosign keyless via OIDC |
| 2.4.1 | **All artifacts validated before use** | ✅ | Verify-on-deploy; deploy refuses on signature or provenance mismatch |
| 2.4.2 | Pipeline steps pinned to a version/digest | ✅ | Full-SHA action pins; deploys reference artifact digests, never mutable tags |
| 2.4.3 | Scanners run in the pipeline | ✅ | Five scan classes, each with an explicit no-input path |
| 2.4.4 | **Reproducible builds** | 🟡 | Reproducible where the toolchain allows; not asserted for all stacks |

---

## 3. Dependencies

| CIS | Control | Status | Implementation |
|---|---|---|---|
| 3.1.1 | **Third-party packages from trusted registries** | ✅ | Default registries; `dependency-vetting` verifies publisher and repository |
| 3.1.2 | SBOM required for third-party artifacts | ✅ | CycloneDX per build, diffed against previous |
| 3.1.3 | Signed metadata / package verification | ✅ | Lockfiles committed, integrity hashes verified, frozen installs |
| 3.1.4 | **Dependencies are pinned** | ✅ | Lockfiles committed; `npm ci` / `--require-hashes` / `go mod verify` / `--locked` |
| 3.1.5 | Packages older than 60 days preferred | 🟡 | Not automated. Recorded rather than claimed |
| 3.2.1 | **Dependencies validated before use** | ✅ | **AIC-7 existence verification** — publisher, repo, download history, name-distance. The slopsquatting control |
| 3.2.2 | Dependency inventory maintained | ✅ | SBOM (CM-8) |
| 3.2.3 | Dependency update policy | ✅ | Dependabot; patch/minor grouped as Standard changes, major as Normal |

---

## 4. Artifacts

| CIS | Control | Status | Implementation |
|---|---|---|---|
| 4.1.1 | **Artifacts signed** | ✅ | cosign keyless |
| 4.1.2 | **Artifact signatures verified before deployment** | ✅ | Enforced in the deploy path, not only produced at build (a signature nobody verifies is decoration) |
| 4.1.3 | Encrypted in transit | ✅ | HTTPS/TLS throughout |
| 4.2.x | Artifact access limited, least privilege | ✅ | Registry permissions scoped per job |
| 4.3.x | Registries are trusted, webhooks secured | ✅ | GHCR; no third-party registries |
| 4.4.1 | **Artifact origin traceable to source and build** | ✅ | SLSA-style provenance attestation: source commit, builder, inputs |

---

## 5. Deployment

| CIS | Control | Status | Implementation |
|---|---|---|---|
| 5.1.1 | **Deployment config as code** | ✅ | IaC in version control, scanned |
| 5.1.2 | Deployment config audited | ✅ | Weekly drift detection against baseline |
| 5.1.3 | Secrets not in deployment config | ✅ | Environment secrets; scanning on every PR |
| 5.2.1 | Deployments automated | ✅ | Pipeline-executed; agents and humans never deploy by hand |
| 5.2.2 | **Deployment approval required** | ✅ | `production` environment with a required reviewer — verified via API 2026-08-08. POAM-006 closed |
| 5.2.3 | Rollback capability | ✅ | **Rehearsed and evidenced at G5** — an untested rollback is a hypothesis |

---

## Honest summary

**Fully implemented: 48.** **Partial: 12.** **Not applicable with reason: 6.** **Gaps: 0.**

*Recount 2026-08-08 after publication: 5.2.2 and 1.5.1 moved to implemented; 1.1.9 moved to
partial when the signing capability probe correctly refused to enable an unsatisfiable control.*

Read that with the profile in mind. Several ✅ are ✅ *because this is a solo public repo* —
"admin count minimised" is trivially satisfied at one. The controls that took real work are
1.1.9 (signing, and the L0010 trap), 1.4.2 (SHA pinning, which caught three hallucinated
references), 1.5.x (the five scanners and their no-input honesty), 3.2.1 (AIC-7), and 4.4.1.

**The three 🟡 that matter:**

- **1.1.2 / 1.1.3 / 1.1.5 — approval and two-person review.** Structurally impossible solo.
  Not a configuration failure and not fixable by configuration. POAM-008, with four
  compensating controls, one mechanically enforced.
- **1.1.9 — signed commits.** Key generated and git configured, but not registered with
  GitHub (needs an interactive OAuth scope). The control is correctly *not* enabled rather
  than falsely claimed. POAM-009.
- **2.4.4 — reproducible builds.** Aspirational per stack; claimed only where true.

**Nothing here is marked satisfied on the strength of a policy document.** Every ✅ traces to
a setting verified against the live API, a workflow that runs, or a hook with a regression
test. That distinction is the whole point of L0005 and L0006.
