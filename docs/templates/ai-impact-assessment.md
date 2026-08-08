# AI Impact Assessment — <feature> #<n>

**Author:** ai-risk-officer · **Reviewers:** security-engineer, architect
**Date:** <YYYY-MM-DD> · **Gate:** G2 (blocking)
**Frameworks:** NIST AI RMF MAP 1–5 · AI 600-1 · ISO/IEC 42001 6.1 · 800-53 RA-3, SA-8, PT-*

---

## 0. The question to answer first

**What is the non-AI alternative, and why is it insufficient?**

If a deterministic solution works, it is usually the better engineering answer. AI is a
capability with a permanent assurance cost — evals, red-teaming, drift monitoring, incident
handling — that is paid every quarter for as long as the feature exists. Justify paying it.

## 1. Purpose and context (MAP 1)

What decision or task does the AI perform? For whom? In what setting? What does the user
believe is happening?

**Deployment context.** Where in the product, at what frequency, with what latency and cost
budget.

## 2. Affected people (MAP 1.1, 3.3)

Who is affected — **including people who are not the user** (data subjects, people described
in content, people affected by a decision).

**Worst realistic outcome** for each group. Be concrete. "Bias risk" is not an assessment;
"output quality degrades for names outside the training distribution's dominant locale, and
this feature gates account recovery" is.

## 3. Risk tier

| Tier | Criteria |
|---|---|
| Minimal | Internal, no personal data, non-consequential output |
| Limited | User-facing, advisory output, human acts on it |
| High | Affects rights, access, safety, finances, employment, health, or legal standing; or processes sensitive personal data |
| Prohibited | Deception at scale, covert manipulation, unlawful discrimination, safety-critical without human control |

**Assigned tier:** ______ · **Reasoning:** ______

If **Prohibited** — escalate to a human decision-maker. Do not negotiate the tier down.

## 4. Data governance (MAP 2)

| Question | Answer |
|---|---|
| What data reaches the model? | |
| Personal data involved? Lawful basis? | |
| Does user data leave our boundary? To whom, under what terms? | |
| **Is it used for training?** (must be no for anything non-public) | |
| Grounding / retrieval sources and their provenance | |
| Training or tuning data provenance and license (if we tune) | |
| Retention and deletion | |
| Data quality and representativeness for the population served | |

## 5. Failure modes (MAP 5)

| # | Failure mode | How it manifests here | Impact | Disposition | Control |
|---|---|---|---|---|---|
| F1 | Confabulation | | | mitigate/accept/eliminate | |
| F2 | Harmful or biased output | | | | |
| F3 | Prompt injection (direct and indirect) | | | | |
| F4 | Sensitive information disclosure | | | | |
| F5 | Insecure output handling | | | | |
| F6 | Overreliance / automation bias | | | | |
| F7 | Denial of wallet / cost exhaustion | | | | |
| F8 | *Feature-specific* | | | | |

Same rule as any threat model: **an undispositioned failure mode fails G2.**

## 6. Guardrails

| Guardrail | Where | Verified by (test proving it **blocks**) |
|---|---|---|
| Input validation / injection defense | | |
| Output filtering and validation | | |
| **Output treated as untrusted input downstream** | | |
| Tool-call authz against the **user's** rights, server-side | | |
| Rate and cost limits | | |
| Fallback when model unavailable or guardrail trips | | |

**The output-handling rule:** model output is untrusted input to every downstream system.
Never eval, exec, render unescaped, or pass to a privileged operation without validation.
This is the SQL-injection lesson relearned, and it is currently the most under-controlled AI
risk in production systems.

## 7. Human oversight

**Where is the human?** In the loop (approves each output) · on the loop (monitors, can
intervene) · absent (justify against the tier).

**What is the human shown in order to decide well?** Including uncertainty, and the basis for
the output — not just the output. An oversight point where the human sees only the answer is
oversight in name only, and it should be recorded as a finding rather than a design.

**What can they actually do?** Override, escalate, reject, correct.

## 8. Transparency (GOVERN 4.2, MAP 5.2)

- [ ] Users are told they are interacting with AI
- [ ] Limitations are stated where the user will see them
- [ ] Generated content is marked
- [ ] There is a path to contest or escalate a consequential output

## 9. Evaluation plan (→ G4)

Eval categories to be built, the baseline, and the pass threshold. Held-out set strategy —
a prompt tuned against its own eval set measures memorization, not capability.

Red-team scope and charter (required at High tier).

## 10. Monitoring plan (→ MANAGE)

Guardrail trigger rate · refusal rate **in both directions** · groundedness sampling · user
contest rate · cost and latency · **scheduled eval re-runs against production** to catch
provider-side model updates that change behavior with no diff on our side.

## 11. Decision

**Recommendation:** proceed / proceed with conditions / do not proceed
**Conditions:**
**Residual risk accepted by:** <human> **on** <date> **review by** <date>
