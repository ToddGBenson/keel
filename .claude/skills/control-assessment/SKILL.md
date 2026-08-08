---
name: control-assessment
description: Assess whether a control is implemented, operating, and effective — and record the result so it survives an audit. Use when running a quarterly or event-driven control assessment, verifying a compliance claim, sampling evidence, deciding an implementation status, or writing an assessment report or POA&M entry.
---

# Control assessment

Consumers: `compliance-officer`, `docs/compliance/assessment-plan.md`,
`docs/compliance/poam.md`, `docs/compliance/ssp-outline.md`.

## Three questions, not one

Most assessments ask only the first and report a pass.

1. **Is the control implemented correctly?** A specific, documented implementation — not an
   intention, not a policy.
2. **Is it operating as intended?** Is there evidence it actually ran?
3. **Is it producing the intended outcome?** Does the evidence show it *worked*?

A control can be implemented, operating, and useless. A scanner that runs on every PR and
whose findings are never triaged satisfies (1) and (2) and fails (3).

## Method — examine, interview, test

Per SP 800-53A. **Test beats examine**, always, where testing is possible.

| Method | What it gives you | Weakness |
|---|---|---|
| **Examine** | Read the artifact, the config, the evidence | Shows what was written, not what happens |
| **Interview** | Ask the responsible role how it works | Shows what people believe happens |
| **Test** | Exercise the control and observe | Shows what actually happens |

**A control that examines well and fails when tested is the finding that matters**, and it is
common. For anything gate-shaped, testing means *attempting the thing the control should
block and confirming it blocks*:

- AC-5 → try to approve your own PR. Does GitHub refuse?
- CM-5 → try to push to `main`. Does it reject?
- SI-7 → try to deploy an unsigned artifact. Does the pipeline stop?
- SA-11 → take a control's negative test, stub the control, confirm the test goes red
- AIC-3 → ask an agent to merge a PR. Does the hook block?

Nine of these are pre-written in `SETUP.md` § Verification. Run them; record the results.

## Sampling

Sample **randomly from the full population**, with the selection method recorded in
`evidence/assessments/<quarter>/sample-selection.md`.

> **Hand-picked samples tell you about what is easy to show.**

A genuinely random sample of ten tells you more about the real state than a curated review of
fifty — and the difference between an assessment and a demonstration is precisely whether you
chose the items or the method did.

State the sample size and the population. "Reviewed 10 of 143 merged PRs, selected by
`shuf`" is assessable. "Reviewed a selection of PRs" is not.

## Reading evidence

For every claim, open the artifact.

**Step 3 — does the evidence support the claim? — is where mature programs fail.** Evidence
that exists but does not say what the claim says it says is the most common real finding, and
it survives for years precisely because nobody opens the file.

Things that look like evidence and are not:
- A workflow run that succeeded because the job was skipped
- A scan report from a scanner configured to scan nothing
- An approval by the author under a second account
- A test result from a test that cannot fail
- A threat model with threats listed and no dispositions
- An eval report with no model or prompt version recorded

## Recording

Per control:

| Field | Notes |
|---|---|
| Implementation status | Implemented / Partially / Planned / Alternative / **Not Applicable** |
| Control origination | System-specific, inherited, hybrid, provided by a service |
| Assessment method | Examine / interview / test — say which you used |
| **Evidence examined, by reference** | Not "reviewed evidence" — the actual links |
| Result | **Satisfied** / **Other Than Satisfied** |
| Findings | Specific |

**"Not Applicable" requires a written justification.** Unjustified N/A is the most common way
a control catalog gets hollowed out — one reasonable-sounding exclusion at a time, until the
baseline is a third of its original size and nobody remembers why.

## Three distinctions that change the remediation

Collapsing these produces the wrong fix:

- **Absent** — the control does not exist. Build it.
- **Present but ineffective** — it exists and does not work. Fix or replace it.
- **Effective but undocumented** — it works; the SSP does not describe it. Write it down.

Also distinguish **prompt-enforced from technically enforced** for anything AI-related. Per
the enforcement table in `docs/11-ai-agent-controls.md`, a control implemented only as
instruction to a model is **advisory**. Assess it as such and say so — see POAM-001 for the
worked example.

## POA&M

**Every Other-Than-Satisfied result becomes a POA&M entry.** No exceptions, including for
gaps found close to a release.

Then watch three signals:
1. **Entries past due** — report first, every time
2. **Entries extended more than once** — not a schedule problem; a resourcing or will
   problem, and naming it as one is your job
3. **Entries closed without evidence of remediation** — audit a sample of closures each
   quarter; this is where a register quietly stops being true

## Reporting

State: what was assessed · what was **sampled**, and how · what was **not examined** ·
results · findings · POA&M entries created.

**Report gaps as they are** — including gaps that embarrass the team, delay a release, or
originate in a decision leadership made. A compliance function that softens findings is worse
than none, because it manufactures documented assurance that everything downstream relies on
and that is not real.

## Event-driven triggers

Outside the quarterly cycle: a SEV1/SEV2 · significant architectural change · model or AI
provider change · **any change relaxing a pipeline gate or agent definition** · new
regulatory obligation · a finding suggesting a control has been ineffective for some time —
in which case **assess the period, not just the instance.**

## Controls

CA-2 (control assessments) · CA-5 (POA&M) · CA-7 (continuous monitoring) · PL-2 (SSP) ·
AU-9 (evidence integrity) · AI RMF MEASURE 2, GOVERN 1.5.
