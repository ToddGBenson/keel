---
name: control-verification
description: Verify that a security control actually exists and actually works, rather than that it was planned or that a scanner ran. Use at the G4 security gate, when checking whether a threat model's allocated controls were implemented, when asked to confirm a control is effective, or when auditing a control claim. Includes adversarial reading technique.
---

# Control verification

The core act of G4 security. Consumers: `security-engineer`, `/security-gate`,
`process/gates/g4-verified.md`, `compliance-officer` (assessment).

## This is not scanning

Scanners are the floor. They find known patterns in code they can reach. They do not tell you
whether *the control your threat model allocated* is present, on every path, and effective.

Verification is a manual, adversarial act performed against a specific allocation. A gate that
passes because CodeQL was green has verified nothing about the design's controls.

## The four steps, per allocated control

### 1. Find the implementation

Locate it. **File and line.**

> If you cannot find it, **the control is not implemented** — regardless of what the design
> document says.

That sentence resolves more G4 rejections than any other. Designs describe intent; code is
what ships. A control that was allocated at G2 and never written is the single most common
real gap, and it is invisible to every scanner because there is nothing there to scan.

### 2. Find the negative-case test

The test proving the control **denies**.

```
Positive test:  owner requests their draft → 200        ← proves the FEATURE works
Negative test:  non-owner requests draft   → 403        ← proves the CONTROL works
```

Only the second is SA-11 security evidence. If there is only a positive test, the control is
**unverified**, and you say so.

Then confirm the test is real: would it fail if the control were removed? Mentally stub out
the check — does the test go red? If not, it asserts something else and is not coverage.

### 3. Read it adversarially

This is the part that finds what tests and scanners miss. Ask, deliberately:

- **Is the check on every path, or only the obvious one?** Trace the alternates: the batch
  endpoint, the export path, the admin route, the retry, the webhook.
- **Does an error path skip it?** An early `return` or a `catch` that continues past the
  check.
- **Is authorization on the object or on the route?** Route-level authz plus an ID parameter
  is IDOR, and it is still the most common real finding in mature codebases.
- **Is it transactional where it needs to be?** A quota or uniqueness check that reads then
  writes without a lock passes twice under concurrency.
- **Is it enforced server-side?** A UI check is not a control. A client-supplied role is not
  a control.
- **What state reaches past it?** Cached values, pre-computed permissions, a session that
  outlives a privilege change.
- **Does it fail closed?** `catch { return allowed }` is how breaches begin. What does this
  do when the authorizer throws, the store is down, the token parse fails?
- **Ordering** — is the check before the side effect, or after it?

When you find something, state the **reproduction**, not the concern:

> "drafts.py:88 — the quota check reads the count and writes outside a transaction. Two
> concurrent autosaves at quota−1 both pass. Reproduce: parallel POST to /drafts with the
> user at 4 of 5."

### 4. Record the evidence

Three sections, always — see the `evidence-writing` skill:

```markdown
## Verified
AC-3 object authz → DraftAuthorizer.java:47
  Negative test api_test.py:212; confirmed red when the ownership check is stubbed. ✅

## Unverified
SI-10 input validation — schema exists at schema.py:31 but no test exercises the
rejection path. UNVERIFIED, not passed.

## Not examined
Rate limiting under sustained load — no load environment. Deferred to /qa-gate.
```

## Standing checks beyond the allocation

Independent of what G2 allocated, confirm at G4:

- **Audit events** the story required are actually emitted (AU-2), asserted in a test
- **Errors do not disclose** internal structure, stack traces, or identifiers
- **No new attack surface** beyond what G2 anticipated — new endpoints, parameters,
  dependencies
- **Personal data handling** matches what the design stated
- **Threat model updated** if the design changed during build
- **Dependencies verified** to exist and be the intended package (AIC-7)

## The honesty rules

- Say **"unverified"**, never "passed", for anything you could not check either way.
- **Report what you did not examine.** Overstated coverage is how gaps survive.
- **Never mark a control satisfied to unblock a merge.** A false claim is worse than an open
  finding.
- **Do not inflate severity to force attention.** It spends the credibility that makes your
  blocks effective, and the next real Critical gets treated like the last inflated one.
- **Do not soften a finding because it is inconvenient.**

## Blocking authority

Critical and High findings **block release**. Not overridable by the Product Owner, not by
schedule — only by documented, time-boxed, human-approved risk acceptance with a POA&M entry
(`docs/templates/security-exception.md`).

Escalate any Critical or High to a human **immediately**, not in the gate summary.

## Controls

SA-11 (developer testing and evaluation) · SA-11(1) static analysis · SA-11(2) threat and
vulnerability analysis · AC-3 · AC-6 · SI-10 · SI-7 · AU-2 · CA-2 · RA-5.
