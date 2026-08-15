# G3 — Code Complete

**Recommends:** A reviewing engineer who is **not the author** · **Approves:** Delivery Lead (ADR-0005) · **Command:** `/review`
**Reference:** `docs/04-development.md` Part B · **Controls:** SA-3, SA-10, SA-11(1),
SA-15, CM-3, CM-5, AC-5, SI-7, SR-3/4/11, AIC-2, AIC-6, AIC-7, AIC-9

## The controlling constraint

**The author does not approve.** Not with a different framing, not "quickly", not because it
is obviously fine. Spawn a **fresh** reviewing identity that has not seen the implementation
reasoning — there are no fresh eyes inside the same reasoning chain (AC-5, AIC-2).

## Checklist

| # | Item | Evidence |
|---|---|---|
| 1 | Every AC implemented, each with a test that **fails without the change** | Test run |
| 2 | Error paths and boundaries tested, not just the happy path | Test files |
| 3 | **Negative-case test present for every allocated control** | Test files |
| 4 | Unit + integration tests pass; coverage threshold met with **no drop vs. `main`** | CI run |
| 5 | Lint, format, static typing clean | CI run |
| 6 | No **new** High/Critical SAST findings | CodeQL SARIF |
| 7 | No **new** High/Critical dependency vulnerabilities | SCA report |
| 8 | No **new** High/Critical IaC or container findings | Scan reports |
| 9 | No secrets in source or history | gitleaks run |
| 10 | No suppressions without a written rationale **and an expiry date** | Diff review |
| 11 | New dependencies **verified to exist and be the intended package**, licensed, justified | PR body |
| 12 | Observability requirements met — required logs/metrics/traces emitted | Code + test |
| 13 | Docs and runbook updated if behavior changed | Diff |
| 14 | Issue linked; commits signed and conventionally formatted | Git log |
| 15 | **AI authorship declared** — which parts, which agent | PR body |
| 16 | Threat model updated if the design changed during build | Threat model doc |
| 17 | PR ≤ ~400 changed lines, or a justified exception | Diff stat |
| 18 | Reviewer states **what they verified independently** | Review comment |

## Judgment notes

**Item 3** is the security evidence. A test showing an authorized user succeeds proves the
feature; only the denial test proves the control (SA-11).

**Items 6–8: fail on *new*, not total.** Gating on absolute counts in a real codebase means
the pipeline is red forever and everyone learns to ignore it. The existing backlog is driven
down on SLA via the POA&M.

**Item 11 (AIC-7)** — models hallucinate plausible package names and attackers register them.
Verify the publisher, repository, and download history. This check is cheap and the failure
is a supply-chain compromise.

**Item 18** is the counter to automation bias (AIC-9). "LGTM" on agent-authored code is a
control failure. State what you checked yourself: "traced AC-1..3 to tests and confirmed each
fails with the implementation stubbed." Saying "I don't understand this — explain it or
simplify it" is the correct professional response, not rudeness.

### Reviewing AI-authored code specifically

Agent output is usually right, which is exactly what makes complacent review dangerous. Look
for **plausible-but-wrong**: correct-looking code with an inverted condition, an off-by-one,
a `catch` that swallows, a check on the route rather than the object, a guard that runs but
is not transactional.

## Fail conditions

- The author approved their own PR
- An AC with no test, or a test that passes with the implementation removed
- A suppression without rationale and expiry
- An unverified new dependency
- AI authorship not declared
- Reviewer approved without stating what they verified

## Exit

**Approve** → eligible for G4 (`/qa-gate`, `/security-gate`, `/ai-gate` if applicable).
**Changes requested** → back to the author with the **specific defect and how to reproduce it**.
**Questions** → a legitimate and often the most valuable outcome.
