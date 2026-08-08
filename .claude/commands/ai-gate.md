---
description: AI verification for G4 — eval suite against baseline, red-team status, guardrail verification, drift check
argument-hint: <issue or PR number>
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, WebSearch, Task
---

# G4 — AI Verification: `$ARGUMENTS`

Delegate to the `ai-risk-officer` agent. Per `docs/12-ai-feature-governance.md`.

## Applies when

The change is **AI-relevant** per `docs/10-definitions.md`: model call added or changed;
prompt, system instruction, or generation parameter changed; retrieval/grounding data
altered; tool-calling capability added or widened; autonomy boundary changed; user data
processed through a model; model output surfaced into a user-affecting decision.

**A prompt change is a code change.** Teams that treat prompts as configuration ship untested
behavior changes to production. This gate applies to prompt-only diffs.

## Preconditions

The **AI Impact Assessment from G2 exists** and its risk tier is recorded. If not, stop — you
cannot verify against requirements that were never established.

## Skills — load these first

- **`eval-design`** — the eight categories, grader selection, held-out discipline, baselines,
  and the noise floor you need before calling anything a regression.
- **`red-teaming`** — at High tier, or after an AI incident.
- **`evidence-writing`** — recording the result so it survives assessment.

## 1. Eval suite

Run it per the `eval-design` skill. Compare against baseline. Record **model version, prompt
version, eval-set version, and grader version** with the results.

**A regression against baseline blocks the merge**, exactly like a failing unit test —
provided it exceeds the measured noise floor.

If the eval set was tuned against during prompt development, say so. A prompt tuned against
its own eval set measures memorization, and the number is not evidence.

## 2. Guardrail verification

Each guardrail from the G2 design gets a test proving it **blocks**. A guardrail verified
only on the happy path is unverified.

Confirm specifically:
- Input validation and injection defense at every ingestion channel
- Output filtering and validation
- **Model output treated as untrusted input to every downstream system** — never evaled,
  exec'd, rendered unescaped, or passed to a privileged operation without validation. This
  is the SQL-injection lesson relearned and currently the most under-controlled AI risk in
  production.
- Tool-call authorization checked server-side against the **user's** rights, never against
  the model's request
- Rate and cost limits
- Fallback behavior when the model is unavailable or a guardrail trips

## 3. Red-team

Required at **High** tier, recommended at Limited. Per the `red-teaming` skill. Confirm it
ran, read the findings, and check they entered the normal finding backlog with standard SLAs.

A red-team that found nothing usually had too narrow a charter. Record that judgment rather
than reporting a clean bill of health.

## 4. Human oversight

Verify the oversight point exists as designed, and that the human is shown **enough to decide
well** — including uncertainty. An oversight point where the human sees only the output and
not its basis is oversight in name only, and it should be reported as a finding.

## 5. Transparency

Users told they are interacting with AI · limitations stated · generated content marked ·
a path to contest or escalate a consequential output.

## Output

```
G4 AI RESULT: PASS | FAIL
Tier: Limited        Model: <pinned version>     Prompt: v7      Eval set: v3

Evals vs. baseline:
  capability      0.91  (baseline 0.89)  ✅
  groundedness    0.87  (baseline 0.94)  ❌ REGRESSION — blocks merge
  injection res.  0.99  (baseline 0.99)  ✅
  over-refusal    0.04  (baseline 0.02)  ⚠️  doubled; investigate
Guardrails: 5/6 verified with blocking tests. Output-escaping guardrail has no
  negative test → unverified.
Red-team: last run 2026-07-12, 1 High open (AIF-009, in SLA)
Findings: HIGH — retrieved document content is passed to the renderer unescaped
```

## Then

Write to `evidence/<issue>/g4/ai/`. Update `docs/compliance/ai-inventory.md`. Escalate any
Critical or High to a human immediately.

Critical and High AI findings **block**, with the same authority as security findings.
