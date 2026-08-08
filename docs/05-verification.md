# 05 — Verification & Validation (→ G4)

**Owners:** QA Engineer, Security Engineer, AI Risk Officer
**Commands:** `/qa-gate`, `/security-gate`, `/ai-gate` · **Gate:** `process/gates/g4-verified.md`

Verification asks *did we build it right*. Validation asks *did we build the right thing*.
G4 requires both, and they are answered by different people than the one who built it.

> **The skills are authoritative for method** — `test-strategy`, `exploratory-testing`,
> `control-verification`, `scanner-triage`, `eval-design`, `red-teaming`. This page explains
> *why* the gate is shaped this way. If the two disagree, the skill wins and this page is the
> bug.

## Test strategy

```
        ╱╲          Manual exploratory — charter-driven, time-boxed, findings logged
       ╱  ╲         Not scripted regression. Humans find what scripts cannot imagine.
      ╱────╲
     ╱  E2E ╲       Few. Critical user journeys only. Slow, brittle, expensive —
    ╱────────╲      and irreplaceable for proving the whole thing hangs together.
   ╱Integration╲    Real collaborators: DB, queue, HTTP boundary, authz. This layer
  ╱────────────╲    catches what unit tests mock away, which is most real defects.
 ╱     Unit     ╲   Many, fast, deterministic. Pure logic, branches, boundaries.
╱────────────────╲
```

Inverted pyramids (E2E-heavy) produce slow, flaky suites nobody trusts and everyone
re-runs. Unit-only suites produce systems where every part passes and the whole fails.
Integration is the layer most teams under-invest in; weight it deliberately.

### What gets tested where

| Concern | Layer |
|---|---|
| Business logic, branches, boundaries | Unit |
| Authorization decisions | Integration — always. Unit-mocked authz proves nothing. |
| Persistence, transactions, migrations | Integration, against the real engine |
| Contract with an external service | Contract test + a recorded-fixture integration test |
| Critical journey end to end | E2E, one per journey, no more |
| Input validation | Property-based where the input space is large |
| Performance target from the NFR | Load test with the stated threshold as the assertion |
| Accessibility | Automated axe scan + manual keyboard/screen-reader pass |
| Security control from the threat model | Integration test asserting the **negative** case |

### The negative case rule

For every control, the test that matters is the one proving the control **denies**. A test
showing an authorized user can read their draft proves the feature works. A test showing an
unauthorized user *cannot* proves the control works. Only the second is security evidence
for SA-11.

## Traceability

QA maintains AC → test → result. This matrix is what makes G4 auditable and is generated
into `evidence/<issue>/g4/traceability.md`.

| AC | Test | Type | Result | Evidence |
|---|---|---|---|---|
| AC-1 draft offered on re-auth | `test_draft_offered_after_session_expiry` | Integration | ✅ | run #4821 |
| AC-2 decline discards permanently | `test_declined_draft_not_recoverable` | Integration | ✅ | run #4821 |
| AC-3 5 MB limit evicts oldest | `test_quota_eviction_order` | Unit | ✅ | run #4821 |
| NFR authz | `test_other_user_cannot_read_draft` | Integration (negative) | ✅ | run #4821 |
| NFR p95 < 200 ms | `load_draft_restore` | Performance | ⚠️ 240 ms | run #4823 |

An AC with no test is a G4 failure. A test with no AC is either dead weight or an
undocumented requirement — resolve which.

## Security verification (SA-11)

Automated scanning is a floor. The Security Engineer verifies, by hand and by test, that
the controls the threat model allocated are present and effective.

| Activity | When | Control |
|---|---|---|
| SAST (CodeQL + language linters) | Every PR | SA-11(1) |
| SCA / dependency vulnerabilities | Every PR + daily on `main` | RA-5, SR-3 |
| Secret scanning | Pre-commit + every PR + full history sweep | IA-5, SI-7 |
| IaC / configuration scanning | Every PR touching infra | CM-6, CM-7 |
| Container / image scanning | Every build | RA-5, SR-11 |
| DAST | Staging, per release | SA-11(8) |
| Manual control verification | Per security-relevant story | SA-11 |
| Threat model re-review | When the design changed during build | SA-11(2) |
| Penetration test | Quarterly + before major release | CA-8, SA-11(5) |
| SBOM generation + diff | Every build | CM-8, SR-4 |

**Triage discipline.** Scanner output is not findings. Every result is dispositioned:
*true positive* → finding with severity and SLA · *false positive* → suppressed **with a
written rationale and an expiry date**, reviewed quarterly · *accepted risk* → human
approval, POA&M entry, review date.

A suppression with no rationale is a control failure and is treated as one. Blanket
suppressions and `# nosec`-style comments without an issue link fail G4.

### Severity and remediation SLA

| Severity | Definition | Remediate within | Blocks release? |
|---|---|---|---|
| Critical | Remotely exploitable, no auth, data loss or RCE | 7 days | Yes, unconditionally |
| High | Exploitable with limited preconditions; privilege escalation | 30 days | Yes |
| Medium | Requires unusual conditions or significant privilege | 90 days | No — tracked |
| Low | Defense in depth, minimal impact | Next planned cycle | No |

Critical and High blocks are overridable **only** by documented, time-boxed, human-approved
risk acceptance with a POA&M entry (`docs/templates/security-exception.md`). Not by the
Product Owner, not by schedule pressure, not by "we'll fix it next sprint."

## AI verification

If the AI-relevant flag is set, `/ai-gate` runs and its pass is required for G4. It covers
eval suite results against baseline, red-team results, guardrail verification, and drift
checks. Full detail in `12-ai-feature-governance.md`.

## Exploratory testing

Time-boxed, charter-driven, and genuinely undirected inside the charter. Scripted tests
find what you thought of; exploration finds what you did not — which is where the
expensive defects live.

```
Charter:   Explore draft recovery across concurrent sessions
           to discover data-loss and cross-user-visibility defects
Time-box:  45 minutes
Notes:     Two tabs, same user, divergent edits → last-write-wins silently,
           no conflict surfaced. Filed #204.
           Session expiry during an in-flight autosave → draft saved under the
           expired session, invisible after re-auth. Filed #205 (High).
```

Findings become issues. The charter and notes are evidence for SA-11.

## Non-functional verification

Verified against the numbers stated at refinement, never against a vibe:

**Performance** — the NFR threshold is the test assertion, run under representative load
and data volume. Performance verified on an empty database is not verified.
**Reliability** — dependency failure, timeout, and partial-outage behavior exercised
deliberately (kill the DB mid-transaction and watch). **Recovery** — rollback tested, not
assumed (CP-10). **Observability** — the story's required log/metric/trace actually appears.
**Accessibility** — automated scan plus a real keyboard and screen-reader pass.

## G4 exit

QA, Security, and (if applicable) AI Risk each independently record pass or fail with
evidence links. All required approvals present ⇒ G4 cleared and the item is release-eligible.

Any fail returns the item to development with the specific criterion named. "Needs more
testing" is not a rejection reason; "AC-3 has no negative-case test and `test_quota_eviction`
asserts implementation detail, not behavior" is.

**Control mapping:** SA-11 (+ (1) static, (2) threat/vuln analysis, (5) pentest, (8)
dynamic), CA-2 (assessments), CA-7 (continuous monitoring), CA-8 (pentest), RA-5
(vulnerability scanning), SI-2 (flaw remediation), CM-4 (impact analysis), CM-8 (component
inventory via SBOM), AU-2 (audit event verification).
