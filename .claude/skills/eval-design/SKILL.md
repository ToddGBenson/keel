---
name: eval-design
description: Build and run an evaluation suite that gates AI behavior in CI the way tests gate code. Use when adding or changing an AI feature, prompt, or model; running the G4 AI gate; deciding what to measure about model behavior; constructing eval datasets; or setting baselines and regression thresholds.
---

# Eval design

Consumers: `ai-risk-officer`, `/ai-gate`, `process/gates/g4-verified.md`,
`.github/workflows/ai-evaluation.yml`, `docs/12-ai-feature-governance.md`.

## The premise

**A prompt change is a code change.** Teams that treat prompts as configuration ship untested
behavior changes to production — it is the single most common way AI features regress, and it
is invisible in a diff review because the diff looks like prose.

An eval suite is the test suite for behavior that is not deterministic. Without one, an AI
feature is unverifiable and cannot pass G4.

## Categories

Cover all eight. A suite that only measures capability tells you the feature works and
nothing about whether it is safe.

| Category | Question | Typical grader |
|---|---|---|
| **Capability** | Does it do the task on a representative set? | Exact match, F1, or rubric |
| **Groundedness** | Are claims supported by the retrieved source, or confabulated? | Citation check + LLM judge |
| **Robustness** | Does it hold under paraphrase, typos, odd formatting, adversarial framing? | Same grader, perturbed inputs |
| **Safety** | Refuses what it should — **and does not over-refuse** benign requests | Classifier + human spot-check |
| **Bias / fairness** | Does quality vary across demographic slices? | Same grader, sliced |
| **Injection resistance** | Does it follow instructions embedded in retrieved or user content? | Did the injected instruction execute? |
| **Disclosure** | Does it leak system prompt, other users' data, internals? | Substring + LLM judge |
| **Cost / latency** | Within the NFR budget under representative load? | Measured |

**Over-refusal is a real failure.** A model that refuses everything scores perfectly on
safety and is useless. Measure both directions and report both; a rising refusal rate on
benign requests is a regression, not a safety improvement.

## Building the dataset

**Representative, not convenient.** Sample from actual usage where you have it. Hand-written
examples drift toward what the author imagined, which is the happy path.

Composition that works:
- **~60% typical cases** — the distribution you actually serve
- **~25% edge cases** — boundaries, ambiguity, unusual formatting, minority slices
- **~15% adversarial** — injection attempts, jailbreaks, elicitation

**Every AI incident becomes an eval case.** This is how the suite earns its keep. A
production failure that does not enter the suite will recur, and the second occurrence is
harder to explain than the first.

Size: start at 50–100 per category. Large enough to be stable, small enough to run per-PR.
Grow it from incidents and red-team findings, not from padding.

## Held-out discipline

**A prompt tuned against its own eval set measures memorization, not capability**, and the
resulting number is not evidence.

- Keep a held-out split the prompt author does not see.
- `ai-evaluation.yml` asserts the eval set was not modified in the same PR as the prompt. If
  both genuinely must change, say so explicitly in the PR and have the AI Risk Officer
  confirm the split is still honest.
- Rotate a portion of the set periodically. A set that never changes becomes a set the prompt
  has been fitted to over months, one small tweak at a time.

## Graders

Pick the cheapest grader that actually discriminates:

1. **Deterministic** — exact match, regex, schema validation, "did the tool call fire with
   these arguments". Fast, free, unambiguous. Use wherever the task allows.
2. **Programmatic heuristic** — citation present and resolvable, output parses, length bounds.
3. **LLM judge** — for open-ended quality. Requires its own validation: **check judge/human
   agreement on a sample before trusting it**, and re-check when the judge model changes. An
   unvalidated judge is a random number generator with good manners.
4. **Human** — for the consequential slice, and for calibrating everything above.

Grade with a rubric, not a vibe. "Rate 1–5" without anchors produces noise; define what 3
means.

## Baselines and thresholds

Record with **every** run: **model version · prompt version · eval-set version · grader
version**. Without those four, a result is not comparable to anything and cannot be evidence
(AIC-8).

- **Baseline** = the current production configuration's scores.
- **Gate on regression against baseline**, not on an absolute score. Absolute thresholds are
  arbitrary; a drop is a fact.
- Set a **noise floor** first: run the same configuration three times and observe the spread.
  A "regression" inside that spread is sampling, not a change. Without this you will chase
  ghosts and then start ignoring the gate.
- Improvements are worth reviewing too — an unexplained jump usually means the eval broke,
  not that the model got better.

## In CI

`ai-evaluation.yml` triggers on prompt, eval, guardrail, and model-config paths, and on a
schedule.

**A regression blocks the merge, exactly like a failing unit test.** Not a warning, not a
comment — a failure.

The scheduled run against production is the control that catches the failure mode unique to
hosted models: **the provider updates the model, behavior changes, and there is no diff on
your side to notice.** Nothing else will catch that.

## Reporting

```
Model: <pinned id>   Prompt: v7   Eval set: v3   Grader: v2

capability       0.91  (baseline 0.89)  ✅
groundedness     0.87  (baseline 0.94)  ❌ REGRESSION — blocks merge
injection res.   0.99  (baseline 0.99)  ✅
over-refusal     0.04  (baseline 0.02)  ⚠️  doubled; below threshold but trending wrong
Noise floor: ±0.02 (3 runs, same config)
```

Report the noise floor alongside the numbers. A reader cannot judge a 0.02 delta without it.

## What evals do not cover

Say so explicitly. Evals measure sampled behavior against expected results. They do not find
what nobody thought to test — that is **red-teaming** (see the `red-teaming` skill), and the
two are not substitutes.

## Controls

AI RMF MEASURE 2.1–2.9 · MANAGE 4.1 · 800-53 SA-11, CA-2, CA-7 · AIC-8, AIC-12.
