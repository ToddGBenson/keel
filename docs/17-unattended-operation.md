# 17 — Running the Sprint Runner Unattended

**Check first:** `./keel sprint --preflight` · **Controls:** AIC-11, AC-5, CM-3

## The precondition

**Do not schedule a run you have never watched finish.**

This runner has not yet completed an end-to-end run. This project's record with
first executions is: nine defects on `bootstrap.sh`, four on the dashboard, two on the
sprint runner's own branch handling. Unattended is where you put something *after* it has
earned it, not instead of earning it.

Run `./keel sprint --one sprint/inbox/something-small.md` while watching. Then schedule.

## Two places it can run — the cost difference is the deciding factor

| | GitHub Actions | Local (Task Scheduler / cron) |
|---|---|---|
| Machine must be awake | No | **Yes** |
| Billing | **`ANTHROPIC_API_KEY` — per-token API billing, separate from a Claude subscription** | Your existing `claude` login (subscription) |
| Logs | Retained, artifact-uploaded | Wherever you redirect them |
| Isolation | Fresh ephemeral runner | Your machine, your filesystem |
| Secrets | Repo secret, scoped to the job | Your local session |

**If you already pay for Claude, the local path likely costs you nothing extra and the CI
path bills separately per token.** That is usually the deciding factor, not the technology.

If you go local, the machine has to be awake at the scheduled time. Sleep is the most common
reason a "scheduled" job never ran.

## Option A — GitHub Actions

1. Add `ANTHROPIC_API_KEY` as a repository secret (Settings → Secrets and variables →
   Actions). **You do this** — agents never handle credentials (AIC-5).
2. Set the cron in `.github/workflows/sprint.yml`. Default is weekly; `'0 6 * * 1'`.
   For nightly at 02:00 your time, convert to UTC and use e.g. `'0 7 * * *'`.
3. Trigger once manually first: Actions → Sprint Runner → Run workflow.

Without the key the workflow exits early with an explanation rather than failing obscurely.

## Option B — Local, overnight (Windows Task Scheduler)

```powershell
# Run nightly at 02:00. Adjust the path.
$action  = New-ScheduledTaskAction -Execute "C:\Program Files\Git\bin\bash.exe" `
           -Argument "-lc './keel sprint >> sprint/done/nightly.log 2>&1'" `
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
0 2 * * *  cd /path/to/keel && ./keel sprint >> sprint/done/nightly.log 2>&1
```

## What bounds an unattended run

| Bound | Value | Why |
|---|---|---|
| Items per run | **3** (`--max N`, or `KEEL_SPRINT_MAX`) | An inbox of twelve is an unbounded bill arriving at 3am |
| Wall clock | 45 min (CI) / 1 h (Task Scheduler) | A runaway loop costs money |
| Protected paths | Branch **abandoned** if it touched a control | A control change must be a deliberate human act |
| Token scope (CI) | No `packages`, `deployments`, `id-token` | It *cannot* deploy — not merely told not to |
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

- **Cost is the real one.** Each description is a full agent session. Three complex ones
  overnight is a meaningful bill. Start with `--max 1`.
- **Nobody sees a stuck run until morning.** The timeouts bound it, but a run that dies at
  02:05 means a wasted night. The summary file is the mitigation, not a fix.
- **An autonomous PR's self-review is written by the agent that wrote the code** — one
  reasoning chain produced both, which makes it the weakest form of the POAM-008
  compensating control. Give overnight PRs *more* scrutiny in the morning, not less.
- **Silence is not success.** If the summary says three processed and you merge three PRs
  without reading them, the automation has replaced your judgement rather than your typing.
  That is the failure mode this whole platform exists to prevent.
