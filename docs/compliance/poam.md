# Plan of Action and Milestones (POA&M)

**Owner:** Compliance Officer · **Control:** CA-5 · **Reviewed:** weekly, formally quarterly

The register of known gaps. Its value is entirely in being **honest and current** — a POA&M
that lists only comfortable findings is worse than none, because it produces documented false
assurance that everything else relies on.

## Entry format

| Field | Notes |
|---|---|
| ID | `POAM-<n>` |
| Weakness | What is actually wrong, specifically |
| Source | Assessment, scan, pentest, incident, red-team, self-identified |
| Control(s) | 800-53 / AIC reference |
| Risk | Critical / High / Medium / Low, with reasoning |
| Affected | Systems, components, data |
| Remediation plan | What will be done |
| **Owner** | A named person, never a team |
| Resources required | Be honest — "none" is usually false and hides the real blocker |
| Milestones | Dated intermediate steps |
| Scheduled completion | Per severity SLA |
| Status | Open / In progress / Risk accepted / Completed |
| Compensating control | What reduces exposure meanwhile |
| Evidence of closure | Required to close — a rescan, a test, an assessment result |

## Register

| ID | Weakness | Control | Risk | Owner | Due | Status |
|---|---|---|---|---|---|---|
| POAM-001 | Agent write-scope boundaries are prompt-enforced, not tool-enforced | AIC-3, AC-6 | Low | *unassigned* | review quarterly | Open — compensating controls in place |
| POAM-002 | Secret guard used keyword matching; blocked all security tooling | AIC-5, IA-5 | Medium | *unassigned* | 2026-08-07 | **Closed** — fixed + regression test |
| POAM-003 | Secret guard matched its own patterns; blocked its own repair | AIC-5 | Medium | *unassigned* | 2026-08-07 | **Closed** — fixed + regression test |
| POAM-004 | Without `jq`, guard scanned `old_string`; blocked removing a secret | AIC-5, IA-5 | **High** | *unassigned* | 2026-08-07 | **Closed** — fixed |

### POAM-002/003/004 — Secret guard defects found by dogfooding

**Source.** Self-identified 2026-08-07 while writing `scripts/install-hooks.sh`. The guard
blocked the write, then blocked its own repair, then blocked the repair of the repair. Three
distinct defects surfaced in sequence.

**POAM-002 — keyword matching (Medium).** `guard-write.sh` matched bare keywords such as the
AWS secret-key parameter name. Those strings appear legitimately in secret-*detection* code:
this hook, `scripts/install-hooks.sh`, `.github/workflows/security.yml`, and the
`scanner-triage` skill. The control blocked all security tooling work in the repo.
**Fixed:** named credentials now require an assignment *and* a plausible value; opaque token
formats remain value-shaped.

**POAM-003 — self-matching patterns (Medium).** The detection patterns matched their own
source text, so any edit to the hook was blocked — **including the fix for POAM-002.** A
control that cannot be repaired through the normal path forces either a bypass or an
exception, and both are worse than the original defect.
**Fixed:** `[x]` character classes match identically but cannot self-trigger. Preserved with
a comment so a future edit does not reintroduce it.

**POAM-004 — fallback scanned removed text (High).** `jq` is not installed in this
environment. The fallback set `content="$payload"`, i.e. the *entire* hook payload including
`old_string`. The guard therefore scanned the text being **removed** — meaning **an edit that
takes a secret out of a file was blocked.** That is precisely the operation you most need to
perform after a leak, and the guard forbade it while appearing to protect you.
Rated High because it makes remediation impossible during exactly the incident it exists for.
**Fixed:** Python fallback extracting only new content; if no parser is available the hook
now **fails open with a warning** rather than blocking every edit, since CI secret scanning
is authoritative.

**Evidence of closure.** `.claude/hooks/selftest.sh` — 20 assertions, including four
regression tests named for these defects. Run: 20 passed, 0 failed.

**Lesson recorded.** Three of these were only findable by *using* the control, not reading
it. This is the `control-assessment` skill's central claim demonstrated on our own
infrastructure: **test beats examine.** A control that examines well and fails when exercised
is the finding that matters. `selftest.sh` is now the standing test, and it runs at
quarterly assessment.

---

### POAM-001 — Agent write-scope is not technically enforceable

**Weakness.** `docs/compliance/ai-inventory.md` § Section B assigns each agent an expected
write scope (e.g. `product-owner` writes issues and product docs, not source). That boundary
exists only in the agent's role prompt. A confused or adversarial model can write outside it.

**Source.** Self-identified during platform build, 2026-08-07.

**Verification performed.** Claude Code agent frontmatter grants tool *types* (`Write`,
`Edit`), not path scopes. `settings.json` permissions are project-wide, not per-agent. The
`PreToolUse` hook payload was probed directly and carries `cwd`, `session_id`, `tool_name`,
`tool_input`, `permission_mode`, `prompt_id`, `tool_use_id`, `transcript_path` — and **no
field identifying the acting subagent**. No enforcement layer currently available can scope
writes per agent.

**Risk: Low.** The high-consequence boundaries — approve, merge, push, production, secrets —
*are* enforced by `guard-bash.sh`, `settings.json` deny rules, and branch protection. What
remains unenforced is role hygiene: the wrong agent authoring the right artifact. That is
caught downstream by human review before anything merges.

**Compensating controls.**
1. G3 review by a non-author — a human sees every source diff before merge
2. CODEOWNERS routes source paths to engineering review regardless of author
3. AI-authorship declaration (AIC-6) names the producing agent on every PR
4. Monthly agent audit (AIC-12) samples merged PRs for role/artifact mismatch

**Remediation plan.** No action available today. Re-evaluate each quarter against Claude Code
releases; if agent identity becomes available to hooks, implement path scoping in
`guard-write.sh` and upgrade the enforcement table in `docs/11-ai-agent-controls.md`.

**Why this is recorded rather than quietly tolerated.** The platform's own rule (PD-7) is
that a false compliance claim is worse than an open finding. The inventory originally implied
this boundary was enforced; it is not. A documented weak control is defensible at assessment.
An overstated one is the finding that costs credibility on every other control in the map.

---

## Rules

**Every Other-Than-Satisfied assessment result becomes an entry.** No exceptions, including
for gaps discovered close to a release.

**Due dates come from severity** (`docs/10-definitions.md`): Critical 7d · High 30d ·
Medium 90d · Low next planned cycle.

**Closure requires evidence of remediation** — a passing rescan, a new test, a reassessment.
Closing on assertion is how a POA&M becomes fiction.

**Risk acceptance is not closure.** It is a status, with a human approver, an expiry date, a
named compensating control, and a review. Indefinite acceptance is not acceptance; it is a
decision to carry the risk permanently, and it should be written that way if that is what is
meant.

## The three signals to watch

1. **Entries past due** — report first, every time.
2. **Entries extended more than once** — that is not a schedule problem. It is a resourcing
   or a will problem, and naming it as one is the Compliance Officer's job.
3. **Entries closed without evidence** — audit a sample of closures every quarter. This is
   where a register quietly stops being true.

## Escalation

Past-due Critical or High → escalate to a human immediately, do not wait for the weekly
review. Twice-extended entries → escalate with the resourcing question stated plainly.
