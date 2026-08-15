# NIST SP 800-53 Rev. 5 — Control Map

**Owner:** Compliance Officer · **Reviewed:** quarterly · **Command:** `/status risks`

How this SDLC implements the controls, where each is implemented, and what evidence proves
it operated. This is the artifact an assessor asks for first.

**Scope note.** This maps the controls the *development lifecycle* implements. A full system
authorization also requires operational, physical, and personnel control families that live
outside this repository. Where a control is only **partially** satisfied by the SDLC, that is
stated — overstating scope here is the fastest way to fail a real assessment.

**Status key:** ✅ Implemented · 🟡 Partial · ⬜ Planned · ➖ Out of SDLC scope

---

## SA — System and Services Acquisition

| Control | Requirement | Implementation | Evidence | Status |
|---|---|---|---|---|
| SA-3 | SDLC with security integrated | This entire process; six gates with security at G2 and G4 | `docs/00-overview.md`, gate evidence bundles | ✅ |
| SA-3(1) | Integrate security into the SDLC | Relevance triage at G0/G1 forces G2; security co-approves G2 and G4 | Triage flags, approval records | ✅ |
| SA-4 | Acquisition process | Dependency justification, license check, maintenance signal check | PR bodies, license scan | ✅ |
| SA-4(3) | Development methods, techniques, practices | Documented process, test-first, code review, threat modeling | `docs/03`–`docs/06` | ✅ |
| SA-8 | Security and privacy engineering principles | Applied and stated at G2, item 9 | Design notes | ✅ |
| SA-10 | Developer configuration management | Git, signed commits, branch protection, change records | Git history, CM records | ✅ |
| SA-10(1) | Software/firmware integrity verification | Cosign signing, SLSA provenance, verify-on-deploy | Attestations | ✅ |
| SA-11 | Developer testing and evaluation | G4 verification, three independent verdicts | `evidence/<issue>/g4/` | ✅ |
| SA-11(1) | Static code analysis | CodeQL + language linters, every PR, gated on new findings | SARIF | ✅ |
| SA-11(2) | Threat modeling and vulnerability analysis | STRIDE at G2, mandatory for flagged stories | Threat models | ✅ |
| SA-11(5) | Penetration testing | Quarterly + pre-major-release | Pentest reports | 🟡 schedule-dependent |
| SA-11(8) | Dynamic code analysis | DAST on staging, per release | DAST reports | ✅ |
| SA-15 | Development process, standards, tools | This process; tools pinned and version-controlled | Repo | ✅ |
| SA-15(3) | Criticality analysis | RICE + risk tiering at G0; AI risk tiering at G2 | Idea records, AIAs | 🟡 |
| SA-15(5) | Attack surface reduction | G2 item 10 — surface change identified and justified | Design notes | ✅ |
| SA-17 | Developer security architecture and design | Architect role, ADRs, control allocation matrix | ADRs, allocation matrices | ✅ |
| SA-22 | Unsupported system components | EOL notices enter intake as scheduled chores | Dependency inventory | 🟡 |

## CM — Configuration Management

| Control | Requirement | Implementation | Evidence | Status |
|---|---|---|---|---|
| CM-2 | Baseline configuration | IaC in version control; one artifact promoted across environments | Git, artifact registry | ✅ |
| CM-3 | Configuration change control | G5 change records; PR + review + human authorization | Change records, approvals | ✅ |
| CM-3(2) | Test, validate, document changes | G3 + G4 before any G5 | Gate evidence | ✅ |
| CM-4 | Impact analyses | Change record item 4; AI impact at item 5 | Change records | ✅ |
| CM-4(1) | Separate test environments | Local / CI / staging / production separation | Environment config | ✅ |
| CM-5 | Access restrictions for change | Branch protection, CODEOWNERS, no admin bypass, signed commits | GitHub settings, git log | ✅ |
| CM-6 | Configuration settings | IaC scanning (checkov/tfsec), weekly drift detection | Scan reports, drift reports | ✅ |
| CM-7 | Least functionality | SA-8 review at G2; IaC scan; container minimization | Design notes, scans | 🟡 |
| CM-8 | System component inventory | SBOM per build, CycloneDX, diffed | SBOM artifacts | ✅ |
| CM-9 | Configuration management plan | `docs/07-release-and-change.md` | This repo | ✅ |
| CM-14 | Signed components | Cosign keyless signing; verify-on-deploy enforced | Signatures | ✅ |

## RA / SI — Risk Assessment & System Integrity

| Control | Requirement | Implementation | Evidence | Status |
|---|---|---|---|---|
| RA-3 | Risk assessment | Threat models at G2; risk tiering at intake | Threat models | ✅ |
| RA-5 | Vulnerability monitoring and scanning | SCA + container scan every PR; **daily rescan of deployed artifacts** | Scan history | ✅ |
| RA-5(2) | Update vulnerabilities to be scanned | Scanner feeds auto-updated | Tool config | ✅ |
| RA-7 | Risk response | Finding disposition: mitigate / transfer / accept / eliminate | Findings, POA&M | ✅ |
| SI-2 | Flaw remediation | Severity SLAs (7/30/90 days); POA&M tracking | Finding register | ✅ |
| SI-3 | Malicious code protection | Container scanning, dependency integrity verification | Scan reports | 🟡 |
| SI-4 | System monitoring | `docs/08-operate-and-respond.md` monitoring table | Alert config | 🟡 |
| SI-7 | Software/firmware/information integrity | Signed commits, signed artifacts, provenance, verify-on-deploy | Signatures, attestations | ✅ |
| SI-10 | Information input validation | Allocated at G2; negative-case tested at G4 | Tests, SAST | ✅ |
| SI-12 | Information management and retention | `docs/10-definitions.md` § Retention | Retention config | 🟡 |

## SR — Supply Chain Risk Management

| Control | Requirement | Implementation | Evidence | Status |
|---|---|---|---|---|
| SR-3 | Supply chain controls and processes | Dependency justification, SCA, lockfiles, pinned actions | PR bodies, lockfiles | ✅ |
| SR-4 | Provenance | SLSA-style build attestation; SBOM | Attestations | ✅ |
| SR-4(3) | Validate as genuine and not altered | Signature verification enforced at deploy | Verification logs | ✅ |
| SR-5 | Acquisition strategies, tools, methods | Dependency policy; **AIC-7 existence verification** | PR bodies | ✅ |
| SR-11 | Component authenticity | Cosign verification; package publisher verification | Signatures | ✅ |
| PM-30 | Supply chain risk management | Considered at intake; SBOM-driven exposure queries | Idea records, SBOMs | 🟡 |

## AC / IA — Access Control & Identification

| Control | Requirement | Implementation | Evidence | Status |
|---|---|---|---|---|
| AC-2 | Account management | Repo, registry, and environment access reviews | Access review records | 🟡 |
| AC-3 | Access enforcement | Allocated at G2; **integration-tested negative cases** at G4 | Tests | ✅ |
| AC-5 | **Separation of duties** | **Agent-enforced (ADR-0005):** the approver holds no implementing capability and the implementers hold no approval. Prompt, tool grant, CODEOWNERS, Environments. **Not a second person** | Approval records, agent defs, `ai-inventory.md` | 🟡 **POAM-017** |
| AC-6 | Least privilege | Workflow `permissions:` scoped per job; agent tool grants | Workflow files, agent defs | ✅ |
| IA-2 | Identification and authentication | GitHub identity; OIDC federation for cloud | Auth config | ✅ |
| IA-5 | Authenticator management | No secrets in source; secret scanning; OIDC, no long-lived keys | Scan reports | ✅ |

## AU — Audit and Accountability

| Control | Requirement | Implementation | Evidence | Status |
|---|---|---|---|---|
| AU-2 | Event logging | Audit events specified as story criteria; verified at G4 item 21 | Tests, log samples | ✅ |
| AU-3 | Content of audit records | Logging standards; no secrets or personal data in logs | Code review | 🟡 |
| AU-6 | Audit record review, analysis, reporting | Monitoring table; pipeline anomaly alerting | Alert config | 🟡 |
| AU-9 | Protection of audit information | Immutable CI logs; protected evidence store | Storage config | 🟡 |
| AU-11 | Audit record retention | `docs/10-definitions.md` § Retention | Retention config | ✅ |
| AU-12 | Audit record generation | CI/CD run records; git history; agent transcripts (AIC-10) | Run logs | ✅ |

## CA — Assessment, Authorization, Monitoring

| Control | Requirement | Implementation | Evidence | Status |
|---|---|---|---|---|
| CA-2 | Control assessments | Quarterly, `assessment-plan.md` | Assessment reports | ✅ |
| CA-5 | Plan of action and milestones | `poam.md`, maintained continuously | POA&M | ✅ |
| CA-7 | Continuous monitoring | Scheduled scans, drift detection, metrics, retro loop | Monitoring records | ✅ |
| CA-8 | Penetration testing | Quarterly + pre-major-release; AI red-team for AI features | Reports | 🟡 |

## CP / IR — Contingency & Incident Response

| Control | Requirement | Implementation | Evidence | Status |
|---|---|---|---|---|
| CP-9 | System backup | Automated, encrypted, **restore-tested on a schedule** | Restore test records | 🟡 |
| CP-10 | System recovery and reconstitution | Rollback rehearsed and verified at G5 item 13 | Rehearsal records | ✅ |
| IR-4 | Incident handling | `docs/08-operate-and-respond.md` | Incident records | ✅ |
| IR-5 | Incident monitoring | Incident register, postmortems | Records | ✅ |
| IR-6 | Incident reporting | Notification assessment in the security incident path | Records | 🟡 |
| IR-8 | Incident response plan | `docs/08-operate-and-respond.md` | This repo | ✅ |

## PL / PT / AT — Planning, Privacy, Awareness

| Control | Requirement | Implementation | Evidence | Status |
|---|---|---|---|---|
| PL-2 | System security and privacy plans | `ssp-outline.md` | SSP | 🟡 |
| PL-8 | Security and privacy architectures | Architect role; control allocation at G2 | ADRs, allocation matrices | ✅ |
| PT-2/PT-3 | Authority and purpose for processing PII | Privacy triage at G1; data governance in the AIA | Story flags, AIAs | 🟡 |
| PT-5 | Privacy notice | Transparency requirements at G4 item 32 | UI review | 🟡 |
| MP-6 | Media sanitization | Synthetic/de-identified data in non-production; disposal policy | Environment config | 🟡 |
| AT-2/AT-3 | Awareness and role-based training | Agent definitions encode role expectations; onboarding docs | `.claude/agents/`, docs | 🟡 |

---

## AI-specific controls

The AI control set (**AIC-1..12**, `docs/11-ai-agent-controls.md`) and AI feature governance
(`docs/12-ai-feature-governance.md`) extend this map. 800-53 Rev. 5 predates generative AI
and has no dedicated family, so AI risk is mapped onto existing controls plus the NIST AI RMF:

| AI concern | 800-53 anchor | AI RMF |
|---|---|---|
| Agent separation of duties | AC-5, CM-5 | GOVERN 2.1 |
| Agent least agency — approve/merge/push/prod | AC-6, CM-5 | MANAGE 2.3 |
| Agent least agency — **write scope by role** 🟡 | AC-6 | MANAGE 2.3 |
| Prompt injection | SI-10 | MEASURE 2.7 |
| Secret/data leakage to a model | IA-5, SC-28, MP-6 | MANAGE 2.2 |
| AI authorship provenance | SR-4, SI-7 | GOVERN 4.2 |
| Hallucinated dependencies | SR-3, SR-4, SR-11 | MANAGE 2.2 |
| Model/prompt change control | CM-3, CM-4, SA-10 | MANAGE 4.1 |
| AI evaluation and red-team | SA-11, CA-2, CA-8 | MEASURE 2 |
| AI incident response | IR-4, IR-6 | MANAGE 4.3 |
| AI system inventory | CM-8, PM-5 | GOVERN 1.6 |
| Agent action audit trail | AU-2, AU-3, AU-12 | GOVERN 1.5 |

🟡 **Agent write scope by role is prompt-enforced, not tool-enforced.** Claude Code grants
tool types rather than path scopes, and the hook payload carries no agent identity (verified
2026-08-07). Detected downstream by non-author review, CODEOWNERS, AI-authorship
declarations, and the monthly agent audit. Tracked as **POAM-001**. The high-consequence
boundaries — approve, merge, push, production, secrets — *are* enforced.

---

## How to use this map

**Do not read the Status column as a score.** A 🟡 that is honestly reasoned is worth more
than a ✅ nobody verified. The Compliance Officer's assessment discipline is: find the
implementation, find evidence it *operated*, and **read the evidence** — evidence that exists
but does not support the claim is the most common finding in a mature program, and it
survives precisely because nobody opens it.

**Partial and out-of-scope entries are features of this document, not gaps in it.** Every
🟡 should trace to a POA&M entry with an owner and a date. Every ➖ should say where the
control *is* satisfied, if it is.

**"We have a policy" satisfies nothing.** A policy is a claim about intent; assessment is
about operation.
