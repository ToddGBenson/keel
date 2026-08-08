# Security Policy

**CIS Software Supply Chain 1.2.5** · **NIST IR-6, RA-5, SI-2** · **Owner:** Todd Benson

## Reporting a vulnerability

**Report privately. Never in a public issue.**

→ **[Open a security advisory](https://github.com/ToddGBenson/keel/security/advisories/new)**

Please include: what the flaw is, where (file and line), how to reproduce or why it is
reachable, and the realistic impact. A finding that cannot be acted on is a complaint — the
`scanner-triage` skill in this repo describes the shape of a good report if you want the
template.

### What happens next

| | |
|---|---|
| Acknowledgement | Within 3 business days |
| Triage and severity assignment | Within 7 days |
| Status updates | At least every 14 days while open |
| Credit | Named in the advisory unless you'd rather not be |

### Remediation targets

Severity is set from **realistic exploitability in context**, not the CVSS base score alone.
Deviations from a vendor score are recorded with reasoning.

| Severity | Definition | Target |
|---|---|---|
| Critical | Remotely exploitable without auth; RCE; mass exposure | 7 days |
| High | Exploitable with limited preconditions; privilege escalation | 30 days |
| Medium | Requires unusual conditions or significant privilege | 90 days |
| Low | Defence in depth, minimal realistic impact | Next planned cycle |

Every accepted finding gets a [POA&M](docs/compliance/poam.md) entry with an owner and a
date. That register is public and honest, including the entries that are inconvenient.

## Scope

**In scope** — the platform itself: guard hooks (`.claude/hooks/`), the setup and sync
scripts (`scripts/`), the CI/CD workflows, the agent and skill definitions, and the gate
logic. Control-bypass findings are the most valuable class here: *a way to merge without
the checks, to weaken a control without review, or to make a scanner report green on
something it never examined.*

**Out of scope** — anything you build **with** this template. Your fork is your system; this
repo governs how it is built, not what it does.

Also out of scope: the absence of controls already disclosed in
[the POA&M](docs/compliance/poam.md). Those are known and recorded — please read it first.
Reporting a known gap is not a finding, though a demonstration that a *compensating* control
does not actually compensate very much is.

## Known limitations, stated up front

This project is deliberately explicit about what it does **not** enforce. A documented weak
control is defensible; an overstated one is a finding.

- **POAM-008 — separation of duties.** Solo operator. AC-5 cannot be satisfied literally;
  independent human approval is not enforced. Compensated by a CI-required self-review
  artifact, a cooling-off period, all-checks-required, and quarterly external review.
- **Agent write-scope is prompt-enforced**, not tool-enforced (POAM-001). Verified: the
  hook payload carries no agent identity.
- **Workflows ship as skeletons.** Stack-specific steps are placeholders until
  `bootstrap.sh` splices a profile in. A fork that skips bootstrap has scanners that will
  correctly report *nothing was scanned* rather than passing.

Full detail: [`docs/compliance/`](docs/compliance/) — control map, CIS map, POA&M, evidence
model.

## Security of the AI layer

This platform uses AI agents to author code, which creates risks a human-only process does
not have. They are enumerated and controlled in
[`docs/11-ai-agent-controls.md`](docs/11-ai-agent-controls.md) (AIC-1..12): prompt-injection
isolation, secret handling, hallucinated-dependency defence, provenance, bounded autonomy.

If you find a way to make an agent in this repo take an action outside its documented
grant — merge, approve, push, reach production, handle a credential — **that is a Critical
finding** and the most interesting report we could receive.

## What we will not do

We will not silently patch a vulnerability that affects users of this template. Fixes are
disclosed in the advisory and the release notes. Quietly patching what people are exposed to
is a trust failure even where it is legally permitted.
