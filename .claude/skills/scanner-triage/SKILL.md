---
name: scanner-triage
description: Turn raw SAST, SCA, IaC, secret, and container scanner output into dispositioned findings. Use when reviewing scan results, deciding whether a result is a true positive, assigning severity, writing or auditing a suppression, or when a pipeline is failing on scanner noise. Covers reachability analysis and severity-from-context.
---

# Scanner triage

Consumers: `security-engineer`, `/security-gate`, `process/gates/g4-verified.md`,
`.github/workflows/security.yml`.

## Scanner output is not findings

A scanner emits *results*. A finding is a result that has been shown to be real, reachable,
and consequential **here**. Handing a team 400 raw results is not security work; it is
transferring the actual work while appearing to have done it.

Every result gets exactly one disposition.

```
result
  │
  ├─ Is the pattern actually present?  ── no ──▶ FALSE POSITIVE
  │        yes                                    (rationale + expiry required)
  ├─ Is the code reachable?            ── no ──▶ FALSE POSITIVE (unreachable)
  │        yes                                    or NOT EXPLOITABLE — say which
  ├─ Is it exploitable in our context? ── no ──▶ ACCEPTED RISK
  │        yes                                    (human approval + POA&M + expiry)
  └──────────────────────────────────────────▶ TRUE POSITIVE
                                                 (severity + SLA + issue)
```

## Reachability — the step most often skipped

A CVE in a dependency you ship is not automatically a finding. Ask, in order:

1. **Is the vulnerable function called?** Many CVEs live in one module of a large library. If
   you import `library.parse` and the flaw is in `library.serve`, say so — with the evidence
   (a call-graph query, a grep, the absence of the import).
2. **Can attacker-controlled input reach it?** A deserialization flaw in a code path that
   only ever handles internally-generated data is a different risk than one on the request
   boundary.
3. **What preconditions does exploitation need?** Authentication? A specific role? Local
   access? Each precondition that must hold is a genuine reduction — but only if it is
   *enforced*, not merely typical.
4. **Is there a compensating control in front of it?** A WAF rule is not a fix; a validated
   allowlist at the boundary might be.

Record the reasoning. A reachability judgment you cannot reconstruct in six months reads as
arbitrary to an assessor, and it will be re-litigated every quarter.

## Severity from context, not from the base score

The vendor's CVSS base score assumes a generic deployment. You are not generic.

| Raises it here | Lowers it here |
|---|---|
| Unauthenticated path | Requires admin privilege already |
| Internet-facing | Internal-only, network-segmented |
| Handles personal or regulated data | Synthetic or public data |
| Known exploited (CISA KEV) | No public exploit, theoretical |
| Our own code, not a dependency | Vendor patch already staged |

**Deviating from the vendor score is correct and expected.** Record the deviation and the
reason. What is *not* acceptable is silently accepting the base score and calling that
triage.

**Never inflate severity to force attention.** It spends the credibility that makes your
blocks work, and the next genuine Critical gets treated like the last inflated one.

SLAs: Critical 7d · High 30d · Medium 90d · Low next cycle. Critical and High block release.

## Writing a suppression that survives audit

A suppression is a claim that a control does not apply here. It needs to be defensible a year
later by someone who was not present.

```python
# nosec B608 - query is parameterised via SQLAlchemy bindparams below; the scanner
# does not follow the builder. Verified by test_no_raw_interpolation. See #318.
# expires: 2026-12-01
```

Required, without exception:
- **What the scanner thinks is wrong**
- **Why it is not** — specific, and pointing at the thing that makes it not wrong
- **An issue reference**
- **An expiry date** — `expires: YYYY-MM-DD`

`security.yml`'s suppression audit fails the build without an issue ref and an expiry. That
job exists because unjustified suppressions are how a scanner quietly stops being a control —
one reasonable-looking `# nosec` at a time, until the scan is green and meaningless.

**Blanket suppressions fail G4.** A file-level or rule-level disable is not a triage decision;
it is opting out of the control. If a rule genuinely does not apply to this codebase, disable
it *in the scanner configuration*, in a reviewed PR, with the reasoning — visibly, not in a
comment nobody reads.

Suppressions are reviewed quarterly. An expired one is a finding.

## Fail on new, not on total

This is the design decision that determines whether the pipeline is a control or decoration.

Gating on the absolute finding count in any real codebase means the pipeline is red on day
one and stays red. Within two sprints everyone has learned to click through it, and at that
point it detects nothing while still showing green on the assessment.

Gate on the **delta the PR introduces**. Drive the existing backlog down on SLA through the
POA&M, where it has owners and dates.

## Batch triage without losing rigour

When facing hundreds of results:

1. **Group by rule, not by file.** One rule usually produces one *kind* of result; judge the
   rule's applicability once, then confirm the outliers.
2. **Triage the highest severity first**, but do not stop there — a cluster of Mediums in one
   component is often a design problem worth more than a lone High.
3. **Sample within a group** and check whether the sample generalises before dispositioning
   the group. Say in the record that you sampled, and how many.
4. **Never mass-suppress to get green.** If a group is genuinely all false positives, fix the
   scanner configuration.

## Writing the finding

So a developer can act without asking you anything:

> **HIGH — `drafts.py:88` — non-transactional quota check**
> The count is read and the write performed outside a transaction. Two concurrent autosaves
> at quota−1 both pass, exceeding the 5 MB limit.
> **Reachable:** any authenticated user, no special preconditions.
> **Reproduce:** parallel POST `/drafts` with the user at 4 of 5 drafts.
> **Fix:** take a row lock on the user quota row, or enforce with a DB constraint.
> **SLA:** 30 days.

A finding a developer cannot act on is a complaint.

## Controls

RA-5 (vulnerability monitoring) · RA-7 (risk response) · SI-2 (flaw remediation) ·
SA-11(1) (static analysis) · CA-5 (POA&M) · SR-3 (supply chain).
