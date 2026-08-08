# 10 — Definitions

The shared vocabulary the gates depend on. Ambiguity here becomes argument at G4.

## Definition of Ready (DoR) — entry to development

A story is Ready when **all** hold. Enforced at G1 (`process/gates/g1-ready.md`).

- Traces to a G0-accepted idea with a problem statement
- User, value, and outcome stated
- INVEST satisfied (`03-refinement.md`)
- Acceptance criteria written in Given/When/Then, binary and observable
- Criteria cover happy path, at least one error path, at least one boundary
- Applicable non-functional criteria attached **with numbers**
- Security relevance triaged and flagged
- AI relevance triaged and flagged
- Dependencies identified and resolved (or the item is Blocked, not Ready)
- Estimated by the team
- Test approach agreed with QA
- No open question exists whose answer would change the design

## Definition of Done (DoD) — exit from development

Applies to every story. Enforced at G3 and G4.

**Code**
- Acceptance criteria implemented, each with a test that fails without the change
- Unit + integration tests written and passing; coverage threshold met, no coverage drop
- Negative-case tests exist for every security control the threat model allocated
- Lint, format, and static typing clean
- No new High/Critical SAST, SCA, IaC, or container findings
- No secrets in source or history
- New dependencies justified, license-checked, existence-verified (AIC-7)
- Reviewed and approved by an identity that is **not** the author
- AI authorship declared

**Verification**
- QA executed the test plan; traceability matrix complete (AC → test → result)
- Exploratory charter run and findings filed
- Non-functional criteria verified against their stated numbers
- Security control verification complete with evidence
- AI evals passed against baseline (if AI-relevant)
- Accessibility verified (if user-facing)

**Operability**
- Required logs, metrics, and traces emitted and confirmed
- Runbook updated if operational behavior changed
- Feature flag state defined; rollback path known
- Documentation updated (user-facing and internal)

**Governance**
- Issue linked; commits reference it; signed
- Threat model updated if the design changed during build
- Control evidence written to `evidence/<issue>/`
- ADR written or explicitly not needed

**"Done" means releasable.** Not "done except tests," not "done pending docs." Partial
completion is a state, and its name is In Progress.

## Definitions of Ready/Done for other item types

**Bug** — Ready: reproducible with steps, expected vs. actual, severity, affected versions,
scope of impact. Done: DoD **plus** a regression test that fails on the unfixed code, plus
a root-cause note. A bug fixed without a failing-first regression test will return.

**Spike** — Ready: the question, the time box, the decision it unblocks, the format of the
answer. Done: written answer, recommendation, follow-on stories created. **Spikes produce
documents, never production code.** Code written during a spike is thrown away; keeping it
is how prototypes become production systems nobody designed.

**Chore** — Ready: what and why now. Done: DoD minus user-facing criteria.

**Process change** — Ready: the friction described concretely, the proposed diff. Done:
merged PR, human-approved, communicated to the team.

## Severity

**Security findings**

| Severity | Definition | Remediate | Blocks release |
|---|---|---|---|
| Critical | Remote exploit, no auth required; RCE; data loss or mass exposure | 7 days | Yes |
| High | Exploitable with limited preconditions; privilege escalation; targeted exposure | 30 days | Yes |
| Medium | Requires unusual conditions or significant existing privilege | 90 days | No |
| Low | Defense-in-depth; minimal realistic impact | Next planned cycle | No |

Severity is set from **realistic exploitability in our context**, not from the CVSS base
score alone. Deviation from the vendor score is recorded with reasoning.

**Incidents** — SEV1 total outage or confirmed breach · SEV2 major degradation or suspected
compromise · SEV3 minor degradation with workaround · SEV4 negligible.

**Defects** — Blocker (no workaround, core journey) · Major (significant impairment) ·
Minor (cosmetic or edge case).

## Relevance flags

**Security-relevant** — touches authn, authz, sessions, cryptography, secrets, personal or
regulated data, file upload/parsing, external network calls, deserialization, template
rendering, subprocess execution, query construction, infrastructure or CI configuration, or
adds a dependency.

**AI-relevant** — adds/changes a model call, prompt, system instruction, generation
parameter, retrieval or grounding data, tool-calling capability, or autonomy boundary;
processes user data through a model; or surfaces model output into a user-affecting decision.

**Privacy-relevant** — collects, processes, stores, transmits, or deletes personal data, or
changes retention, access, or purpose of existing personal data.

Any flag set ⇒ **G2 mandatory** with the corresponding specialist as blocking co-approver.

## Work item states

```
Idea ──▶ Accepted ──▶ Ready ──▶ Designed ──▶ In Progress ──▶ In Review
                                                                 │
   Released ◀── Authorized ◀── Verified ◀── Code Complete ◀──────┘

Blocked      — cannot progress; has a named blocker and an owner
Parked       — accepted, deferred, has a review date
Rejected     — closed with a recorded reason
```

Backward moves are normal and are recorded with the specific reason. An item that moves
backward silently loses its audit trail.

## Environments

| Env | Purpose | Data | Access | Change path |
|---|---|---|---|---|
| Local | Development | Synthetic | Developer | Free |
| CI | Automated verification | Synthetic | Pipeline identity | Ephemeral |
| Staging | Pre-production verification | Synthetic or de-identified | Team, read-mostly | Automated from `main` |
| Production | Live service | Real | Pipeline identity + break-glass | **G5-authorized only** |

Production personal data never leaves production. De-identification is verified, not
assumed. (MP-6, AC-3, SC-28)

## Evidence & retention

**Evidence** is an artifact produced by performing a control, sufficient for an independent
party to confirm the control operated: workflow run records, SARIF, test results, coverage
reports, SBOMs, signatures and attestations, approval records, threat models, eval results,
assessment reports, change records. Prose asserting the work was done is **not** evidence.

| Record | Retention | Control |
|---|---|---|
| Audit logs (system) | 1 year online, 3 years archived | AU-11 |
| CI/CD run records | 3 years | AU-11, CM-3 |
| Change records | 3 years post-decommission | CM-3 |
| Gate evidence bundles | 3 years | CA-2, SA-11 |
| Security findings & POA&M | Until closed + 3 years | CA-5, RA-5 |
| Incident records & postmortems | 3 years | IR-5 |
| SBOMs & attestations | Artifact lifetime + 3 years | CM-8, SR-4 |
| AI evals, red-team, assessments | 3 years | AI RMF MEASURE |
| Agent session transcripts | 1 year | AU-11, AIC-10 |

Adjust to your actual regulatory obligation — these are defaults, and the wrong retention
period is itself a finding in both directions.

## Terms

**Gate** — checklist + independent approver + evidence artifact. All three, or it is not a
gate. **Control** — a safeguard implemented to satisfy a security or governance requirement.
**Finding** — a verified gap between required and actual. **POA&M** — Plan of Action and
Milestones; the register of open gaps with owners and dates (CA-5). **SSP** — System
Security Plan; how controls are implemented here (PL-2). **SBOM** — machine-readable
component inventory (CM-8). **Attestation** — signed statement about how an artifact was
produced (SR-4). **Eval** — a repeatable measurement of AI behavior against expected
results. **Guardrail** — a runtime control constraining AI input or output. **Red-team** —
adversarial human testing. **Drift** — behavior change without a corresponding code change.
