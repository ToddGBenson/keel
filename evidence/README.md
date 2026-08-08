# Evidence

Gate evidence, indexed by work item. This directory is the audit trail — the thing an
assessor asks for when they say *"show me how this change came to be in production, and who
is answerable for it."*

Governed by `docs/compliance/evidence-model.md`. Method: the `evidence-writing` skill.

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
  releases/<version>/    change-record.md  sbom.cdx.json  attestation.intoto.jsonl
                         approval-record.md  deployment-record.md
  incidents/<id>/        timeline.md  postmortem.md  actions.md
  retros/<id>/           retro.md  metrics.json
  assessments/<quarter>/ assessment-report.md  sample-selection.md  findings.md
  ai-assurance/          agent-evals/<date>/  inventory-snapshots/
```

## What is committed and what is not

**Committed** — the narrative records (`.md`). Verification records, threat models, charters,
change records, postmortems, assessments. These are authored by a role during a gate and are
part of the audit trail.

**Not committed** (see `.gitignore`) — raw generated output: SARIF, JUnit XML, most JSON scan
reports. These live in the CI artifact store with their retention policy. Committing them
bloats the repo and, worse, creates a second copy that can drift from the authoritative one.

Exceptions kept in-tree because they are small and frequently referenced: `eval-report.json`,
`metrics.json`, `sbom.cdx.json`.

## Rules

**Never hand-edit generated evidence.** If a scan report or test result is wrong, regenerate
it and record why. A hand-edited SARIF is a fabrication regardless of intent —
`.claude/hooks/guard-write.sh` blocks it, and `.gitignore` keeps it out of the tree.

**Prose asserting the work was done is not evidence.** A workflow run URL, a SARIF file, a
signed attestation, a GitHub approval record with identity and timestamp — those are
evidence. "CI passed" is not.

**Every record names its producer.** Agent, model version, human approver, linked issue. That
is what makes the chain reconstructable (AIC-10, AU-12).

**Three sections in every verification record:** what I verified · what I could not verify ·
what I did not examine. The second and third are what make the first credible.

## Retention

Per `docs/10-definitions.md` § Retention. Gate bundles 3 years · findings until closed + 3
years · incident records 3 years · assessments 3 years · agent transcripts 1 year.

## Controls

CA-2 · CA-7 · AU-9 (protection of audit information) · AU-11 (retention) · AU-12 · SA-11.
