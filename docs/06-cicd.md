# 06 — CI/CD Pipeline

**Owner:** Release Manager (pipeline) + Security Engineer (gates)
**Implementation:** `.github/workflows/`

The pipeline is where the process stops being a document and becomes a mechanism. Every
gate item that *can* be automated is automated, because a control that depends on someone
remembering is not a control.

## Stages

```
 LOCAL            PR                    MERGE              BUILD              STAGING           PROD
 ─────            ──                    ─────              ─────              ───────           ────
 secrets  ──▶ build + test  ──▶  required reviews  ──▶  artifact   ──▶  deploy staging ──▶ [G5 HUMAN]
 lint         SAST/SCA/IaC        branch protection      SBOM             DAST                  │
 unit         secrets scan        all checks green       sign             e2e + perf            ▼
 pre-commit   SBOM diff           story link             attest           smoke            canary deploy
 hooks        coverage            DoD complete           provenance       drift check      health checks
              AI evals            signed commits                                           auto-rollback
                                                                                                │
                                                                                                ▼
                                                                                     continuous monitoring
```

**One artifact, promoted.** The binary tested in staging is byte-identical to the one that
reaches production. Never rebuild per environment — a rebuild invalidates every test that
came before it, and it is how "worked in staging" becomes an incident. Configuration is
injected at deploy time; the artifact is immutable. (CM-2, SI-7)

## Stage 1 — Local (pre-commit)

Fast checks that catch the embarrassing class of problem before it is public. Installed via
`.claude/settings.json` hooks and `scripts/install-hooks.sh`.

- Secret detection (gitleaks) — **blocking**
- Format + lint — blocking
- Unit tests for changed packages — blocking
- Conventional commit message + issue reference — blocking
- Large-file and binary guard — blocking

`--no-verify` is prohibited (`docs/11-ai-agent-controls.md` AIC-3). If a hook blocks you,
the hook is working. A CI job re-runs these checks server-side so local bypass is detected
rather than trusted.

## Stage 2 — Pull request (`ci.yml`, `security.yml`, `ai-evaluation.yml`)

Every check below is a **required status check** on `main`. Required means the merge button
is disabled, not that a reviewer is expected to notice.

| Check | Tool | Fails on | Control |
|---|---|---|---|
| Build | native toolchain | any error | SA-15 |
| Unit + integration tests | native runner | any failure | SA-11 |
| Coverage | native | below threshold, or a **drop** vs. `main` | SA-11 |
| Lint / static typing | native | any error | SA-15 |
| SAST | CodeQL | new High/Critical | SA-11(1) |
| Dependency vulnerabilities | dependency-review + osv/grype | new High/Critical | RA-5, SR-3 |
| License compliance | license scanner | disallowed license | SA-4 |
| Secrets | gitleaks (full history) | any hit | IA-5 |
| IaC configuration | checkov/tfsec | High/Critical misconfig | CM-6, CM-7 |
| Container image | trivy | High/Critical, fixable | RA-5, SR-11 |
| SBOM generation + diff | syft → CycloneDX | unexpected component delta | CM-8, SR-4 |
| PR governance | `pr-governance.yml` | no issue link, DoD incomplete, no AI declaration | CM-3, CM-5 |
| AI evals | `ai-evaluation.yml` | eval regression vs. baseline | AI RMF MEASURE |

**Fail on new, not on total.** Gating on the absolute finding count in a real codebase
means the pipeline is red forever and everyone learns to ignore it. Gate on the delta the
PR introduces; drive the existing backlog down on SLA through the POA&M. This is the single
most important design decision in the pipeline and the one most often gotten wrong.

## Stage 3 — Merge gate

Branch protection on `main` — configured, not documented-and-hoped:

- All required status checks pass
- ≥1 approving review from a **CODEOWNER who is not the author**
- Stale approvals dismissed on new commits
- Conversations resolved
- Signed commits required (SI-7, CM-14)
- Linear history; no force-push; **no administrator bypass**
- Security-relevant paths require the security owner (see `.github/CODEOWNERS`)

Administrator bypass disabled is what separates a real control from a documented intention.
If an emergency needs it, that is the emergency change procedure with its own record — not
a quiet click.

## Stage 4 — Build & supply chain (`sbom-and-sign.yml`)

Post-merge on `main`, in an ephemeral, least-privilege runner:

1. **Build** the immutable artifact, reproducibly where the toolchain allows.
2. **SBOM** in CycloneDX, attached to the artifact — the component inventory required by
   CM-8 and the thing that makes the next Log4Shell a one-hour query instead of a two-week
   audit.
3. **Sign** with Sigstore/cosign, keyless via OIDC. (CM-14, SI-7, SR-11)
4. **Attest provenance** — SLSA-style: what source commit, what builder, what inputs.
   (SR-4, SR-4(3))
5. **Push** to the registry with an immutable digest reference. Deploys reference digests,
   never mutable tags. `:latest` in a deployment manifest is an unpinned dependency on
   whatever ran last.
6. **Verify on pull** — the deploy job verifies signature and provenance before running the
   artifact, and refuses on mismatch. A signature nobody verifies is decoration.

## Stage 5 — Staging

Production-like: same topology, same configuration mechanism, representative data volume,
**no production personal data** (synthetic or properly de-identified — MP-6, and a
compliance finding if violated).

Runs: deploy verification · full integration + E2E · DAST (SA-11(8)) · performance against
the NFR thresholds · configuration drift check against the baseline (CM-2, CM-6) ·
**rollback rehearsal** — actually roll back, then roll forward. An untested rollback plan
is a hypothesis, and G5 asks for a fact.

## Stage 6 — Production (G5, human-gated)

The authorization is a **GitHub Environment protection rule** with required reviewers. The
deploy job cannot start until a human approves it in the GitHub UI, and the approval is
recorded with identity and timestamp. That record is the CM-3 change-approval evidence.

Deployment is progressive by default:

**Canary** — small traffic slice, watch error rate/latency/saturation against defined
thresholds for a defined bake time, then expand. **Blue-green** where canary is impractical.
**Automated rollback** on threshold breach — no human decision in the loop, because the
human decision arrives ten minutes late every time.

Post-deploy: smoke tests, health verification, deployment record written to
`evidence/releases/<version>/`, monitoring confirmed live.

## Stage 7 — Continuous monitoring (`compliance-evidence.yml`)

Scheduled, not event-driven — because the risk changes while your code does not:

- Daily dependency + container rescan of **deployed** artifacts (a clean scan at build time
  says nothing about a CVE published yesterday) — RA-5, SI-2
- Weekly configuration drift detection against baseline — CM-2, CM-6
- Weekly secret sweep of the full history
- Monthly SBOM refresh and vulnerability re-query
- Quarterly control assessment evidence collection — CA-2, CA-7
- Continuous alerting on pipeline anomalies (unexpected permission use, unsigned artifact,
  workflow file change) — AU-6, SI-4

## Pipeline security

The pipeline is production infrastructure with production credentials. Treat it as an attack
surface, because it is:

- **Least privilege by default** — `permissions: contents: read` at the workflow level;
  elevate per job, never globally. (AC-6)
- **OIDC federation, no long-lived cloud keys.** (IA-5)
- **Pin third-party actions to a full commit SHA**, never a tag — tags are mutable and a
  compromised action tag is a supply-chain compromise of everything it touches. (SR-3, SR-11)
- **`pull_request_target` is prohibited** on untrusted input; fork PRs never receive secrets.
- **Workflow files are CODEOWNER-protected** — a PR that edits `.github/workflows/` requires
  security review, because otherwise the pipeline gates itself out of existence. (CM-5)
- **Ephemeral runners**; no state carried between jobs except declared artifacts.
  **keel itself no longer satisfies this.** Its PR gate runs on a persistent self-hosted
  runner because hosted Actions are billing-blocked (POAM-014). A persistent runner keeps a
  work directory and a tool cache between jobs, and shares a host with Concourse and Vault.
  The compensating rules — fork PRs refused, no Vault or Concourse credentials in Actions
  secrets, repository-scoped rather than org-scoped — are in
  `docs/runbooks/self-hosted-runner.md`. Prefer hosted runners if you have them; this is a
  deviation recorded as such, not a recommendation.
- **Signed, immutable audit logs** of every run, retained per `10-definitions.md`. (AU-9, AU-11)

## When the pipeline is the bottleneck

Slow pipelines get bypassed, and a bypassed control is worse than an honest absence of one
because it still shows green on the assessment. Target PR feedback under 10 minutes.

Legitimate levers: parallelize, cache dependencies (never cache *results*), run only
affected tests on PR and the full suite on merge, move deep scans (DAST, full SCA, pentest
regression) to the merge or nightly stage.

Illegitimate levers: removing a gate, downgrading a fail to a warning, `continue-on-error`
on a security check. If a gate must be relaxed, it goes through the process-change path
with a human approval and a recorded rationale — visibly, not in a quiet diff.

**Control mapping:** CM-2, CM-3, CM-3(2), CM-4, CM-5, CM-6, CM-7, CM-8, CM-14, SA-10,
SA-11(1)(8), SA-15, SR-3, SR-4, SR-4(3), SR-11, RA-5, SI-2, SI-3, SI-4, SI-7, AU-2, AU-6,
AU-9, AU-11, AU-12, AC-6, IA-5, CP-10.
