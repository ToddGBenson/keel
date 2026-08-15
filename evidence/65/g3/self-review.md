# Self-review — #65

Mode: solo (POAM-008)
PR: #66   Author: Todd Benson (claude-opus-5, AI-authored)   Date: 2026-08-15

Adopting the supplied agentic-SDLC specification: UX role, RACI, developer pool, observability
loop, and — the consequential one — moving gate approval from a human to `delivery-lead`.

## Verified independently

- **The four gaps were measured, not assumed.** `git grep` for UX/accessibility, RACI, vector
  store, and per-agent model assignment returned **zero matches** across the repository before
  any change. I did not argue from memory about what keel lacked.
- **All 15 agents pass the tool-grant drift check** against `ai-inventory.md`
  (`validate-platform.py`), including the five new ones. That check is now load-bearing: it is
  the mechanical guard on the one property PD-2 depends on.
- **`ux` was given no `Bash` grant**, deliberately, so it cannot execute the thing it specifies.
  `delivery-lead` was given no source, test, design or threat-model scope. The asymmetry is real
  in the tool grants, not only in the prose.
- **Both validators pass**, and the manifest still governs every tracked path with the five new
  agent files and the new ADR included.
- **Stale claims were hunted with `git grep`, not from memory.** One survived — ADR-0003's
  restatement of the old PD-2 — and it is marked superseded-in-part rather than edited, because
  rewriting an old ADR's reasoning to match a new decision destroys the only thing ADRs are for.

## Agent findings

**None — no three-pass agent review.** Consistent with every PR since #48, and **least
defensible here**: this change rewrites a prime directive and downgrades a NIST control claim.

**If one thing gets an independent read, make it ADR-0005 §D1** — the claim that separation of
duties survives as an asymmetry between agents rather than between species. If that argument is
wrong, POAM-017 is understated and AC-5 should read ❌ rather than 🟡.

## Not verified

- **Nothing has actually run under the new authority.** No gate has been approved by
  `delivery-lead` since the change. The control is written, not exercised — the same gap that
  #56 recorded for `sync-platform.sh` and #58 for the release lane, and it is becoming this
  repository's characteristic weakness.
- **The compensating controls in POAM-017 are all detective.** I could not devise a preventive
  one that does not reintroduce the human the owner chose to remove. The absence is recorded in
  the ADR's Consequences rather than papered over.
- **The G5 carve-out is untestable here.** keel ships nothing to production (ADR-0004), so
  "hand to a human when a release reaches real users" has no path to being exercised in this
  repository. A fork inherits an untested carve-out.
- **`docs/adr/` is `project_owned`**, so **forks will not receive ADR-0005**. I judged this
  acceptable because the operative rules travel in platform-owned files — PD-2 in `CLAUDE.md`,
  the carve-outs in `delivery-lead`'s own prompt — but a fork inherits the *rule* without the
  *reasoning*, and someone will eventually ask why their orchestrator can approve a gate.
- **The RACI is asserted, not derived.** I wrote it from the gate definitions and role
  boundaries. No historical rejection was analysed to check whether the consultations it
  prescribes are the ones that were actually missing.
- **Five new agents have never been invoked.** Their prompts are untested against real work.

## Cold-read notes

- **What I did not want to look at:** I recommended the human-approval option, the owner chose
  otherwise, and I then had to write the change well rather than write it grudgingly. The
  temptation was to lard it with warnings until the feature was unusable — a way of being
  overruled without accepting it. The carve-outs I kept (live blocks, production releases) are
  ones I would defend on their own merits; I checked each against "would I have proposed this if
  I had agreed from the start?" and dropped the ones that failed.
- **The strongest part of the change is the tool-grant asymmetry, and it is strong by accident.**
  `validate-platform.py` already checked agent tool grants against the inventory for a different
  reason (AIC-3 drift). That check now happens to be the enforcement point for PD-2. I did not
  design that; I noticed it and wrote it down. It is worth someone deciding whether to make it
  explicit rather than incidental.
- **Two agent-enforced controls now verify each other.** POAM-008's compensating control is a
  self-review artifact; `delivery-lead` is what checks it. That is recorded in POAM-017 and I do
  not think it is fine — it is the kind of arrangement that looks like two controls and behaves
  like none.
- **The developer pool is the weakest-value part of this change.** Four specialists carry real
  failure-mode knowledge, but the spec's own advice was that orchestration matters more than
  agent count, and I added four agents on a day when nothing exercised them. If one thing here
  gets deleted in six months, it should be these, and that would be the right call.

## Residual risk accepted

- A prime directive rewritten and a NIST control downgraded, on a single-identity review.
- Separation of duties now rests on a prompt boundary and one automated tool-grant check.
- Nothing in this change has been exercised by real work.
- Next external sample review due: 2026-10-01.
