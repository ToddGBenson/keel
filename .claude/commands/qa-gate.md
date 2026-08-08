---
description: QA verification for G4 — execute the test plan, build the AC-to-test traceability matrix, run an exploratory charter
argument-hint: <issue or PR number>
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, Task
---

# G4 — QA Verification: `$ARGUMENTS`

Delegate to the `qa-engineer` agent. Per `docs/05-verification.md`.

**Skills:** `test-strategy` · `exploratory-testing` · `evidence-writing`.

## Independence

Spawn a fresh `qa-engineer` invocation. The identity that wrote the implementation does not
verify it (AC-5). Your job is not to confirm the developer's happy path — it is to find what
they did not imagine.

## 1. Traceability

Build AC → test → result and write it to `evidence/<issue>/g4/traceability.md`.

| AC | Test | Type | Result | Evidence |
|---|---|---|---|---|

**An AC with no test fails this gate.** A test with no AC is either dead weight or an
undocumented requirement — resolve which; do not leave it ambiguous.

## 2. Test quality audit and placement check

Per the **`test-strategy`** skill — the delete-the-implementation audit, layer placement,
flaky-test handling.

The two placements this gate always checks: **authorization tested at integration level**,
and **a negative-case test for every allocated control**.

## 3. Execute

Run the suite. Record results with run links. Report failures with output — never summarize
a failure as "minor".

## 4. Exploratory charter

Per the **`exploratory-testing`** skill — charter design, the productive heuristics,
note-taking as you go.

## 5. Non-functional verification

Performance against the stated number · reliability under deliberate dependency failure (kill
the DB mid-transaction and watch) · **rollback actually exercised**, not assumed ·
observability outputs confirmed present · accessibility by automated scan **plus** a real
keyboard and screen-reader pass.

## Output

```
G4 QA RESULT: PASS | FAIL

Traceability: 7/7 AC covered
Tests: 142 passed, 0 failed, 1 flaky (filed #211 — do not retry away)
Test quality: AC-5's test asserts internal ordering; passes with eviction logic
              removed. Not valid coverage. → FAIL
Exploratory: 45 min, 2 findings — #212 (Major, cross-tab silent data loss), #213 (Minor)
NFR: p95 240 ms vs. 200 ms target → FAIL
Not verified: screen-reader pass (no environment available) — stated, not claimed
```

## Rules

- Report results **exactly as observed**. If unverified, say **unverified** — never "passed"
  for something you did not run. A QA sign-off that overstates coverage is the most damaging
  artifact you can produce, because everything downstream trusts it.
- Reject **specifically**, naming the criterion and what was observed. "Needs more testing"
  is not a rejection.

## Then

Write to `evidence/<issue>/g4/qa/`. Hand defects to `developer` — you do not fix what you find.
