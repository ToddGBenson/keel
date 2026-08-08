# Test Plan — <story/epic> #<n>

**Author:** qa-engineer · **Agreed with:** product-owner (criteria), developer (approach)
**Gate:** G1 (approach agreed) → G4 (executed) · **Method:** the `test-strategy` skill

> Keep this short. A test plan longer than the story is a document nobody reads twice. For
> most stories this is half a page; the traceability matrix does the real work.

## Scope

**In:** what this change adds or alters.
**Out:** what is deliberately not tested here, and where it *is* covered.

## Risk-based focus

What would be most expensive if it broke? Weight effort there rather than spreading evenly.

| Risk | Likelihood | Impact | Where it gets tested |
|---|---|---|---|
| | | | |

## Layer allocation

Per the `test-strategy` skill. Two placements are non-negotiable and G4 checks both:

- **Authorization tested at integration level** — unit-mocked authz proves the mock
- **A negative-case test for every control the threat model allocated** — the test proving
  it *denies*

| Concern | Layer | Rationale |
|---|---|---|
| | Unit / Integration / E2E / Exploratory | |

## Traceability

Generated to `evidence/<issue>/g4/traceability.md`. An AC with no test **fails G4**.

| AC | Test | Type | Result | Evidence |
|---|---|---|---|---|

## Non-functional verification

Against the numbers stated at refinement — not against a judgement.

| NFR | Threshold | Method | Result |
|---|---|---|---|
| Performance | p95 < ___ ms at ___ concurrent, ___ rows | Load test | |
| Reliability | On <dependency> failure, behaviour is ___ | Deliberate fault injection | |
| Recovery | Rollback within ___ | **Actually exercised**, not assumed | |
| Observability | Emits ___ | Assertion | |
| Accessibility | WCAG 2.2 AA | Automated scan **+ keyboard/screen-reader pass** | |

## Exploratory charters

Per the `exploratory-testing` skill. One risk per charter, 45–90 minutes.

| Charter | Time-box | Findings |
|---|---|---|
| Explore ___ to discover ___ | | |

## Test data

What is needed, how it is generated, and confirmation it is **synthetic or properly
de-identified**. Production personal data never leaves production (MP-6) — a violation here
is a compliance finding, not a convenience.

## Environment

Where this runs, what must be available, what is stubbed and why.

## Entry and exit

**Entry:** G3 passed; build deployed to the test environment.
**Exit:** every AC traced to a passing test · negative-case tests present for all allocated
controls · NFRs verified against their numbers · exploratory charters run and findings filed
· **anything unverified stated as unverified, never as passed**.

## Not covered

State it explicitly. Overstated coverage is how gaps survive assessment, and a QA sign-off
that implies more than it verified is the most damaging artifact in this process — everything
downstream trusts it.
