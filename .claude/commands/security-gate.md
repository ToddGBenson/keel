---
description: Security verification for G4 — verify allocated controls actually exist and work, triage scanner output, produce evidence
argument-hint: <issue or PR number>
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, WebSearch, Task
---

# G4 — Security Verification: `$ARGUMENTS`

Delegate to the `security-engineer` agent. Per `docs/05-verification.md`.

## Skills — load these first

- **`control-verification`** — the four-step method (find implementation → find negative test
  → adversarial read → record). This is the core of the gate.
- **`scanner-triage`** — reachability analysis, severity-from-context, suppression rules.
- **`evidence-writing`** — the verified / unverified / not-examined structure.

## This is not "run the scanners"

Scanners are the floor. The gate's actual work is verifying that the controls the threat
model **allocated** are present and effective — that is what `control-verification` carries,
and it is the difference between a gate and a green badge.

## Scan coverage to confirm ran and to read

SAST (SA-11(1)) · SCA / dependency vulnerabilities (RA-5, SR-3) · secret scan over full
history (IA-5) · IaC and configuration (CM-6, CM-7) · container image (RA-5, SR-11) · SBOM
generated and diffed (CM-8, SR-4) · license compliance · DAST if staging-deployed (SA-11(8)).

**Read the results.** A green badge on a job that scanned nothing is the most common form of
false assurance in a pipeline.

## Also check

- Threat model updated if the design changed during build
- No new attack surface introduced beyond what G2 anticipated
- Audit events from the story's criteria actually emitted (AU-2)
- Personal data handling matches what the design stated
- Errors do not disclose internal structure
- Dependencies verified to exist and be the intended package (AIC-7)

## Output

```
G4 SECURITY RESULT: PASS | FAIL | PASS WITH FINDINGS

Controls verified:
  AC-3 object authz    → DraftAuthorizer:47   neg. test api_test:212   ✅
  SI-10 input valid.   → schema.py:31         property test:88         ✅
  AU-2 audit event     → NOT FOUND — story required audit.draft.restored ❌

Findings:
  HIGH   drafts.py:88 — non-transactional quota check; concurrent writes both pass.
         Reachable by any authenticated user. Remediate ≤30d.
  MEDIUM ...
Scanner triage: 14 results → 2 true positive, 11 false positive (rationale + expiry
  recorded), 1 accepted (POA&M-024, expires 2026-10-01)
Not checked: runtime behavior under load — deferred to /qa-gate
```

## Rules

- **Never write evidence you did not produce.** Never mark a control satisfied to unblock a
  merge. A false compliance claim is worse than an open finding.
- Say **"unverified"** rather than "passed" when you could not verify either way.
- Report what you did **not** check. Overstated coverage is how gaps survive.
- Critical and High findings **block**. That block is not overridable by the Product Owner or
  by schedule — only by documented, time-boxed, human-approved risk acceptance.

## Then

Write to `evidence/<issue>/g4/security/`. Escalate any Critical or High to a human
immediately. Do not wait for the gate summary.
