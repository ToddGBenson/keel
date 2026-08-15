# ADR-0005: The orchestrator approves gates, not a human

**Status:** Accepted
**Date:** 2026-08-15
**Deciders:** system owner (human), with agent-drafted analysis
**Related:** #65, ADR-0001, ADR-0004, PD-2, POAM-008, POAM-017, `docs/01-roles.md`,
`.claude/agents/delivery-lead.md`

## Context

A specification for a local agent-driven SDLC was supplied, containing:

> **No agent may advance work without Scrum Master approval.**

keel's PD-2 said the opposite: *"Gate approval is a human act, recorded in GitHub, backed by
evidence."* `delivery-lead` was defined as facilitating gates **without owning them**, and the
AC-5 separation-of-duties claim in the control map rested on a human standing between the
producing identity and the approving one.

The system owner was shown that conflict, and the cost of resolving it in the spec's favour,
and chose the spec. This ADR records what was decided and what it costs — not a justification
that it costs nothing.

## Decision

**`delivery-lead` approves every gate G0–G5.** Other roles produce evidence and recommend; it
records the transition. No work advances without it.

### D1 — Separation of duties survives by asymmetry, not by species

The old control was *different species*: a human approving a machine's work. The new one is
*different capability*:

> **The approver builds nothing. The builders approve nothing.**

`delivery-lead` holds no implementing scope — no source, no tests, no designs, no threat models,
no release artifacts. It is the only role that can approve and the only role that produces
nothing approvable. Those two properties are load-bearing on each other.

**The failure mode is therefore singular and namable:** if `delivery-lead` ever acquires
implementing scope, PD-2 is void and every AC-5 claim collapses with it. That is why its row in
`ai-inventory.md` is annotated as a security-relevant change, and why `validate-platform.py`'s
tool-grant drift check now matters more than it did — it is the mechanical guard on the one
thing that must not change.

### D2 — This is weaker than what it replaces, and is recorded as such

A prompt boundary is not a person. An agent cannot be answerable for an outcome, so accountability
does not disappear when a human stops approving — it **relocates**, onto whoever configured the
orchestrator, who now answers for transitions they did not read.

We are not claiming equivalence. **POAM-017** records the reduction at High. The honest summary:

| | Before | After |
|---|---|---|
| Approver | human | `delivery-lead` |
| Enforced by | a different person | a prompt and a tool grant |
| Detects a bad approval | at the time | at assessment, or never |
| Accountable | the approver | whoever configured the approver |

### D3 — Two carve-outs remain human

1. **A release reaching production.** `delivery-lead` may approve G5 for a change that ships
   nothing to real users — which is every release keel itself makes (ADR-0004). It hands over
   when a release leaves the building. Forks that deploy are advised in POAM-017 to keep G5
   human, and the advice is in `delivery-lead`'s own prompt so it travels with the role.
2. **A live Critical or High block.** `security-engineer` and `ai-risk-officer` block, and
   `delivery-lead` cannot approve past a block — only record that the blocking role withdrew it,
   with a reason. Without this, "blocking authority" would mean nothing.

### D4 — A gate that never rejects is not a gate

The predictable failure is not a dramatic bad approval; it is drift toward approving everything,
because approving is frictionless and rejecting requires an argument. So: **`delivery-lead`'s
rejection rate is a monitored metric, and a zero rate across a quarter is a finding about this
control**, raised in the retro rather than celebrated.

## Consequences

**Good.** The lifecycle runs unattended. The gate criteria get read every time, mechanically,
which humans under delivery pressure demonstrably do not do. Rejections become cheap, which is
the thing most likely to make the gates real rather than ceremonial.

**Bad.** The strongest control in the framework has been traded for a weaker one, to buy
throughput. Anyone reading the control map must now understand that "separation of duties" means
something different here than it does in the source standard.

**Unresolved.** Nothing detects a `delivery-lead` that approves badly *at the time it happens*.
The compensating controls are the tool-grant check, the recorded evidence trail, and the
quarterly assessment — all detective, none preventive. POAM-017 stays open on that basis, and
this is the second control in this repository (with POAM-008) where solo, unattended operation
is accepted rather than solved.
