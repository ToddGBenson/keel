# 07 — Release & Change Management (→ G5)

**Owner:** Release Manager · **Command:** `/release` · **Gate:** `process/gates/g5-release.md`
**Primary controls:** CM-3, CM-4, CM-5, CM-9, SA-10, CP-10

## Change classes

| Class | Definition | Path | Approval |
|---|---|---|---|
| **Standard** | Pre-authorized, low risk, repeatable, automated verification (dependency patch, config value within policy, doc change) | Normal pipeline, no per-change review | Pre-authorized by policy; recorded |
| **Normal** | Everything else — features, refactors, schema changes | Full G0–G5 | Human at G5 |
| **Emergency** | Active incident or actively exploited vulnerability | Expedited, below | Human at G5 (may be concurrent) |

Classification is recorded on the change record. Misclassifying a Normal change as Standard
to skip review is a control violation, not a shortcut, and the pipeline's PR governance
check is designed to catch it.

## The change record

Assembled by `/release`, stored at `evidence/releases/<version>/change-record.md`. It is
the CM-3 artifact an assessor will ask for.

1. **Identifier and scope** — version, every issue and PR included, nothing else
2. **Change class**
3. **Impact analysis (CM-4)** — components touched, interfaces changed, data migrations,
   backward compatibility, downstream consumers, security control impact, **AI system
   impact** if any model/prompt/data changed
4. **Gate evidence** — G4 clearance for every included item, with links
5. **Security posture** — open findings by severity, any accepted risks with their POA&M
   entries and expiry dates
6. **AI assurance** — eval results vs. baseline, red-team status, guardrail verification
   (if AI-relevant)
7. **Test evidence** — CI run, staging results, DAST, performance vs. NFR
8. **Supply chain** — SBOM diff vs. previous release, signature and provenance verification
9. **Deployment plan** — strategy, sequence, timing, feature flag states
10. **Rollback plan** — trigger conditions, **rehearsal evidence**, data-migration reverse
    path, maximum acceptable rollback window
11. **Verification plan** — post-deploy checks and who runs them
12. **Communication** — who is told, when, in what channel
13. **Authorization** — human approver identity, timestamp, GitHub Environment approval link

## Release readiness review

Release Manager convenes; Security, QA, and (if AI-relevant) AI Risk attend and each hold a
veto. Four questions:

1. **Did everything included clear G4?** Anything that did not is removed from the release,
   not waived. Scope shrinks; gates do not.
2. **What is the worst realistic outcome, and can we detect it?** If the answer to "how
   would we know" is "a customer will tell us," the release is not ready.
3. **Can we get back?** Rollback rehearsed, within a stated window, including data. A
   forward-only migration is a decision that requires explicit human sign-off, because it
   removes the safety net for everything else in the release.
4. **Who is available when it breaks?** Named person, reachable, with access. Releasing into
   an evening or a Friday with nobody on call is a choice, and it should be a conscious one.

## Human authorization (G5)

**A human being authorizes every production deployment.** Not an agent, not a rule, not a
schedule. Technically enforced by a GitHub Environment protection rule with required
reviewers — the deploy job blocks until a human approves in the UI.

The approver is confirming three things and is accountable for them: that the evidence is
complete, that the residual risk is understood and acceptable, and that the rollback is
real. Approving a release you have not read is the failure mode this control exists to
prevent; the agents' job is to make the evidence bundle small enough to actually read.

## Versioning & release notes

Semantic versioning. A breaking change is a MAJOR bump and a deprecation period, not a
paragraph in the notes.

Release notes are written for the reader, not the author: what changed for users, what
requires action, what is deprecated and when it disappears, known issues, and the security
fixes included. Security fixes are disclosed per the disclosure policy — silently patching
a vulnerability customers are exposed to is a trust failure even when it is legally
permitted.

## Emergency change procedure

For active incidents and actively exploited vulnerabilities only. Compresses *timing*.
Removes **no** control.

```
Declare emergency  ──▶  human approval to enter the path (recorded, with justification)
        │
        ▼
Minimal fix, single focused change — no opportunistic extras riding along
        │
        ▼
Abbreviated verification:  automated gates STILL RUN and STILL BLOCK
                           manual verification narrowed to the change's blast radius
        │
        ▼
Human authorization (may be concurrent with deploy for a live Critical incident)
        │
        ▼
Deploy with heightened monitoring
        │
        ▼
Within 72 HOURS: full change record, complete evidence, retro
                 ── not completed in 72h ⇒ the change is REVERTED ──
```

The 72-hour reversion rule is what keeps "emergency" from becoming the default path. Every
emergency change is reviewed at the next retro; a rising emergency rate is a signal that
the normal path is too slow, and the fix is to speed the normal path, not to widen the
emergency door.

## Post-release

**Immediately:** smoke tests, health check, error-rate and latency comparison to the
pre-deploy baseline, deployment record written.

**24 hours:** confirm the success metric from the original idea record is actually moving.
This is the loop closing — the step almost everyone skips, and the reason backlogs fill
with features nobody uses. If the metric did not move, that is a finding for the retro,
not an embarrassment to bury.

**Next retro:** what the release taught us, converted into a committed change.

## Change records as evidence

Retained per `10-definitions.md` § Retention. Together with the GitHub approval record,
signed commits, and pipeline logs, they constitute the CM-3 audit trail: **who changed
what, when, why, who approved it, and what evidence supported the approval.** That is the
question every assessor asks, and this is the shape of the answer.
