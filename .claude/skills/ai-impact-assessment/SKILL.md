---
name: ai-impact-assessment
description: Assess an AI feature before it is built — purpose, affected people, risk tier, data governance, failure modes, guardrails, human oversight, transparency. Use at G2 for any AI-relevant change, when deciding whether to add AI to a product, when assigning an AI risk tier, or when asked whether an AI feature is safe to build.
---

# AI impact assessment

Consumers: `ai-risk-officer`, `/design`, `process/gates/g2-design.md`,
`docs/templates/ai-impact-assessment.md`. **Blocking co-approval at G2.**

## Ask this before anything else

> **What is the non-AI alternative, and why is it insufficient?**

If a deterministic solution works, it is usually the better engineering answer. AI carries a
**permanent assurance cost** — eval suites, red-teaming, drift monitoring, incident handling,
inventory upkeep — paid every quarter for as long as the feature exists.

Most "AI feature" requests are a search problem, a rules engine, a better form, or a
templating job wearing a fashionable hat. Establishing that this one is not takes ten minutes
and occasionally saves a year.

## 1. Purpose and context (MAP 1)

What decision or task does the AI perform? For whom? In what setting? **What does the user
believe is happening?** — the gap between what the system does and what the user thinks it
does is where most harm originates.

Deployment context: where in the product, at what frequency, with what latency and cost budget.

## 2. Affected people (MAP 1.1, 3.3)

Who is affected — **including people who are not the user.** Data subjects. People described
in content the model generates. People on the receiving end of a decision.

This is the section that gets written generically and should not be. State the **worst
realistic outcome** for each group, concretely:

```
✗ "Potential bias risk in outputs."
✓ "Output quality degrades for names outside the training distribution's dominant
   locale. This feature gates account recovery, so the failure mode is: users with
   non-Western names are disproportionately locked out of their own accounts and
   routed to a support queue with a 3-day SLA."
```

The second is assessable. The first is a sentence that has appeared in ten thousand
documents and changed nothing.

## 3. Risk tier

| Tier | Criteria | Requirements |
|---|---|---|
| **Minimal** | Internal, no personal data, non-consequential output | Basic evals, standard gates |
| **Limited** | User-facing, advisory, a human acts on it | Evals + guardrails + user disclosure |
| **High** | Affects rights, access, safety, finances, employment, health, or legal standing; or processes sensitive personal data | Full assessment + red-team + bias testing + human-in-the-loop + monitoring |
| **Prohibited** | Deception at scale, covert manipulation, unlawful discrimination, safety-critical without human control | **Not built.** Escalate to a human decision-maker |

**Do not negotiate a tier down** because the requirements are inconvenient. If a feature is
High, the honest options are to build it properly, redesign it so it is not High, or not
build it. Tier inflation downward is the most consequential failure available in this
assessment.

## 4. Data governance (MAP 2)

| Question | Why it matters |
|---|---|
| What data reaches the model? | Scope of exposure |
| Personal data? Lawful basis? | PT-2, PT-3 |
| Does data leave our boundary, to whom, under what terms? | Contractual and regulatory |
| **Is it used for training?** | Must be **no** for anything non-public. Verify the contract, not the marketing page |
| Grounding / retrieval sources and provenance | Poisoning surface, license |
| Retention and deletion | SI-12, MP-6 |
| Data quality and representativeness for the population served | Where bias originates |

The retrieval corpus is the part most often skipped. **Everything in it is attacker-reachable
context** if any of it is user-supplied.

## 5. Failure modes (MAP 5)

Enumerate, then disposition each — same four options as any threat model: **mitigate /
transfer / accept / eliminate**. An undispositioned failure mode fails G2.

Confabulation · harmful or biased output · **prompt injection, direct and indirect** ·
sensitive information disclosure · **insecure output handling** · overreliance and automation
bias · denial of wallet · plus the ones specific to *this* feature.

For each, state how it manifests **here**, not in general.

## 6. Guardrails

Each one needs a location and a test that proves it **blocks**:

- Input validation and injection defense **at every ingestion channel**
- Output filtering and validation
- **Model output treated as untrusted input to every downstream system** — never evaled,
  exec'd, rendered unescaped, or passed to a privileged operation unvalidated
- Tool-call authorization checked **server-side against the user's rights**, never against
  the model's request
- Rate and cost limits
- Fallback when the model is unavailable or a guardrail trips

## 7. Human oversight

**Where is the human?** In the loop (approves each output) · on the loop (monitors, can
intervene) · absent (justify against the tier).

**What is the human shown in order to decide well?** Including uncertainty, and the *basis*
for the output — not just the output.

> An oversight point where the human sees only the answer and not its basis is oversight in
> name only. Record it as a finding, not as a design.

**What can they actually do?** Override, escalate, reject, correct. An oversight point with
no available action is a notification.

Then the harder question: **will they actually do it?** A human asked to approve 200 outputs
an hour is a rubber stamp with a job title. Design the throughput, not just the checkpoint.

## 8. Transparency (GOVERN 4.2, MAP 5.2)

Users told they are interacting with AI · limitations stated where they will be seen ·
generated content marked · a path to contest or escalate a consequential output.

## 9. Decision

Proceed / proceed with conditions / do not proceed. Conditions must be verifiable at G4.
Residual risk accepted by a **named human**, with a review date.

## Then

Feed the eval plan (`eval-design`) and, at High tier, the red-team charter (`red-teaming`).
The AIA is what G4 verifies against — if a requirement is not written here, G4 cannot check it.

Register the system in `docs/compliance/ai-inventory.md`.

## Controls

AI RMF MAP 1–5, GOVERN 4.2 · AI 600-1 · ISO 42001 6.1, A.5 · 800-53 RA-3, SA-8, PT-2, PT-3,
PT-5, SI-12, MP-6.
