---
name: writing-acceptance-criteria
description: Write or assess acceptance criteria that are binary, observable, and testable. Use when refining a story, running the G1 Definition of Ready gate, reviewing whether criteria are testable, converting a vague requirement into something QA can prove, or writing non-functional requirements with concrete thresholds.
---

# Writing acceptance criteria

Consumers: `product-owner`, `/refine`, `/ready`, `process/gates/g1-ready.md`, `qa-engineer`
(traceability).

## The single test

> **Could a reasonable person argue this passed when it did not?**

If yes, it is not a criterion. This one question decides most G1 rejections and is worth
applying to every line before anything else.

## Form

Given/When/Then. Cover three cases, minimum:

```gherkin
# happy path
Given I am editing a document and have unsaved changes
When my session expires and I sign in again within 24 hours
Then I am offered my most recent draft with its edit timestamp

# error path
Given my draft exceeds the 5 MB per-user storage limit
When autosave runs
Then the save is rejected, the oldest draft is evicted, and I see a non-blocking notice

# boundary
Given I have exactly 5 stored drafts and the limit is 5
When I create a sixth
Then the oldest is discarded and the new one is stored
```

The error path and the boundary are where the defects are. A story with only happy-path
criteria has not been refined; it has been described.

## Failure patterns

| Written | Why it fails | Rewrite |
|---|---|---|
| "The user sees their draft" | Which draft? Sees it where? In what state? | "The most recent draft is offered with its edit timestamp" |
| "The page loads quickly" | Unfalsifiable | "p95 < 200 ms at 100 concurrent users" |
| "The UI is intuitive" | Not observable | Delete it. If it matters, it is a usability test with a task success rate |
| "Errors are handled gracefully" | Which errors? What is graceful? | "On upstream timeout, the editor stays open, retries twice, then shows a retry action" |
| "Data is stored securely" | Restates the wish | "Draft bodies are encrypted at rest; a non-owner receives 403 on read" |
| "Works on mobile" | Which devices, which behaviour? | "At 375 px width the toolbar collapses and all actions remain reachable" |
| "Should validate input" | No boundary, no behaviour | "Titles over 200 chars are rejected with a field-level message; the draft is not saved" |

## The implementation-spec trap

Criteria state the **need**, not the solution — otherwise the story stops being negotiable
(the N in INVEST) and the team loses the freedom to find a cheaper answer.

```
✗ "A `drafts` table is created with columns id, user_id, body, updated_at"
✓ "A draft survives a browser crash and is offered on next sign-in"
```

The first forecloses the design at refinement time, by someone not building it.

## Non-functional criteria — with numbers

These are criteria, not decoration, and they carry the same binary test. Attach the ones that
apply:

| Type | Shape | Example |
|---|---|---|
| Performance | threshold + load + data volume | "p95 < 200 ms at 100 concurrent users with 10k drafts" |
| Security | the authz rule, the validation boundary, the audit event | "Only the owner may read a draft; `audit.draft.restored` is emitted with actor and draft id" |
| Privacy | what data, retention, minimization | "Draft bodies are deleted 30 days after account closure" |
| Accessibility | standard + interaction | "WCAG 2.2 AA; fully operable by keyboard; state changes announced" |
| Observability | what must be emitted to debug it | "Emits `draft.restore.failed` with reason code" |
| Reliability | the failure mode and the degradation | "If the store is unavailable, editing continues locally and the user is told saving is paused" |

**"Fast" and "secure" are not criteria.** If you cannot state the number, that is a spike —
not a guess written down.

## Relevance triage

While writing criteria, flag the story per `docs/10-definitions.md`. Any flag makes **G2
mandatory**, and getting this wrong at refinement is what produces an expensive surprise at
G4.

- **Security-relevant** — authn, authz, sessions, crypto, secrets, personal/regulated data,
  file upload or parsing, external calls, deserialization, template rendering, subprocess,
  query construction, infra/CI config, or a new dependency.
- **AI-relevant** — model call, prompt, system instruction, generation parameter,
  retrieval/grounding data, tool-calling capability, autonomy boundary; user data through a
  model; model output into a user-affecting decision.
- **Privacy-relevant** — collects, processes, stores, transmits, or deletes personal data, or
  changes retention, access, or purpose.

**When uncertain, flag it.** An unnecessary G2 costs an hour; a missed one costs a release.

## The open-question rule

A story with an open question **whose answer would change the design** is not Ready, however
complete its criteria look. Starting anyway means building the wrong thing efficiently.

Write open questions down explicitly. An unrecorded question does not stop existing; it
just surfaces mid-sprint as a clarification request, which is the thing refinement exists to
prevent.

## Handing off to QA

Each criterion should map to one test. If QA cannot see how to prove a criterion true or
false, it fails the T in INVEST — fix it now, not at G4.

For every security criterion, expect a **negative-case** test (proving denial), not just a
positive one. Write the criterion so that test is obvious:

```gherkin
Given I am not the owner of a draft
When I request it by id
Then I receive 403 and no draft content
```

## Controls

SA-3 · SA-4(3) · SA-8 (security requirements defined at design-in) · SA-11 (testability) ·
PL-8 · AI RMF MAP 2.3.
