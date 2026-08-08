---
name: evidence-writing
description: Produce, place, and verify gate evidence that would satisfy an independent assessor. Use whenever recording the result of a gate (G0-G5), writing a verification or assessment record, claiming a control is satisfied, or asked what proves something was done. Also use when reviewing whether existing evidence actually supports the claim it is attached to.
---

# Evidence writing

The discipline behind every gate. Consumers: all gate roles, `/security-gate`, `/qa-gate`,
`/ai-gate`, `/release`, `compliance-officer`, `docs/compliance/evidence-model.md`.

## The distinction everything rests on

**Evidence is an artifact produced by performing a control**, sufficient for an independent
party to confirm it operated.

| Evidence | Not evidence |
|---|---|
| A workflow run record with results | "CI passed" |
| A SARIF file | "We run SAST" |
| A test result with the assertion visible | "It's tested" |
| A signed attestation | "The build is trusted" |
| A GitHub approval with identity and timestamp | "It was reviewed" |
| A threat model with dispositions | "We considered security" |
| An eval report naming model and prompt versions | "Evals pass" |
| A rollback rehearsal record | "Rollback is supported" |

**Prose asserting the work was done is not evidence.** This is the line that gets quietly
abandoned under deadline, and abandoning it is what turns a compliance posture into
paperwork.

## Three rules

**1. Point at an artifact or say the item is unsatisfied.** There is no third option. If you
cannot link something, write "unsatisfied — no evidence produced" and stop. That sentence is
worth more than a paragraph implying the work happened.

**2. Never write evidence you did not produce.** Do not describe a scan you did not run, a
test you did not execute, or a control you did not verify. A false compliance claim is worse
than an open finding — the finding is tracked and will be fixed; the claim is a hole nobody
knows exists.

**3. Say "unverified", never "passed", for anything you could not check.** And **report what
you did not examine.** Overstated coverage is how real gaps survive assessment cycles.

## Where it goes

```
evidence/<issue>/
  g1/  dor-checklist.md
  g2/  design-note.md  threat-model.md  control-allocation.md  ai-impact-assessment.md
  g3/  review-record.md  ci-run.json  sast.sarif  sca-report.json
  g4/
    qa/       traceability.md  test-results.xml  exploratory-charter.md  nfr-results.md
    security/ control-verification.md  scan-triage.md  findings.md  dast-report.html
    ai/       eval-report.json  guardrail-verification.md  redteam-summary.md
evidence/releases/<version>/   change-record.md  sbom.cdx.json  attestation.intoto.jsonl
                               approval-record.md  deployment-record.md
evidence/incidents/<id>/       timeline.md  postmortem.md  actions.md
evidence/retros/<id>/          retro.md  metrics.json
evidence/assessments/<quarter>/ assessment-report.md  sample-selection.md  findings.md
```

## Integrity (AU-9)

- **Prefer git-resident** — commit history is tamper-evident and attributable via signed commits.
- **Prefer CI-generated** — a workflow run record cannot be hand-authored after the fact,
  which is precisely its value over a written claim.
- **Never hand-edit generated evidence.** If a scan report or test result is wrong,
  regenerate it and record why. A hand-edited SARIF is a fabrication regardless of intent,
  and `guard-write.sh` blocks it.
- Narrative artifacts (`.md` verification records, charters, assessments) you author
  yourself — those are legitimate.

## What every gate record must carry

Because agents produce most artifacts here, the record must answer a question a human-only
process never raises: *what produced this, and who is answerable?*

```markdown
# G4 Security Verification — #142

Produced by:   security-engineer agent
Model version: <pinned model id>
Date:          2026-08-07
Approved by:   <human> on <date>
Issue:         #142
```

That, plus signed commits carrying `AI-Assisted:` trailers and retained transcripts,
satisfies AIC-10 and AU-12. An assessor's real question is *"show me how this change came to
be in production, and who is answerable for it"* — this makes it answerable in minutes.

## Writing a verification record

Structure that survives scrutiny:

```markdown
## What I verified
AC-3 object authorization → DraftAuthorizer.java:47
  Negative test: api_test.py:212 (asserts 403 for a non-owner)
  Confirmed the test fails when the ownership check is stubbed out. ✅

## What I could not verify
Performance NFR — no load environment available. UNVERIFIED, not passed.

## What I did not examine
Runtime behaviour under concurrent load. Deferred to /qa-gate.

## Findings
HIGH — drafts.py:88, quota check is non-transactional; two concurrent
autosaves both pass. Reproduce: parallel POST at quota-1.
```

Three sections, always: verified · could not verify · did not examine. The second and third
are what make the first credible.

## Reading evidence (the assessment discipline)

When checking someone else's claim, verify three things in order:

1. **Does the control exist?** A specific, documented implementation — not an intention.
2. **Did it operate?** Is there evidence it ran?
3. **Does the evidence support the claim?** ***Read it.***

**Step 3 is where mature programs fail.** Evidence that exists but does not say what the
claim says it says is the most common finding in a real assessment, and it survives for years
precisely because nobody opens the file. Open the file.

## Retention

Per `docs/10-definitions.md` § Retention. Gate bundles 3 years · findings until closed + 3
years · audit logs 1 year online / 3 archived · agent transcripts 1 year.

## Controls

CA-2 · CA-7 · AU-9 · AU-11 · AU-12 · SA-11 · AIC-10.
