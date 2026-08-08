# 12 — Governance of AI Features We Ship

**Owner:** AI Risk Officer · **Command:** `/ai-gate` · **Gates:** G2 (mandatory), G4 (mandatory)
**Scope:** AI capability inside the products this platform builds. For controls on the
agents doing the building, see `11-ai-agent-controls.md`.

**Anchors:** NIST AI RMF 1.0 · NIST AI 600-1 Generative AI Profile · ISO/IEC 42001 ·
OWASP LLM Top 10 · NIST SP 800-53 Rev. 5.

---

## When this applies

The AI-relevant flag is set at refinement (`03-refinement.md`) if the change:

- Adds or modifies a model call, or changes model, version, or provider
- Changes a prompt, system instruction, or generation parameter
- Alters retrieval/grounding data or an embedding pipeline
- Adds or widens tool/function-calling capability
- Changes an autonomy boundary or a human-in-the-loop point
- Sends user data to a model, or exposes model output to a user
- Puts model output into a decision that affects a person

**A prompt change is a code change.** Teams that treat prompts as configuration ship
untested behavior changes to production, and it is the single most common way AI features
regress. Prompts are versioned, reviewed, and eval-gated like source.

## The AI RMF loop, mapped to our gates

```
GOVERN   ── standing ──▶ policies, roles, inventory, this document
   │
MAP      ── G0/G1  ──▶  context, purpose, affected people, what could go wrong
   │
MEASURE  ── G2/G4  ──▶  evals, red-team, bias/robustness testing, guardrail verification
   │
MANAGE   ── G4/G5  ──▶  risk disposition, monitoring, incident response, decommission
   │                                                                        │
   └────────────────────── improvement loop (/retro, /learn) ◀──────────────┘
```

## G2 — AI Impact Assessment

Blocking co-approval by the AI Risk Officer. Template:
`docs/templates/ai-impact-assessment.md`.

**1. Purpose and context (MAP 1).** What decision or task does the AI perform, for whom,
in what setting? What is the *non-AI* alternative and why is it insufficient? If a
deterministic solution works, that is usually the better engineering answer — AI is a
capability with an assurance cost, not a default.

**2. Affected people (MAP 1.1, 3.3).** Who is affected, including people who are not the
user. What is the worst realistic outcome for them? Where the system affects rights,
access, safety, employment, credit, health, or legal standing, the risk tier is elevated
and additional review applies.

**3. Risk tiering.**

| Tier | Criteria | Requirements |
|---|---|---|
| **Minimal** | Internal, no personal data, output non-consequential (e.g. code formatting) | Basic evals; standard gates |
| **Limited** | User-facing, output advisory, human acts on it | Evals + guardrails + disclosure to user |
| **High** | Affects rights/access/safety/finances, or processes sensitive personal data | Full assessment + red-team + bias testing + human-in-the-loop + monitoring |
| **Prohibited** | Deception at scale, covert manipulation, unlawful discrimination, safety-critical without human control | Not built. Escalate to a human decision-maker. |

**4. Data governance (MAP 2, 800-53 PT-/SI-).** Training/tuning/grounding data provenance
and license. Personal data — lawful basis, minimization, retention. Whether user data
reaches a provider, under what terms, and whether it is used for training (it must not be,
by contract, for anything non-public). Data quality and representativeness for the
population served.

**5. Failure mode analysis (MAP 5).** Confabulation, harmful or biased output, prompt
injection, sensitive-information disclosure, insecure output handling, denial of wallet,
overreliance, and the specific way *this* feature fails. Each gets a disposition — the
same four as any threat model: mitigate / transfer / accept / eliminate.

**6. Guardrail design.** Input validation and injection defense · output filtering and
validation · **treating model output as untrusted input to every downstream system**
(OWASP LLM02/LLM05 — the SQL injection lesson relearned: never eval, exec, or render
unescaped model output) · rate and cost limits · tool-call authorization checked
server-side against the *user's* rights, never the model's request · fallback behavior when
the model is unavailable or the guardrail trips.

**7. Human oversight design.** Where a human is in the loop, on the loop, or absent, and
why that is appropriate for the tier. What the human is shown in order to decide well —
including uncertainty. A human oversight point where the human sees only the answer and
not the basis for it is oversight in name only.

**8. Transparency (GOVERN 4.2, MAP 5.2).** Users are told they are interacting with AI.
Limitations are stated. Provenance is marked on generated content. There is a path to
contest or escalate a consequential output.

## G4 — AI verification

Blocking. `/ai-gate` runs it, and it does not pass on assertion.

### Eval suite (MEASURE 2)

Every AI feature has an eval suite that is version-controlled, run in CI, and gated on a
baseline. It is the AI equivalent of a test suite, and a feature without one is not
verifiable.

| Eval category | Asks |
|---|---|
| **Capability** | Does it do the task, on a representative set with known-good answers? |
| **Groundedness** | Are claims supported by the retrieved source, or confabulated? |
| **Robustness** | Does it hold under paraphrase, typos, unusual formatting, adversarial framing? |
| **Safety** | Does it refuse what it should refuse, and *not* over-refuse benign requests? |
| **Bias / fairness** | Does output quality or treatment vary across demographic slices? |
| **Injection resistance** | Does it follow instructions embedded in retrieved or user content? |
| **Disclosure** | Does it leak system prompt, other users' data, or internal detail? |
| **Cost / latency** | Within the NFR budget under representative load? |

Results are recorded per run with the model version, prompt version, and eval-set version.
**A regression against baseline blocks the merge**, exactly like a failing unit test.

Eval sets are held out from prompt development where possible; a prompt tuned against its
own eval set measures memorization, not capability.

### Red-teaming (MEASURE 2.7, 600-1)

Required for High tier, recommended for Limited. Adversarial, human-led, time-boxed,
charter-driven. Attempts: jailbreak and guardrail bypass · indirect prompt injection through
every content channel the system ingests · sensitive data extraction · tool-call abuse and
privilege escalation through the model · harmful content elicitation · unbounded cost.

Findings are severity-rated and enter the normal finding backlog with the standard SLAs. A
red-team exercise that finds nothing usually means the charter was too narrow — record that
judgment rather than reporting a clean bill of health.

### Guardrail verification

Each guardrail from the G2 design is verified by an automated test proving it **blocks** —
the negative-case rule from `05-verification.md` applies with full force here. A guardrail
verified only on the happy path is unverified.

## G5 and beyond — MANAGE

**Release.** Change record includes eval results vs. baseline, red-team status, residual
risk, and the model/prompt versions being deployed. Progressive rollout applies to AI
changes as to any other, and the canary metrics include AI-specific ones.

**Monitoring (MEASURE 2.4, MANAGE 4.1).** Live: guardrail trigger rate · refusal rate
(both directions — over-refusal is a real failure) · groundedness sampling · user feedback
and contest rate · cost and latency · **scheduled re-runs of the eval suite against
production**, because provider-side model updates change behavior with no diff on your side.
That last one is the control that catches the failure mode unique to hosted models.

**AI incidents (MANAGE 4.3).** Harmful/biased/materially wrong output, guardrail bypass,
successful injection, data leakage, unexplained behavior change. Standard incident process
(`08-operate-and-respond.md`) with the AI Risk Officer required. Postmortems feed the eval
suite — **every AI incident becomes an eval case.** That is how the suite earns its keep
over time.

**Decommission (MANAGE 4.2).** Removal is planned: data deletion, user notice, dependent
systems, retention of records for the audit period.

## AI system inventory (GOVERN 1.6, 800-53 CM-8)

Maintained at `docs/compliance/ai-inventory.md`: every AI system and feature, its owner,
tier, model and version, data touched, eval suite location, last red-team date, last
assessment date, and monitoring status.

An organization that cannot enumerate its AI systems cannot govern them, and this is the
first artifact an AI-focused assessor asks for.

## Control mapping

| Concern | AI RMF | 800-53 | ISO 42001 |
|---|---|---|---|
| Policy, roles, accountability | GOVERN 1–4 | PM-*, PL-2, AC-5, SA-3 | 5.2, 5.3, A.2, A.3 |
| Inventory | GOVERN 1.6 | CM-8, PM-5 | A.4 |
| Context & impact assessment | MAP 1–5 | RA-3, PT-*, SA-8 | A.5, 6.1 |
| Data governance | MAP 2, MEASURE 2.8 | PT-2, PT-3, SI-12, MP-6, SR-4 | A.7 |
| Testing & evaluation | MEASURE 2 | SA-11, CA-2, CA-8 | A.6, 9.1 |
| Red-team | MEASURE 2.7 | CA-8, SA-11(5) | A.6 |
| Guardrails / output handling | MANAGE 2 | SI-10, SC-7, AC-3 | A.6 |
| Transparency | GOVERN 4.2, MAP 5.2 | PT-5, SI-7 | A.8 |
| Monitoring | MEASURE 2.4, MANAGE 4 | CA-7, SI-4, AU-6 | 9.1, A.9 |
| Incident response | MANAGE 4.3 | IR-4, IR-6, IR-8 | A.10 |
| Change control | MANAGE 4.1 | CM-3, CM-4, SA-10 | 8.1 |
