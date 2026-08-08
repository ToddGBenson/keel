---
description: Implement a G1-ready story test-first on a branch, with control evidence and AI-authorship declaration (→ G3)
argument-hint: <issue number>
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, WebSearch, Task
---

# Implement: `$ARGUMENTS`

Delegate to the `developer` agent. Follow `docs/04-development.md` Part B.

**Skills:** `test-strategy` when deciding what to test where · **`dependency-vetting` before
adding any dependency** — non-negotiable, it is the AIC-7 control.

## Preconditions — verify before writing any code

1. The story has passed **G1**. If not, stop and run `/ready`.
2. If flagged security-, privacy-, or AI-relevant, **G2 artifacts exist** — threat model and
   control allocation. If not, stop and run `/design`.
3. Acceptance criteria are unambiguous. If anything is ambiguous enough to change your
   design, **ask now**. Guessing here is what produces a G4 rejection.

## The loop — non-negotiable order

```
branch  ──▶  FAILING TEST  ──▶  minimal implementation  ──▶  refactor green  ──▶  repeat
```

Write the failing test **first**, every time. A test written after the implementation
asserts what the code does; a test written before asserts what it should do. Only the second
catches the bug you were about to write, and only the second is credible SA-11 evidence.

Branch: `<type>/<issue>-<slug>`.

## Required coverage

- Every acceptance criterion has a test that **fails without your change**
- Error paths and boundaries, not just the happy path
- **A negative-case test for every control the threat model allocated** — the test proving
  the control *denies*. The positive case is feature evidence, not security evidence.
- Required logs, metrics, and traces from the story's observability criteria

## Dependencies (AIC-7)

Before adding any dependency, **verify the package actually exists and is the one intended** —
publisher, repository, download history, maintenance signal. Models hallucinate plausible
package names and attackers register them. Then license-check, scan, and justify it in the PR.

## Self-check before opening the PR

1. Does each AC have a test that fails without the change?
2. Error paths and boundaries covered?
3. Can you point at the line implementing each allocated control?
4. Every new dependency verified, justified, licensed?
5. Debuggable at 3 a.m. from what it emits?
6. **What did you make worse?** State it in the PR.
7. AI authorship declared?

## Commit and PR

Signed, Conventional Commits, with the issue reference and:

```
AI-Assisted: <model> (<scope of involvement>)
```

PR uses `.github/PULL_REQUEST_TEMPLATE.md`, fully completed. Keep it under ~400 changed
lines — beyond that reviewers skim, and everyone involved knows it. Split instead.

## Hard limits

Never bypass a hook (`--no-verify`), force-push, rewrite shared history, push to `main`, or
self-merge. If a hook blocks you, **the hook is working correctly** — fix the cause.

Never suppress a scanner finding. That requires Security sign-off with a written rationale
and an expiry date.

## Then

Report honestly: what you built, what you tested, **what failed**, what you skipped and why.
Then **hand off** — `/review` for code review, `/security-gate`, `/qa-gate`. You do not
review, verify, or release your own work (AC-5).

## Stop and ask a human when

A gate would be crossed · a secret or credential is involved · a High/Critical issue appears ·
blast radius exceeds the issue · an unplanned dependency or infra change is needed · the work
has drifted from the issue · you have failed the same task three times · you are asked to
weaken a control.
