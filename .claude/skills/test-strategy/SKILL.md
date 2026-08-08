---
name: test-strategy
description: Decide what to test at which layer, and audit whether existing tests actually constrain behavior. Use when planning tests for a story, running the G4 QA gate, reviewing test quality in a PR, deciding between unit and integration coverage, or when asked whether coverage is meaningful. Includes the delete-the-implementation audit and flaky-test handling.
---

# Test strategy

Consumers: `qa-engineer`, `/qa-gate`, `developer`, `/review`, `process/gates/g4-verified.md`.

## Shape

```
        ╱╲          Exploratory — charter-driven, time-boxed. Finds what nobody imagined.
       ╱  ╲
      ╱────╲
     ╱  E2E ╲       Few. Critical journeys only. Slow, brittle — and irreplaceable for
    ╱────────╲      proving the whole thing hangs together.
   ╱Integration╲    Real collaborators: DB, queue, HTTP boundary, authz. This layer catches
  ╱────────────╲    what unit tests mock away, which is most real defects.
 ╱     Unit     ╲   Many, fast, deterministic. Pure logic, branches, boundaries.
╱────────────────╲
```

**Integration is the layer most teams under-invest in.** Unit-only suites produce systems
where every part passes and the whole fails. E2E-heavy suites produce slow, flaky suites
nobody trusts and everyone re-runs until green — which is worse than no suite, because it
still shows green.

## Placement

| Concern | Layer | Why |
|---|---|---|
| Business logic, branches, boundaries | Unit | Fast, exhaustive on the interesting cases |
| **Authorization decisions** | **Integration — always** | Unit-mocked authz proves the mock, not the authorizer |
| Persistence, transactions, migrations | Integration, real engine | An in-memory substitute has different semantics exactly where it matters |
| Contract with an external service | Contract test + recorded-fixture integration | |
| Critical user journey | E2E — one per journey, no more | |
| Input validation | Property-based where the space is large | |
| Performance NFR | Load test, threshold as the assertion, **representative data volume** | Performance on an empty database is not verified |
| Accessibility | Automated axe scan **+ manual keyboard and screen-reader pass** | The scan catches maybe half |
| **A security control from the threat model** | **Integration, negative case** | See below |

## The negative-case rule

For every control, the test that matters is the one proving it **denies**.

```
Positive:  owner reads their draft → 200      ← the feature works
Negative:  non-owner reads it      → 403      ← the CONTROL works
```

Only the second is SA-11 security evidence. A story whose controls have only positive tests
fails G4 regardless of coverage percentage.

## The test-quality audit

Judge tests by whether they **constrain behavior**. The check:

> **Mentally delete the implementation. Which tests fail?**

If a plausible bug would leave a test green, it is decorative — and worse than absent,
because it inflates the coverage number and buys false confidence.

Watch for:

- **Asserting implementation detail** rather than observable behavior — passes with the
  logic removed, fails on harmless refactors. Exactly backwards.
- **Assertions too loose to fail** — `assert result is not None`, `assert len(x) > 0`.
- **Setup so elaborate** the test's meaning is unrecoverable; nobody will maintain it and
  everybody will skip it.
- **Shared mutable state** between tests — passes in isolation, fails in CI, or vice versa.
- **Wall-clock or network dependence.**
- **Tests that mirror the implementation's structure** — they were written by reading the
  code, so they encode the same misunderstanding.

Report the audit as a finding, specifically:

> "AC-5's test asserts internal eviction ordering rather than observable behavior. It passes
> with the eviction logic removed entirely. Not valid coverage."

## Coverage

A **floor, not a target.** Coverage measures reach, not quality — 100% coverage of assertions
that cannot fail is 0% verification.

Two rules worth enforcing in CI:
- Absolute threshold met
- **No drop versus the base branch** — otherwise a large untested change passes by diluting
  an already-high number

## Flaky tests

**A flaky test is a defect. File it as one.**

Never retry it away. The retry hides a real race condition, and the race is the finding — it
is telling you something true about the system that you are choosing not to hear. A suite
with retries configured is a suite that has stopped being evidence.

## Traceability

Build AC → test → result. An AC with no test **fails G4**. A test with no AC is either dead
weight or an undocumented requirement — resolve which; do not leave it ambiguous.

```markdown
| AC | Test | Type | Result | Evidence |
|----|------|------|--------|----------|
| AC-1 draft offered on re-auth | test_draft_offered_after_expiry | Integration | ✅ | run #4821 |
| NFR authz | test_other_user_cannot_read_draft | Integration (negative) | ✅ | run #4821 |
| NFR p95 < 200 ms | load_draft_restore | Performance | ⚠️ 240 ms | run #4823 |
```

## Non-functional verification

- **Performance** — the NFR number is the assertion, under representative load *and data
  volume*
- **Reliability** — exercise dependency failure **deliberately**. Kill the DB mid-transaction
  and watch. Make the dependency *slow* rather than down; that path is usually untested and
  usually worse.
- **Recovery** — roll back for real, then roll forward. An untested rollback is a hypothesis.
- **Observability** — assert the required log, metric, or trace actually appears

## Reporting

Report results **exactly as observed**. If unverified, say **unverified** — never "passed"
for something you did not run. A QA sign-off that overstates coverage is the most damaging
artifact in this process, because everything downstream trusts it.

Reject **specifically**, naming the criterion and the observation. "Needs more testing" is
not a rejection.

## Controls

SA-11 · SA-11(1) · SA-11(8) · CA-2 · CM-4 · AU-2 (audit event verification).
