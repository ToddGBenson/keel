---
description: Decompose an accepted idea or epic into INVEST stories with binary acceptance criteria and relevance triage
argument-hint: <idea id, epic id, or issue number>
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, WebSearch, Task
---

# Refine: `$ARGUMENTS`

Run refinement per `docs/03-refinement.md`. Delegate to the `product-owner` agent; consult
`architect` where technical feasibility affects the split.

**Skills:** `story-splitting` for the decomposition · `writing-acceptance-criteria` for each
resulting story.

## Preconditions

The item must be **G0-accepted**. If it is not, stop and say so — refining an unaccepted
idea produces work that may never have been worth doing.

## Decompose

Split along **user-visible value**, never technical layers. Each story ships independently
and delivers something a person can observe.

```
✗ #1 Create table  #2 Build endpoint  #3 Wire UI      — nothing ships until all three
✓ #1 State survives tab close  #2 State survives session expiry  #3 Browse last 5 drafts
```

Valid split axes: workflow step · happy vs. error path · CRUD operation · data variation ·
user role · platform · performance target as its own measurable story.

## Per story, produce

- **Title and narrative** — as a `<role>`, I want `<capability>`, so that `<outcome>`
- **INVEST check**, each letter explicitly assessed. Any failure ⇒ fix or split.
- **Acceptance criteria** in Given/When/Then. **Binary and observable.** Cover happy path,
  at least one error path, at least one boundary. If two honest people could disagree about
  whether a criterion passed, rewrite it.
- **Non-functional criteria with numbers** — performance, security (authz rule, validation
  boundary, audit event), privacy, accessibility, observability, reliability. Never "fast"
  or "secure".
- **Relevance triage** — security-relevant? AI-relevant? privacy-relevant? Per
  `docs/10-definitions.md`. Any flag ⇒ **G2 is mandatory**. Getting this wrong here is what
  produces an expensive surprise at G4; when uncertain, flag it.
- **Dependencies** — named, with status.
- **Open questions** — anything whose answer would change the design. **A story with an open
  design-changing question is not refined**, however complete it otherwise looks.
- **Test approach** — one line, agreed in principle with QA.

## Rules

- Any story larger than ~3 developer-days gets split.
- Unknowns big enough to block estimation ⇒ create a **spike** instead, with a time box and
  the decision it unblocks.
- Do not write acceptance criteria as an implementation spec. State the need; leave the how
  negotiable.

## Then

Create the issues using `.github/ISSUE_TEMPLATE/story.yml`, linked to the parent. Report the
set and the open questions. **Run `/ready` before any of them enters development.**
