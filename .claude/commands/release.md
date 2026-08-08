---
description: Assemble the G5 change record, run the release readiness review, and present for human authorization
argument-hint: <version, e.g. v1.4.0>
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, Task
---

# G5 — Release: `$ARGUMENTS`

Delegate to the `release-manager` agent. Per `docs/07-release-and-change.md`.

**Skill:** `evidence-writing` — the change record is the CM-3 artifact an assessor asks for.

## 1. Establish scope

Enumerate exactly what is included — every issue and PR, nothing else. Ambiguity about scope
at release time is how un-gated work slips in.

**Verify G4 clearance for every item.** Anything without it is **removed from the release**,
not waived. Scope shrinks; gates do not.

## 2. Assemble the change record

To `evidence/releases/<version>/change-record.md`. This is the CM-3 artifact an assessor
asks for — complete, not tidy:

1. Identifier and exact scope
2. Change class — Standard / Normal / Emergency
3. **Impact analysis (CM-4)** — components, interfaces, data migrations, backward
   compatibility, downstream consumers, security control impact, **AI system impact** if any
   model, prompt, or grounding data changed
4. G4 clearance evidence per item, with links
5. Security posture — open findings by severity; accepted risks with POA&M links and expiry
   dates
6. AI assurance — evals vs. baseline, red-team status, guardrail verification
7. Test evidence — CI run, staging results, DAST, performance vs. NFR
8. Supply chain — SBOM diff vs. previous release, signature and provenance **verified**
9. Deployment plan — strategy, sequence, timing, feature flag states
10. **Rollback plan with rehearsal evidence** — including the data path
11. Verification plan — post-deploy checks and who runs them
12. Communications
13. Authorization — to be completed by the human approver

## 3. Readiness review

Convene `security-engineer`, `qa-engineer`, and — if AI-relevant — `ai-risk-officer`. Each
holds a veto. Four questions, no soft answers:

1. **Did everything included clear G4?** Show the evidence.
2. **What is the worst realistic outcome, and would we detect it?** If the answer to "how
   would we know" is "a customer will tell us," the release is not ready.
3. **Can we get back?** Rollback **rehearsed**, within a stated window, including data. A
   forward-only migration removes the safety net for everything else and needs explicit
   human sign-off on that basis.
4. **Who is on call?** Named, reachable, with access.

## 4. Present for authorization

Make the human's decision **cheap to make well** — not unnecessary.

**Lead with the risks, not the accomplishments.** An approver who has to hunt for the
concerns in a positive summary is being managed rather than informed, and approving a
release you have not really read is exactly what this gate exists to prevent.

```
RELEASE v1.4.0 — READY FOR AUTHORIZATION

Risks and residual exposure:
  - POA&M-024 accepted Medium (rate-limit gap on the export endpoint), expires 2026-10-01
  - Forward-only migration on drafts table — rollback restores schema but NOT
    drafts created between deploy and rollback. Window: ~15 min. Rehearsed 2026-08-05.
  - AI over-refusal rate doubled (0.02 → 0.04); below threshold but trending wrong

Scope: 6 stories, 2 bugs, 1 dependency bump — all G4-cleared (evidence linked)
Open findings in scope: 0 Critical, 0 High, 3 Medium (all within SLA)
Supply chain: SBOM diff +2 / −1 components; signature and provenance verified
On call: <name>, reachable, has access
Rollback: rehearsed, ~4 min, data caveat above

AUTHORIZATION REQUIRED — a human must approve in the GitHub Environment.
```

## Hard limits

- **You do not authorize.** A human does, via the Environment protection rule. That approval
  record is the evidence.
- **You do not deploy by hand.** The pipeline identity deploys. A hand deployment has no
  attestation and no audit trail.
- **You do not include un-gated work.** Ever.

## 5. Post-release

Immediately: smoke tests, health check, error-rate and latency vs. the pre-deploy baseline,
deployment record written.

At 24 hours: **confirm the success metric from the original idea record is actually moving.**
This is the step nearly everyone skips, and the reason backlogs fill with features nobody
uses. If it did not move, report that plainly — it is a retro finding, not an embarrassment.
