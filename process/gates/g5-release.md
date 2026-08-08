# G5 — Release Authorized

**Approver:** **A human operator.** Prepared by the Release Manager. Technically enforced by
a GitHub Environment protection rule with required reviewers.
**Command:** `/release` · **Reference:** `docs/07-release-and-change.md`
**Controls:** CM-3, CM-4, CM-5, CM-9, SA-10, SI-7, SR-4, CP-10, AU-2, AI RMF MANAGE

## The controlling constraint

**A human being authorizes every production deployment.** Not an agent, not a rule, not a
schedule. The agents' job is to make that decision *cheap to make well* — not unnecessary.

The approver is accountable for three judgments: the evidence is complete, the residual risk
is understood and acceptable, and the rollback is real.

## Checklist

| # | Item | Evidence |
|---|---|---|
| 1 | Scope enumerated exactly — every issue and PR, nothing else | Change record |
| 2 | **Every included item cleared G4** | Per-item evidence links |
| 3 | Change class recorded — Standard / Normal / Emergency | Change record |
| 4 | Impact analysis complete (CM-4): components, interfaces, migrations, backward compatibility, downstream consumers, control impact | Change record |
| 5 | **AI system impact assessed** if any model, prompt, or grounding data changed | Change record |
| 6 | Open findings listed by severity; **zero Critical, zero High** in scope | Finding register |
| 7 | Accepted risks each have a POA&M entry, human approval, and an expiry date | POA&M |
| 8 | AI assurance: evals vs. baseline, red-team status, guardrails verified | Eval report |
| 9 | Test evidence: CI run, staging results, DAST, performance vs. NFR | Run links |
| 10 | **SBOM diff** vs. previous release reviewed | SBOM artifacts |
| 11 | Artifact **signature and provenance verified** — and verification is enforced at deploy | Attestation |
| 12 | Deployment plan: strategy, sequence, timing, feature flag states | Change record |
| 13 | **Rollback plan with rehearsal evidence**, including the data path and its window | Rehearsal record |
| 14 | Verification plan: post-deploy checks and who runs them | Change record |
| 15 | Communication plan | Change record |
| 16 | **Named on-call person, reachable, with access** | Change record |
| 17 | Release notes written for the reader, including security fixes | Release notes |
| 18 | **Human authorization recorded** with identity and timestamp | GitHub Environment approval |

## Judgment notes

**Item 2** — anything without G4 clearance is **removed from the release**, not waived.
**Scope shrinks; gates do not.** This is the single item most often pressured, and holding it
is what makes every gate upstream mean something.

**Item 11** — a signature nobody verifies is decoration. The deploy job must verify and
refuse on mismatch (SI-7, SR-4).

**Item 13** — an untested rollback plan is a hypothesis, and this gate asks for a fact. A
forward-only migration removes the safety net for *everything else* in the release and
requires explicit human sign-off on that specific basis.

**Item 16** — releasing into a Friday evening with nobody on call is a legitimate choice, but
it must be a conscious one, not a default.

## How to present for authorization

**Lead with the risks, not the accomplishments.** An approver who has to hunt for the concerns
inside a positive summary is being managed rather than informed — and approving a release you
have not really read is exactly what this gate exists to prevent.

State plainly: what could go wrong, whether we would detect it, what residual risk we are
carrying and until when, and how we get back.

## Emergency changes

Compress **timing** only. Remove **no** control — automated gates still run and still block.
Human authorization may be concurrent with deploy for a live Critical incident.

**The 72-hour rule is absolute:** full change record and evidence completed within 72 hours,
or **the change is reverted**. That rule is what stops "emergency" from becoming the default
path. Every emergency change goes to the next retro; a rising rate means the normal path is
too slow, and the fix is to speed the normal path — never to widen the emergency door.

## Fail conditions

- Anything in scope lacks G4 clearance
- Any open Critical or High finding in scope
- Rollback untested, infeasible, or forward-only without explicit sign-off
- Signature or provenance verification not enforced at deploy
- Nobody on call
- An agent attempting to authorize, or a hand deployment outside the pipeline

## Exit

**Authorized** → pipeline deploys progressively with automated rollback on threshold breach.
**Not authorized** → scope reduced or issues resolved; re-present.

**Post-release:** smoke tests and health verification immediately; deployment record written;
and at **24 hours, confirm the success metric from the original idea record is actually
moving.** That last step closes the loop nearly everyone skips, and it is why backlogs fill
with features nobody uses.
