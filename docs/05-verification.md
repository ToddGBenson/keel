# 05 — Verification & Validation (→ G4)

**Owners:** QA, Security, AI Risk · **Commands:** `/qa-gate`, `/security-gate`, `/ai-gate`
**Gate:** `process/gates/g4-verified.md`

Verification asks *did we build it right*; validation asks *did we build the right thing*. G4
requires both, answered by someone other than the builder.

**Method lives in skills** — `test-strategy`, `exploratory-testing`, `control-verification`,
`scanner-triage`, `eval-design`, `red-teaming`. This page is *why* the gate is shaped this
way. Skill wins on any disagreement.

## The two rules that shape every verdict

**Layer deliberately.** Unit-only suites pass in every part and fail as a whole; E2E-heavy
suites are slow and flaky and get re-run until green. Integration is the under-invested layer
that catches what unit tests mock away — **authorization and persistence are tested there,
always** (`test-strategy`).

**The negative-case rule.** For every control, the test that matters proves it *denies*. A
test showing an authorized user succeeds proves the *feature*; only the test showing an
unauthorized user is refused proves the *control*, and only that is SA-11 evidence.

## Traceability

QA maintains AC → test → result → evidence, generated to `evidence/<issue>/g4/traceability.md`.
An AC with no test is a G4 failure. A test with no AC is dead weight or an undocumented
requirement — resolve which.

## Security verification (SA-11)

Scanning is the floor; the Security Engineer verifies by hand and by test that the allocated
controls are present and effective (`control-verification`, `scanner-triage`). When each scan
runs:

| Scan | When | Control |
|---|---|---|
| SAST (CodeQL + linters) | Every PR | SA-11(1) |
| SCA / dependency vulns | Every PR + daily on `main` | RA-5, SR-3 |
| Secret scan | Pre-commit + PR + full-history sweep | IA-5, SI-7 |
| IaC / config | Every PR touching infra | CM-6, CM-7 |
| Container image | Every build | RA-5, SR-11 |
| SBOM + diff | Every build | CM-8, SR-4 |
| DAST | Staging, per release | SA-11(8) |
| Pentest | Quarterly + pre-major-release | CA-8, SA-11(5) |

**Triage discipline.** Scanner output is not findings. Each result is dispositioned — true
positive → finding + SLA; false positive → suppressed **with a written rationale and expiry**;
accepted → human approval + POA&M. A suppression without a rationale is a control failure, and
blanket / bare `# nosec` suppressions fail G4.

**Severity SLAs and blocking authority** are canonical in `10-definitions.md` § Severity
(Critical 7d / High 30d / Medium 90d). Critical and High block release, overridable only by a
documented, time-boxed, human-approved risk acceptance (`templates/security-exception.md`) —
never by the Product Owner or schedule pressure.

## AI verification

If AI-relevant, `/ai-gate` is required for G4: eval results vs. baseline, red-team status,
guardrail verification, drift (`eval-design`, `red-teaming`; detail in
`12-ai-feature-governance.md`).

## Non-functional verification

Against the numbers stated at refinement, never a vibe: **performance** asserted under
representative load *and data volume* (an empty DB isn't verified); **reliability** exercised
by deliberate dependency failure (kill the DB mid-transaction); **recovery** by an actually-run
rollback (CP-10); **observability** by confirming the required log/metric/trace appears;
**accessibility** by automated scan *plus* a real keyboard/screen-reader pass.

## G4 exit

QA, Security, and (if applicable) AI Risk each record pass/fail independently with evidence.
All required approvals ⇒ release-eligible. Any fail returns the item with the **specific
criterion named** — "needs more testing" is not a rejection; "AC-3 has no negative-case test"
is.

**Control mapping:** SA-11(1)(2)(5)(8), CA-2, CA-7, CA-8, RA-5, SI-2, CM-4, CM-8, AU-2.
