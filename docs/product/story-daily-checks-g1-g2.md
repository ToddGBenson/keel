# Story 1 — Daily health and security posture report

**From:** `intake-daily-checks.md` · **Gates:** G1 (Ready) + G2 (security-relevant)

## Narrative
As someone running a home machine, I want one daily report of its health and security
posture, so that I notice a filling disk, a stale backup, or a disabled firewall before it
matters.

## Acceptance criteria

```gherkin
# happy path
Given the program runs on a supported OS
When I invoke it
Then I get a report listing every check with PASS / WARN / FAIL / SKIPPED
And the process exit code is 0 when nothing FAILED

# thresholds (U5) — numbers, not vibes
Given disk usage is 86% and the threshold is 85%
Then that check reports WARN with the actual figure

# unprivileged degradation (U6) — the control
Given a check needs privileges the process does not have
Then it reports SKIPPED with the reason
And it is NEVER reported as PASS

# safety (U2) — the control that matters most
When the program runs
Then it sends no packets to any host other than this machine
And it makes no outbound network connection

# machine-readable
Then a JSON report is written with a schema version and a UTC timestamp
```

## Non-functional criteria
- **Safety:** read-only. No writes outside its own report file; no remediation.
- **No egress:** no outbound connections. The report contains local hostnames/IPs and
  **must not leave the machine** (privacy).
- **Unprivileged:** runs as a normal user; missing privilege ⇒ SKIPPED, never PASS.
- **Fast:** completes in < 10 s so a daily schedule is unobtrusive.
- **Deterministic exit:** `0` = no failures, `1` = at least one FAIL. Cron-friendly.

## G2 — Threat model (skill: `threat-modeling`)

**Scope:** a local, unprivileged, read-only reporter. **Assets:** the host's configuration
detail and the report itself.

| # | Threat | STRIDE | Disposition | Control → component | Negative test |
|---|---|---|---|---|---|
| T1 | Program becomes a network scanner and trips IDS / AUP | **D** | **Eliminate** | No socket API is imported at all; inventory reads the OS neighbour table only | Test asserts the module imports no network library and opens no socket |
| T2 | Report leaks host detail off-machine | **I** | **Mitigate** | No egress; report written to a local path only | Test asserts no outbound connection is attempted |
| T3 | A privileged check silently reports PASS when it could not run | **S** (false assurance) | **Mitigate** | `SKIPPED` is a distinct status; `PASS` requires an actual observation | Test: an unavailable probe yields SKIPPED, never PASS |
| T4 | Shell probe output is interpolated unsafely (command injection) | **E** | **Mitigate** | `subprocess` with an argument **list**, `shell=False`, fixed argv — no user input reaches a command | Test asserts `shell=True` appears nowhere |
| T5 | A hanging probe stalls the daily run forever | **D** | **Mitigate** | Every subprocess call has a timeout; timeout ⇒ SKIPPED | Test: a timing-out probe degrades rather than hangs |
| T6 | Report path is attacker-controlled → arbitrary write | **T** | **Mitigate** | Path resolved and confined; refuses to write outside the report directory | Test: `../` escape is refused |

**No accepted risks. No undispositioned threats.**

**SA-8 as applied:** *economy of mechanism* — no network stack, so a whole class of risk is
eliminated rather than mitigated; *fail secure* — an unknown result is SKIPPED, never PASS;
*least privilege* — never asks for root.

**G1: READY** · **G2: PASS**
