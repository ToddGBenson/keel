# 04 — Design & Development (→ G2, G3)

**Owners:** Architect, Security Engineer, AI Risk Officer (G2); Developer (G3)
**Commands:** `/design`, `/implement`, `/review`
**Gates:** `process/gates/g2-design.md`, `process/gates/g3-code-complete.md`

---

## Part A — Design (G2)

Required when the story is flagged security-relevant or AI-relevant, or when the change
is expensive to reverse. Skipped for routine work — and the skip is recorded, not silent.

### Architecture Decision Records

Write an ADR when a decision is **costly to reverse**: data model shape, service boundary,
persistence or messaging technology, auth model, external dependency, public interface
contract, or an AI model/provider choice.

Do not write an ADR for reversible choices. An ADR that documents a decision nobody would
revisit is filler that devalues the ones that matter.

Template: `docs/templates/adr.md`. Status flows `Proposed → Accepted → Superseded`. ADRs
are **immutable once accepted** — you supersede, you do not edit. The record of what we
believed and why is the point.

### Threat modeling — STRIDE

> **The `threat-modeling` skill is authoritative for the method.** What follows is the
> explanation — why the gate exists and what it is for. If the two ever disagree, the skill
> wins and this section is the bug. Practitioners execute from the skill; this page is for
> understanding the process.

Run per-story on the delta, not the whole system. Full-system models go stale and get
ignored; delta models stay true.

Answer four questions (Shostack): *What are we building? What can go wrong? What are we
going to do about it? Did we do a good job?*

| Threat | Asks | Control family |
|---|---|---|
| **S**poofing | Can an actor claim an identity they do not hold? | IA-2, IA-5, SC-8 |
| **T**ampering | Can data be modified in transit, at rest, or in the pipeline? | SI-7, SC-8, SC-28, CM-14 |
| **R**epudiation | Can an actor deny an action we cannot prove? | AU-2, AU-3, AU-12 |
| **I**nformation disclosure | Can data reach an unauthorized party? | AC-3, SC-28, SC-8, MP-6 |
| **D**enial of service | Can availability be exhausted, and by whom, at what cost? | SC-5, SC-6, CP-10 |
| **E**levation of privilege | Can an actor gain rights beyond their grant? | AC-3, AC-6, CM-7 |

Every identified threat gets one of four dispositions, recorded: **mitigate** (control +
where it lives + how it is verified) · **transfer** · **accept** (human approval + POA&M
entry + review date) · **eliminate** (remove the feature or the data).

An unmitigated threat with no recorded disposition is a G2 failure. Template:
`docs/templates/threat-model.md`.

### Control allocation

For every control the threat model invokes, name three things or the allocation is
incomplete:

| Control | Component that implements it | How it is verified | Evidence artifact |
|---|---|---|---|
| AC-3 authz on draft read | `DraftAuthorizer` in the API layer | Integration test, negative case | Test result + coverage |
| SI-10 input validation | Schema validation at the boundary | Property test + SAST rule | SARIF + test report |
| AU-2 audit event | `audit.draft.restored` emitted | Assertion in integration test | Test result, log sample |

"Implemented in the application" is not an allocation. Name the file.

### Secure design principles (SA-8)

Applied, not recited. At G2 the architect states how each holds — or why it does not:

**Least privilege** — every component runs with the minimum grant, including CI jobs and
agent tool scopes. **Defense in depth** — no single control failure is catastrophic.
**Fail secure** — an error denies rather than permits; a crashed authorizer does not mean
"allow". **Complete mediation** — every access is checked, not just the first.
**Economy of mechanism** — a security control you cannot fully reason about is not one.
**Open design** — security rests on keys and configuration, never on the design being
secret. **Minimize attack surface** (SA-15(5)) — every new endpoint, parameter, and
dependency is surface; justify it. **Secure defaults** — the out-of-box configuration is
the safe one, always.

### AI design review

If the AI-relevant flag is set, the AI Risk Officer runs the AI Impact Assessment at G2
and it is a blocking co-approval. Details in `12-ai-feature-governance.md`; template at
`docs/templates/ai-impact-assessment.md`.

---

## Part B — Development (G3)

### The loop

```
  Pull the G1-ready story
        │
        ▼
  Write the failing test that expresses an acceptance criterion   ◀── start here, always
        │
        ▼
  Smallest implementation that passes it
        │
        ▼
  Refactor with the test green
        │
        ▼
  Repeat until every AC has a passing test
        │
        ▼
  Self-check against the DoD  ──▶  gaps? back into the loop
        │
        ▼
  Open PR with complete evidence  ──▶  independent review (G3)
```

Test-first is not a style preference here. A test written after the implementation tends to
assert what the code does; a test written before asserts what the code *should* do. Only the
second kind catches the bug you were about to write, and only the second kind is credible
verification evidence for SA-11.

### Branching

Trunk-based. Short-lived branches off `main`, merged within ~2 days. Long-lived branches
accumulate merge risk and hide un-reviewed work from the scanners that run on `main`.

`<type>/<issue>-<slug>` — `feat/142-draft-autosave`. Types: `feat` `fix` `chore` `docs`
`refactor` `test` `sec`.

Behind a feature flag if the work spans more than one merge. An unfinished feature merged
dark is safer than a branch that lives a week.

### Secure coding practice

Not exhaustive — the failure classes that actually ship:

- **Validate at the boundary, encode at the sink.** Validation is not escaping. Both are
  required, in different places. (SI-10)
- **Parameterize every query.** No string-built SQL, ever, including in tests and
  migrations — tests are where the copy-paste pattern gets learned.
- **Authorize on every access, server-side, on the object.** Not on the route. Not in the
  UI. IDOR is still the most common real finding in a mature codebase. (AC-3)
- **Never log secrets, tokens, or personal data.** Assume logs are read broadly and
  retained longer than you expect. (AU-3, SC-28)
- **Fail closed.** `catch { return allowed }` is how breaches begin.
- **No secrets in source.** Injected at runtime from a secret manager. If one leaks, rotate
  first, remove second — a deleted commit is not a rotated credential. (IA-5)
- **Pin and verify dependencies.** Lockfiles committed; integrity hashes verified; new
  dependencies justified in the PR. (SR-3, SR-4, SR-11)
- **Errors tell the user what to do, not how the system is built.** Stack traces and
  internal identifiers stay in logs.
- **Deterministic, isolated tests.** No shared mutable state, no wall-clock dependence, no
  network. A flaky test is a defect, filed as one — never retried away.

### The developer's self-check, before opening the PR

Run `/implement` and it enforces this. Manually, the questions are:

1. Does each acceptance criterion have a test that fails without my change?
2. Did I test the error paths and the boundaries, not just the happy path?
3. Are the controls named in the threat model actually implemented — can I point at the
   line?
4. Did I add a dependency? Is it justified, licensed compatibly, and maintained?
5. Does this emit what an operator needs to debug it at 3 a.m.?
6. What did I make worse? (Performance, coupling, an abstraction that now leaks.) Say it
   in the PR rather than hoping review misses it.
7. Have I declared which parts are AI-authored?

### Pull requests

Small. A PR over ~400 lines of change receives a materially worse review — reviewers
degrade to skimming, and everyone involved knows it. Split it.

The PR body follows `.github/PULL_REQUEST_TEMPLATE.md` and must include the issue link,
the DoD checklist, control evidence for anything the threat model allocated, and the
AI-authorship declaration.

### Code review (G3)

Performed by an identity that is **not** the author. The reviewer's job is not to find
style violations — the linter does that, and a review spent on formatting is a review that
did not look for the logic error.

Review for, in order: **correctness** (does it do what the AC says, including the paths not
exercised by the happy case) · **security** (authz, input handling, secrets, the threat
model's controls) · **failure behavior** (what happens when the dependency is down, the
input is hostile, two requests race) · **maintainability** (will the next person understand
this) · **test quality** (do the tests actually constrain behavior, or do they assert
implementation details and pass regardless).

Reviewers approve, request changes, or **ask a question** — the third is underused and
often the most valuable. Approving code you do not understand is a failure of the control,
not politeness.

**Control mapping:** SA-3, SA-8, SA-10 (developer configuration management), SA-11 and
SA-11(1)(2) (developer testing, static analysis, threat/vulnerability analysis), SA-15,
SA-17 (developer security architecture), CM-3 (change control), CM-5 (access restrictions
for change), SI-10, SI-7, SR-3/4/11.
