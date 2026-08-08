# Model Card — <system / feature name>

**Owner:** ai-risk-officer · **Risk tier:** Minimal / Limited / High
**Last updated:** <YYYY-MM-DD> · **Inventory entry:** `docs/compliance/ai-inventory.md`
**Frameworks:** AI RMF GOVERN 4.2, MAP 3.4 · ISO/IEC 42001 A.8 · 800-53 CM-8, PT-5

> Documents an AI system as **deployed here**, not the model in the abstract. A vendor's
> model card describes the model; this describes what we do with it, which is the part that
> determines the risk.

## Overview

| | |
|---|---|
| **Purpose** | What decision or task it performs |
| **Users** | Who interacts with it |
| **Affected people** | **Including those who are not users** — data subjects, people described in output, people affected by a decision |
| **Risk tier** | With one-line reasoning |
| **Non-AI alternative** | What it is, and why it was insufficient |

## Configuration

| | |
|---|---|
| Model + version | Pinned. Recorded in gate evidence per AIC-8 |
| Provider | |
| Prompt version | Version-controlled — **a prompt change is a code change** |
| Generation parameters | Temperature, max tokens, stop sequences |
| Tools available to the model | Each with its authorization boundary |
| Retrieval / grounding sources | And their version |
| Fallback | Behaviour when unavailable or a guardrail trips |

## Data

| Question | Answer |
|---|---|
| What reaches the model | |
| Personal data? Lawful basis? | |
| Leaves our boundary? To whom, under what terms? | |
| **Used for training?** | Must be **no** for anything non-public. Cite the contract clause, not the marketing page |
| Retention and deletion | |
| Representativeness for the population served | Where bias originates |

## Intended use

**Designed for:** the tasks and contexts it was built and evaluated for.

**Not designed for:** the uses it will fail at. Be specific — this section is what stops
someone extending the feature into a context it was never assessed in, which is the most
common way an AI system drifts out of its risk tier without anyone noticing.

## Performance

From the eval suite (`eval-design` skill). Include the **noise floor** — a reader cannot
judge a delta without it.

| Category | Score | Baseline | Notes |
|---|---|---|---|
| Capability | | | |
| Groundedness | | | |
| Robustness | | | |
| Safety (refusal correctness) | | | |
| **Over-refusal** | | | A rising rate is a regression, not a safety improvement |
| Bias / fairness across slices | | | Report per slice, not aggregated |
| Injection resistance | | | |
| Disclosure | | | |
| Cost / latency | | | |

**Eval set version:** ___ · **Grader:** ___ · **Noise floor:** ±___ over ___ runs

## Known limitations and failure modes

What it gets wrong, and under what conditions. Written plainly enough that someone deciding
whether to rely on it can actually decide.

## Guardrails

| Guardrail | Where | Test proving it **blocks** |
|---|---|---|
| Input validation / injection defense | | |
| Output filtering | | |
| **Output treated as untrusted input downstream** | | |
| Tool-call authz against the **user's** rights | | |
| Rate / cost limits | | |

## Human oversight

**Position:** in the loop / on the loop / absent — with justification against the tier.
**What the human is shown:** including uncertainty and the *basis* for the output.
**What they can do:** override, escalate, reject, correct.
**Throughput:** how many decisions per hour. A human asked to approve 200 outputs an hour is
a rubber stamp with a job title — state the real number.

## Transparency

- [ ] Users are told they are interacting with AI
- [ ] Limitations stated where users will see them
- [ ] Generated content marked
- [ ] A path exists to contest or escalate a consequential output

## Red-team

**Last run:** <date> · **Charter scope:** ___ · **Open findings:** ___
Required at High tier. A run that found nothing usually had too narrow a charter.

## Monitoring

Guardrail trigger rate · refusal rate **both directions** · groundedness sampling · user
contest rate · cost and latency · **scheduled eval re-runs against production** (catches
provider-side model updates that change behaviour with no diff on our side).

## Change history

| Date | Change | Model | Prompt | Approved by |
|---|---|---|---|---|

Model, prompt, and grounding changes are **Normal changes** under CM-3: impact assessed,
evals re-run, human-approved, recorded.
