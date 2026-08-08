---
description: Independent code review of a PR or story (G3) — correctness, security, failure behavior, maintainability, test quality
argument-hint: <PR number or issue number>
allowed-tools: Read, Grep, Glob, Bash, Task
---

# G3 — Code Review: `$ARGUMENTS`

Run the gate in `process/gates/g3-code-complete.md`.

## Independence (AIC-2 / AC-5)

Spawn a **fresh `developer` agent invocation** that has not seen the implementation
reasoning. Do not ask the implementing agent to review its own work "with fresh eyes" —
there are no fresh eyes inside the same reasoning chain, and the correlation is exactly what
this control exists to break.

## Skills — load these first

- **`secure-code-review`** — the review order, and the **plausible-but-wrong catalogue** for
  AI-authored code. This is the method; do not improvise it.
- **`test-strategy`** — for judging whether the tests actually constrain behavior.
- **`dependency-vetting`** — if the PR touches a manifest or lockfile.

## What review is for

Not style. The linter handles style, and a review spent on formatting is a review that did
not look for the logic error.

The one thing to hold before you open the skill: **agent output is usually right, which is
exactly what makes complacent review dangerous.** Verify claims rather than reading them, and
state what you checked yourself.

## Checklist

- [ ] Every AC implemented, with a test that fails without the change
- [ ] Error paths and boundaries tested
- [ ] Negative-case test present for each allocated control
- [ ] All CI checks green — and **read** the results, not just the badge
- [ ] No new High/Critical SAST, SCA, IaC, container findings
- [ ] No secrets; no suppressions without rationale and expiry
- [ ] New dependencies verified, justified, licensed
- [ ] Observability requirements met
- [ ] Docs and runbook updated if behavior changed
- [ ] Issue linked, commits signed, AI authorship declared
- [ ] Threat model updated if the design changed during build
- [ ] PR ≤ ~400 changed lines (or a justified exception)

## Output

Approve · Request changes · **Ask a question** — the third is underused and often the most
valuable outcome.

```
G3 RESULT: APPROVE | CHANGES REQUESTED | QUESTIONS

Verified independently:
  - AC-1..3 traced to tests; confirmed each fails with the implementation stubbed
  - AC-3 authz: DraftAuthorizer:47 checks object ownership; negative test at api_test:212
Concerns:
  - drafts.py:88 — the quota check runs before the write but is not transactional;
    two concurrent autosaves can both pass. Reproduce: parallel POST at quota-1.
Not verified: performance NFR (deferred to /qa-gate)
```

## Then

**The reviewer approves — never the author.** Record on the PR. If changes are requested,
name the specific defect and how to reproduce it.
