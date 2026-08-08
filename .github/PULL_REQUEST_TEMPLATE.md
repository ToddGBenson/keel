# <type>(<scope>): <summary>

Closes #<issue>

> A PR without a linked issue, a completed DoD checklist, or an AI-authorship declaration is
> **closed, not fixed in review**. `pr-governance.yml` enforces this.

## What and why

What changed, and what problem it solves. Link the story's acceptance criteria.

## What I made worse

Performance, coupling, an abstraction that now leaks, a test that got slower, a TODO left
behind. Say it here rather than hoping review misses it — a PR that claims to make everything
better and nothing worse is one reviewers learn to distrust.

*(If genuinely nothing: "nothing identified" — but look first.)*

## AI authorship — required (AIC-6)

- [ ] **Parts AI-authored:** <files/functions, or "none">
- [ ] **Agent / model:** <e.g. `developer` agent, claude-opus-5>
- [ ] **What I verified personally, not just read:** <specific — "traced AC-1..3 to tests and
      confirmed each fails with the implementation stubbed">

> Not a warning label — provenance data. It lets us measure whether AI-authored changes fail
> review at a different rate and tune review depth on evidence. Concealing it is a process
> violation.

## Acceptance criteria → tests

| AC | Test | Fails without this change? |
|---|---|---|
| AC-1 | `test_...` | ✅ |

## Definition of Done

**Code**
- [ ] Every AC implemented, each with a test that **fails without the change**
- [ ] Error paths and boundaries tested, not just the happy path
- [ ] **Negative-case test for every control the threat model allocated** (the test proving
      it *denies*)
- [ ] Coverage threshold met, no drop vs. `main`
- [ ] Lint, format, static typing clean
- [ ] No new High/Critical SAST, SCA, IaC, or container findings
- [ ] No secrets in source or history
- [ ] No suppressions without a written rationale **and an expiry date**
- [ ] New dependencies **verified to exist and be the intended package**, licensed, justified
      below

**Verification**
- [ ] Required logs / metrics / traces emitted
- [ ] Accessibility verified (if user-facing)
- [ ] Threat model updated if the design changed during build

**Governance**
- [ ] Issue linked; commits signed and conventionally formatted
- [ ] Docs / runbook updated if behavior changed
- [ ] Control evidence written to `evidence/<issue>/`
- [ ] ADR written, or explicitly not needed

## Security

- **Security-relevant?** yes / no — if yes, link the threat model and G2 approval
- **Controls implemented:** `<control>` → `<file:line>` → `<verifying test>`
- **New attack surface:** what, and why it is justified

## AI feature changes *(if AI-relevant)*

- [ ] AI Impact Assessment linked; risk tier: ______
- [ ] Eval suite run — **no regression vs. baseline** (attach report)
- [ ] Model version, prompt version, eval-set version recorded
- [ ] Every guardrail has a test proving it **blocks**
- [ ] **Model output treated as untrusted input downstream** — not evaled, exec'd, rendered
      unescaped, or passed to a privileged operation unvalidated

> **A prompt change is a code change.** This section applies to prompt-only diffs.

## New dependencies

| Package | Version | Why | License | Existence verified (publisher/repo/downloads) |
|---|---|---|---|---|

*(none — delete this section)*

## Rollback

How to undo this. Any data migration and whether it is reversible.

## Reviewer notes

Where you want scrutiny, and what you are least sure about.

## Self-review — required if nobody else approves (solo mode, POAM-008)

Delete this section if another identity approved. Otherwise it **is** the review evidence,
and `pr-governance.yml` will block the merge without it. Run `/self-review <PR>`.

- **Record:** `evidence/<issue>/g3/self-review.md`
- **Opened / reviewed:** `<timestamp>` → `<timestamp>` (cooling-off: don't merge same session)
- **Verified independently:** *specific claims you checked, not "reviewed it"*
- **Agent findings:** developer · security-engineer · qa-engineer
- **Not verified:** *say "unverified", never "passed"*
- **Cold-read notes:** *what you saw on the second, later look*

> A self-review with nothing in "Not verified" or "Cold-read notes" is a self-review that did
> not happen. See `docs/13-solo-operation.md` for what this control does and does not cover.

---

**Reviewer:** you are approving as an identity that is **not the author** (AC-5). State what
you verified independently — "LGTM" on agent-authored code is a control failure. Approving
code you do not understand is too; "explain it or simplify it" is the correct response.
