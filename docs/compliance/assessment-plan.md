# Control Assessment Plan

**Owner:** Compliance Officer · **Controls:** CA-2, CA-7 · **Frequency:** quarterly, plus
event-driven

## Purpose

Determine whether controls are **implemented correctly, operating as intended, and producing
the intended outcome**. Those are three separate questions and most assessments only ask the
first.

## Method

Per SP 800-53A: **examine** (read artifacts) · **interview** (ask the responsible role) ·
**test** (exercise the control and observe).

**Test beats examine.** A control that examines well and fails when tested is the finding
that matters. Where a control can be tested, test it — for a pipeline gate, that means
attempting the thing the gate should block and confirming it blocks.

## Scope per quarter

Rotate so every control is assessed at least annually, with these assessed **every quarter**
because they carry the most weight or drift fastest:

- **AC-5 / CM-5 separation of duties** — sample merged PRs; confirm no author-approved PR
  reached `main`. Test it: attempt a self-approval and confirm branch protection refuses.
- **SA-11 developer testing** — sample G4 evidence bundles; confirm the negative-case tests
  exist and would actually fail if the control were removed.
- **CM-3 change control** — sample releases; confirm a human approval record exists with
  identity and timestamp.
- **RA-5 / SI-2 vulnerability management** — findings past SLA; POA&M currency.
- **SI-7 / SR-4 integrity** — confirm signature verification is **enforced** at deploy, not
  merely produced at build. Test it: attempt to deploy an unsigned artifact.
- **AIC-3 least agency** — confirm agent tool grants match `ai-inventory.md`.
- **AIC-6 provenance** — sample merged PRs; confirm AI authorship declarations are present.

## Sampling

Sample randomly, from the full population, using a documented selection method recorded in
`evidence/assessments/<quarter>/sample-selection.md`.

**Hand-picked samples tell you about what is easy to show.** A genuinely random sample of ten
tells you more about the real state than a curated review of fifty, and it is the difference
between an assessment and a demonstration.

## Recording

Per control: implementation status · assessment method used · **evidence examined, by
reference** · result (Satisfied / Other Than Satisfied) · findings.

Every Other-Than-Satisfied result becomes a **POA&M entry** with an owner and a date. No
exceptions.

## The three-step discipline

1. **Does the control exist?** A specific, documented implementation — not an intention.
2. **Did it operate?** Is there evidence it ran?
3. **Does the evidence support the claim?** **Read it.**

Step 3 is where mature programs fail. Evidence that exists but does not say what the claim
says it says is the most common finding, and it survives for years precisely because nobody
opens the file.

## Event-driven assessments

Trigger outside the quarterly cycle on: a SEV1/SEV2 incident · a significant architectural
change · a model or AI provider change · a change to the pipeline gates or agent definitions
that **relaxes** a control · a new regulatory obligation · a finding that suggests a control
has been ineffective for some time (assess the period, not just the instance).

## Reporting

To `evidence/assessments/<quarter>/assessment-report.md`. State clearly: what was assessed,
what was **sampled**, what was **not examined**, results, findings, and POA&M entries created.

**Report gaps as they are** — including gaps that embarrass the team, delay a release, or
originate in a decision leadership made. A compliance function that softens findings is worse
than none, because everything downstream relies on assurance that is not real.

Distinguish precisely between a control that is **absent**, one that is **present but
ineffective**, and one that is **effective but undocumented**. They have completely different
remediations, and collapsing them produces the wrong fix.
