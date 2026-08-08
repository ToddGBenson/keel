# ADR-0001: Governed agent-driven SDLC anchored to NIST 800-53

**Status:** Accepted
**Date:** 2026-08-07
**Deciders:** platform owner (human), with agent-drafted analysis
**Related:** `README.md`, `CLAUDE.md`, `docs/00-overview.md`, POAM-001

> The platform records its own architecture decisions using its own process. If we would not
> subject this repo to its own gates, we should not ask anyone else to.

## Context

A development platform was needed that takes ideas through to production with an auditable
assurance chain, uses AI agents to do the work, and satisfies a NIST control baseline. The
team is small; the human operator is the accountable party.

Four constraints shaped everything:

1. **Accountability cannot be delegated to an agent.** NIST's control model assumes a
   responsible individual. An agent cannot hold accountability.
2. **Controls that depend on remembering are not controls.** Whatever can be mechanical must
   be mechanical.
3. **The process must be amendable.** A process nobody can change becomes one everybody
   quietly routes around, which is worse than a smaller process people follow.
4. **Agents produce plausible output fast.** Review capacity, not production capacity, is the
   binding constraint — and complacent review is the failure mode.

## Decisions

### D1 — Anchor to 800-53 Rev. 5, crosswalk to SSDF

**Chosen** because 800-53 carries the accountability structure the platform depends on —
AC-5 separation of duties, AU audit trails, CA assessment and POA&M discipline, CM change
control. SSDF assumes these exist without specifying them.

**Rejected: SSDF as the primary anchor.** Better vocabulary for engineers, insufficient for
the governance spine. Retained as `docs/compliance/ssdf-crosswalk.md` — it is the view to
lead with when explaining the process to a development team.

**Consequence:** heavier than SSDF alone. Scope is SDLC-only; a full authorization needs
operational, physical, and personnel families that live outside this repo, and the control
map marks those honestly rather than implying coverage.

### D2 — Six gates, each = checklist + independent approver + evidence artifact

**Chosen** because anything less is theatre. A gate with a checklist and no independent
approver is self-certification; one with an approver and no evidence is an opinion.

**Rejected: stage-gates over the whole release.** Batches work and creates the pressure to
wave things through. Each item passes G1→G5 on its own timeline; what the gate enforces is
sequence of assurance, not batch size.

**Consequence:** more per-item overhead. Tailoring is explicit (`docs/00-overview.md`), and
skipped gates are recorded rather than silent.

### D3 — Agents execute, a human authorizes

**Chosen.** Agents assemble evidence; humans decide. The technical expression is a GitHub
Environment protection rule on `production` — the deploy job cannot start without a human
approval recorded with identity and timestamp, and that record *is* the CM-3 evidence.

**Rejected: fully autonomous agents.** Faster, and removes the human from the NIST
accountability chain entirely. That is not a tuning choice; it is the absence of the control.

**Consequence:** the human is a throughput limit. Mitigated by making decisions *cheap to
make well* — the agents' job is a complete, risks-first evidence bundle small enough to
actually read, not a decision the human rubber-stamps.

### D4 — Separation of duties enforced mechanically, not by convention

Producer ≠ approver, backed by CODEOWNERS, branch protection with no admin bypass, signed
commits, and `guard-bash.sh` blocking `gh pr merge` / `--approve` at the agent layer.

**Consequence — and the honest one:** *some* boundaries are enforceable and some are not.
Approve, merge, push, production, and secrets are enforced. **Per-agent write scope is not** —
Claude Code grants tool types rather than path scopes, and the hook payload carries no agent
identity. Recorded as **POAM-001** rather than claimed. See D7.

### D5 — Gate on new findings, not total

**Chosen.** Gating on absolute finding counts in any real codebase means the pipeline is red
from day one; within two sprints everyone clicks through it, and it detects nothing while
still showing green on assessment.

The existing backlog drains on severity SLA through the POA&M, where it has owners and dates.

**Consequence:** a pre-existing backlog can persist if the POA&M is not worked. That is why
past-due aging is the first thing `/status risks` reports.

### D6 — Every retro ends in a merged PR

**Chosen** because intentions decay and diffs do not. Actions convert to one of five artifact
changes or they are recorded as feelings.

**Consequence:** the process is version-controlled and its history is auditable — an assessor
sees not only what the process is, but when it changed and why (CM-3 applied reflexively).

### D7 — Skills hold the method; docs explain why; gates are the checklist

Added after the initial build, when STRIDE was found duplicated across five files. Skills are
authoritative for method; a doc that disagrees is the bug.

**Rejected: inlining method into each agent.** Simpler to read in isolation, guaranteed to
drift. The drift had already begun before the skills existed.

## How we would know we were wrong

Specific, observable signals that should trigger revisiting this ADR:

- **Gate rejection rate at zero across a quarter** → the gates are ceremony (D2)
- **Emergency change rate rising** → the normal path is too slow; fix the path, do not widen
  the emergency door (D2)
- **Escaped defects flat or rising** while lead time grows → process cost without benefit
- **Human approval consistently under ~2 minutes** on non-trivial releases → D3 has degraded
  into rubber-stamping and the evidence bundle is not doing its job
- **AI-authored changes failing review at a materially different rate** than human-authored →
  recalibrate review depth (AIC-9)
- **A new team member cannot be productive in a week** → too heavy; remove process
- **Exception register growing** → people no longer believe in the process

## Reversal cost

**Low to moderate.** The process is files, and the enforcement is GitHub configuration.
Abandoning it means deleting directories and relaxing branch protection.

What is *not* cheap to reverse is the evidence chain: work released under this process has
audit artifacts that a successor process must either inherit or orphan. Retention
obligations (`docs/10-definitions.md`) outlive the process that produced them.
