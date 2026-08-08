# Evidence Model

**Owner:** Compliance Officer · **Controls:** CA-2, CA-7, AU-9, AU-11, SA-11

## What counts as evidence

An artifact **produced by performing a control**, sufficient for an independent party to
confirm it operated.

| Is evidence | Is not evidence |
|---|---|
| A workflow run record with results | "CI passed" |
| A SARIF file | "We run SAST" |
| A test result with the assertion visible | "It's tested" |
| A signed attestation | "The build is trusted" |
| A GitHub approval record with identity and timestamp | "It was reviewed" |
| A threat model with dispositions | "We considered security" |
| An eval report with model and prompt versions | "Evals pass" |
| A rollback rehearsal record | "Rollback is supported" |

**Prose asserting the work was done is not evidence.** This is the distinction the whole
compliance posture rests on, and it is the one most often quietly abandoned under deadline.

## Structure

```
evidence/
  <issue-number>/
    g1/  dor-checklist.md
    g2/  design-note.md  threat-model.md  control-allocation.md  ai-impact-assessment.md
    g3/  review-record.md  ci-run.json  sast.sarif  sca-report.json
    g4/
      qa/       traceability.md  test-results.xml  exploratory-charter.md  nfr-results.md
      security/ control-verification.md  scan-triage.md  findings.md  dast-report.html
      ai/       eval-report.json  guardrail-verification.md  redteam-summary.md
  releases/
    <version>/  change-record.md  sbom.cdx.json  attestation.intoto.jsonl
                approval-record.md  deployment-record.md  post-release-verification.md
  incidents/
    <id>/       timeline.md  postmortem.md  actions.md
  retros/
    <id>/       retro.md  metrics.json
  ai-assurance/
    agent-evals/<date>/  results.json  regressions.md
    inventory-snapshots/
  assessments/
    <quarter>/  assessment-report.md  sample-selection.md  findings.md
```

## Per-gate evidence requirements

| Gate | Required artifacts | Controls |
|---|---|---|
| G0 | Idea record with problem, evidence, baseline, flags, RICE, decision | SA-3(1), RA-3 |
| G1 | DoR checklist with per-item disposition; estimate; test approach | SA-3, SA-4(3) |
| G2 | Design note, ADR (if warranted), threat model with dispositions, control allocation matrix, AIA (if AI-relevant) | SA-8, SA-11(2), SA-17 |
| G3 | Review record naming what was verified independently, CI run, SARIF, SCA, secrets scan, signed commits, AI declaration | SA-11(1), AC-5, CM-5 |
| G4 | Traceability matrix, test results, exploratory charter, NFR results, control verification with file:line, scan triage with dispositions, DAST, SBOM, eval report | SA-11, CA-2, RA-5 |
| G5 | Change record, SBOM diff, signature and provenance verification, rollback rehearsal, **human approval record**, deployment record, 24h metric check | CM-3, CM-4, SR-4, CP-10 |

## Evidence integrity (AU-9)

Evidence must be **tamper-evident, attributable, and retrievable**:

- **Git-resident where possible** — commit history is tamper-evident and attributable via
  signed commits.
- **CI-generated where possible** — a workflow run record cannot be hand-authored after the
  fact, which is exactly its value over a written claim.
- **Immutable storage** for artifacts, SBOMs, and attestations, addressed by digest.
- **Never hand-edit generated evidence.** If it is wrong, regenerate it and record why. A
  hand-edited scan report is a fabrication regardless of intent.
- **Retention** per `docs/10-definitions.md` § Retention.

## AI-specific evidence

Because agents produce most artifacts here, the evidence must answer a question a
human-only process does not raise: *what produced this, and who is answerable for it?*

Every gate evidence bundle records: **the agent** that produced the artifact · **the model
version** · **the human** who approved · the linked issue. Together with signed commits
carrying `AI-Assisted:` trailers and retained session transcripts, this satisfies AIC-10 and
AU-12.

An assessor's actual question is: *"Show me how this change came to be in production, and who
is answerable for it."* The evidence model exists to make that answerable in minutes.

## The assessment discipline

For any control claimed as implemented, verify three things in order:

1. **The control exists** — a documented, specific implementation, not an intention.
2. **The control operated** — there is evidence it ran.
3. **The evidence supports the claim** — **read it.**

Step 3 is where mature programs fail. Evidence that exists but does not say what the claim
says it says is the most common finding, and it survives for years precisely because nobody
opens the file.
