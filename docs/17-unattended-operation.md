# 17 — Running the Sprint Runner Unattended

**Policy:** `docs/18-automation-policy.md` · **Check:** `./keel sprint --preflight` · **Controls:** AIC-11, AC-5, CM-3

## The precondition

**Do not schedule a run you have never watched finish.**

This runner has not yet completed an end-to-end run. This project's record with
first executions is: nine defects on `bootstrap.sh`, four on the dashboard, two on the
sprint runner's own branch handling. Unattended is where you put something *after* it has
earned it, not instead of earning it.

Run `./keel sprint --one sprint/inbox/something-small.md` while watching. Then schedule.

The *refusal* path is tested — preflight and `--unattended` both correctly decline when a
parameter is unmet. The *success* path is not. That asymmetry is the whole risk.

## The agreed parameters come first

Five parameters govern any automated run — CLI credential, dev-ready stories only, a
non-prod environment, a human gate on what is running there, and all three test suites
enabled. They live in `automation-policy.yml` and are documented in
**`docs/18-automation-policy.md`**. Read that before this.

```
./keel sprint --preflight
```

Every failing line is a precondition, not a warning. `--unattended` re-checks them at start
of run and refuses if any is unmet.

## It runs locally, via the CLI — there is no CI option

The scheduled GitHub Actions runner has been **removed**, not disabled. P1 prohibits a
standing `ANTHROPIC_API_KEY`: a long-lived credential running unattended with no session
boundary is a worse risk than the isolation CI would have bought. A workflow that must never
be enabled is a trap, and a disabled trap is still a trap.

Two consequences you are accepting:

- **The machine has to be awake.** Sleep is the most common reason a "scheduled" job never
  ran, and it fails silently.
- **The run inherits your local session and filesystem** rather than a fresh ephemeral
  runner. Isolation is weaker than CI's. That is the trade P1 makes deliberately.

Billing follows the credential: the CLI login uses your existing Claude subscription, so if
you already pay for it, a local run likely costs nothing extra.

## Scheduling it (Windows Task Scheduler)

```powershell
# Run nightly at 02:00. Adjust the path.
$action  = New-ScheduledTaskAction -Execute "C:\Program Files\Git\bin\bash.exe" `
           -Argument "-lc './keel sprint --unattended >> sprint/done/nightly.log 2>&1'" `
           -WorkingDirectory "C:\Users\tgb_\Documents\Projects\Coders"

$trigger = New-ScheduledTaskTrigger -Daily -At 2am

# Wake the machine, and do not start if on battery.
$settings = New-ScheduledTaskSettingsSet -WakeToRun `
            -DontStopIfGoingOnBatteries -StartWhenAvailable `
            -ExecutionTimeLimit (New-TimeSpan -Hours 1)

Register-ScheduledTask -TaskName "keel-sprint" -Action $action `
  -Trigger $trigger -Settings $settings -Description "Nightly keel sprint runner"
```

`-WakeToRun` matters: without it a sleeping machine simply skips the run, silently.
`-StartWhenAvailable` catches up a missed run rather than waiting a whole day.

macOS/Linux equivalent:
```cron
0 2 * * *  cd /path/to/keel && ./keel sprint --unattended >> sprint/done/nightly.log 2>&1
```

## What bounds an unattended run

| Bound | Value | Why |
|---|---|---|
| Items per run | **3** (`max_items_per_run`) | An inbox of twelve is an unbounded bill arriving at 3am |
| Wall clock | 1 h (`-ExecutionTimeLimit`) | A runaway loop costs money |
| Protected paths | Branch **abandoned** if it touched a control | A control change must be a deliberate human act |
| Gate entry | Starts at **G2** — never crosses G0/G1 | Deciding *what* to build stays human (P2) |
| Deploy target | Only the environment `automation-policy.yml` names | Production stays blocked by `guard-bash.sh` (P3) |
| Tests | Unit + functional + security, **re-run by the runner** | An agent's "tests pass" is an assertion, not evidence (P5) |
| Merge | Never | AC-5 / POAM-008 |

If the cap defers work, the run **says so** rather than truncating silently.

## What you read in the morning

`sprint/done/last-run.md` — processed count, deliberate stops, still-queued count, and the
open PRs awaiting you.

Then `./keel dash` for the fuller picture, and the PRs themselves.

**A `*.BLOCKED.md` file is a success, not a failure.** It means the runner hit something a
human should decide — a High finding, a needed credential, scope creep, or a blocking
question with no safe default — and stopped instead of guessing.

## Honest risks of unattended operation

- **Cost.** Each story is a full agent session. Three complex ones overnight is meaningful
  usage. Start with `max_items_per_run: 1`.
- **Nobody sees a stuck run until morning.** The timeouts bound it, but a run that dies at
  02:05 means a wasted night. The summary file is the mitigation, not a fix.
- **An autonomous PR's self-review is written by the agent that wrote the code** — one
  reasoning chain produced both, which makes it the weakest form of the POAM-008
  compensating control. Give overnight PRs *more* scrutiny in the morning, not less.
- **Silence is not success.** If the summary says three processed and you merge three PRs
  without reading them, the automation has replaced your judgement rather than your typing.
  That is the failure mode this whole platform exists to prevent.
