# G4 — Verified

**Approvers:** QA Engineer + Security Engineer (+ AI Risk Officer if AI-relevant) — each
**independently**, each recording pass or fail with evidence
**Commands:** `/qa-gate`, `/security-gate`, `/ai-gate`
**Reference:** `docs/05-verification.md` · **Controls:** SA-11 (+1, 2, 5, 8), CA-2, CA-7,
CA-8, RA-5, SI-2, CM-4, CM-8, AU-2, AI RMF MEASURE 2

Three independent verdicts, not one combined sign-off. Any fail blocks.

---

## Scope: per story, or per epic

G4 runs over **one story** by default. It may instead run **once over an epic's stories as a
batch** — the same items, assessed across a group (ADR-0002).

**Eligibility is not a judgement call. Run the check:**

```bash
bash scripts/check-batch-eligibility.sh <epic-number>
```

It refuses the batch if any story carries `security-relevant` or `ai-relevant`, or if the epic
exceeds 5 stories. A refused batch means those stories are verified **individually**, at full
ceremony — it does not mean verify them less.

**Removing a risk flag to pass this check is falsifying a triage decision (PD-7).** If a flag
looks wrong, that is a re-triage on the issue with a reason recorded, not a label deletion in
service of a green gate.

When running batched, three things change and nothing else does:

- **Item 15** (adversarial read) is performed over the **combined** surface. This is the point
  of batching — the question a per-story review structurally cannot ask is *what did these
  stories do to each other?* An endpoint added in story 3 consuming a field left unvalidated by
  story 1 is invisible when each is read alone. Look at the seams first.
- **Item 16/17** (scan results) covers everything accumulated since the epic opened, triaged
  once rather than N times.
- **Item 1** (traceability) must still resolve **per story** — every AC of every story has its
  test and result. A batch verdict that cannot be decomposed back to individual stories is not
  evidence, it is an average.

Everything in Parts A–C is assessed as written. The gate did not get smaller; its unit did.

---

## Part A — QA verification

| # | Item | Evidence |
|---|---|---|
| 1 | Traceability matrix complete: **every AC has a test and a result** | `traceability.md` |
| 2 | No test with no AC left unresolved (dead weight or undocumented requirement) | Matrix |
| 3 | Test quality audited — tests would **fail if the implementation were removed** | Audit note |
| 4 | Authorization tested at **integration** level, not unit-mocked | Test files |
| 5 | Persistence, transactions, migrations tested against the **real engine** | Test files |
| 6 | Performance NFR asserted under representative load **and data volume** | Load test run |
| 7 | Reliability verified under **deliberate** dependency failure | Test evidence |
| 8 | **Rollback actually exercised**, not assumed | Rehearsal record |
| 9 | Observability outputs confirmed present | Test assertion |
| 10 | Accessibility: automated scan **plus** a real keyboard/screen-reader pass | Scan + notes |
| 11 | Exploratory charter run, time-boxed, findings filed | Charter + notes |
| 12 | Any flaky test **filed as a defect**, not retried away | Issue link |

---

## Part B — Security verification

| # | Item | Evidence |
|---|---|---|
| 13 | Every allocated control **located in the code** (file:line) | Verification record |
| 14 | Every allocated control has a **negative-case test proving it denies** | Test files |
| 15 | Adversarial read performed — attempts to reach past each check documented | Verification record |
| 16 | SAST, SCA, secrets, IaC, container scans ran **and the results were read** | SARIF + reports |
| 17 | Every scanner result dispositioned: TP / FP (rationale + expiry) / accepted (POA&M) | Triage record |
| 18 | Severity assigned on realistic exploitability; deviation from CVSS reasoned | Findings |
| 19 | DAST run if staging-deployed | DAST report |
| 20 | SBOM generated and diffed against the previous build | SBOM artifacts |
| 21 | Audit events from the story's criteria confirmed emitted | Test assertion |
| 22 | Threat model updated if the design changed during build | Threat model |
| 23 | **No open Critical or High findings** in scope | Finding register |

---

## Part C — AI verification *(if AI-relevant)*

| # | Item | Evidence |
|---|---|---|
| 24 | AI Impact Assessment from G2 exists and its risk tier is recorded | AIA |
| 25 | Eval suite run; **model, prompt, and eval-set versions recorded** | Eval report |
| 26 | **No regression against baseline** across capability, groundedness, robustness, safety, bias, injection resistance, disclosure, cost/latency | Eval report |
| 27 | Every guardrail has a test proving it **blocks** | Test files |
| 28 | **Model output treated as untrusted input** to every downstream system — never evaled, exec'd, rendered unescaped, or passed to a privileged operation unvalidated | Code review |
| 29 | Tool-call authorization checked server-side against the **user's** rights | Code + test |
| 30 | Red-team run (required at High tier); findings in the normal backlog with SLAs | Red-team report |
| 31 | Human oversight point verified — and the human is shown **enough to decide well** | Design + code |
| 32 | Transparency verified — AI disclosed, limitations stated, contest path exists | UI review |
| 33 | AI inventory updated | `ai-inventory.md` |

---

## Judgment notes

**Item 3** — the check: mentally delete the implementation. Which tests fail? If a plausible
bug leaves them green, they are decorative and they inflate the coverage number.

**Item 13** — if you cannot find the implementation, the control is **not implemented**,
regardless of what the design says.

**Item 17** — a suppression with no rationale is a control failure, and it is reported as one.
Blanket suppressions and bare `# nosec`-style comments fail this gate.

**Item 26** — a regression blocks the merge, exactly like a failing unit test. **A prompt
change is a code change.**

**Item 28** is currently the most under-controlled AI risk in production systems. It is the
SQL-injection lesson relearned. Check it every time.

## The honesty rules

- Say **"unverified"** rather than "passed" for anything you could not verify.
- Report what you did **not** check. Overstated coverage is how gaps survive assessment.
- **Never write evidence you did not produce**, and never mark a control satisfied to unblock
  a merge. A false compliance claim is worse than an open finding — the finding is tracked;
  the claim is a hole nobody knows about.

## Fail conditions

Any AC without a test · any control without a negative-case test · any open Critical or High
finding (security or AI) · any eval regression · any guardrail unverified · a suppression
without rationale · a sign-off asserting verification that was not performed.

## Exit

**Pass (all three)** → release-eligible; evidence in `evidence/<issue>/g4/`.
**Any fail** → back to development with the **specific criterion named**. "Needs more
testing" is not a rejection reason.

Critical and High findings block, and that block is not overridable by the Product Owner or
by schedule — only by documented, time-boxed, human-approved risk acceptance with a POA&M
entry.
