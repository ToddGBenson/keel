# Runbook — self-hosted Actions runner

**Why a fork might need this.** GitHub-hosted runners are billed. When a payment fails or a
spending limit is reached, every job refuses to start with:

> The job was not started because recent account payments have failed or your spending limit
> needs to be increased.

Self-hosted runners do not consume included minutes, so the PR governance gate keeps working.
That is the only reason keel uses one. If your hosted runners work, **do not do this** — you
are taking on host security for no benefit.

Related: `docs/06-cicd.md` (what runs where), POAM-014.

---

## What runs on it, and what deliberately does not

keel's delivery pipeline is Concourse. It builds, tests, scans and records evidence, and it
has **no pull-request concept at all**. The runner exists for the one thing Concourse cannot
do: read the pull request — issue linkage, AI-authorship declaration, the DoD checklist, and
the self-review artifact that is POAM-008's compensating control.

**A green PR Governance check does not mean the code is good.** It means the process around
the change is intact. Tests and scans run in Concourse, after merge.

---

## Security — read before installing

The runner executes workflow code on your host. On the keel box that host also runs Concourse
(`localhost:8080`) and Vault (`localhost:8200`), so a workflow step is a short reach from both.

**Non-negotiable:**

1. **Never run fork PRs on it.** Every job carries
   `github.event.pull_request.head.repo.full_name == github.repository`. `pull_request` runs
   the *base* repository's workflow file, but the steps still check out and can execute the
   *fork's* code. This is the standard self-hosted runner compromise and it is not theoretical.
2. **Never put Vault or Concourse credentials in Actions secrets.** The runner does not need
   them. Concourse reads Vault directly; nothing in Actions should.
3. **Repository-scoped, not org-scoped.** An org runner is reachable by every repository in
   the org, including ones with weaker review.
4. **Run it as an ordinary user, not as an administrator or a service account.**

---

## Install (Windows, non-administrator)

Verify the download against the SHA256 GitHub publishes in the release notes. This is a
supply-chain control (SR-3, SR-11), not a formality — the runner executes with your privileges.

```powershell
$dir = "$HOME\actions-runner-keel"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$ver = '2.336.0'   # check github.com/actions/runner/releases/latest
$zip = Join-Path $dir "actions-runner-win-x64-$ver.zip"
Invoke-WebRequest "https://github.com/actions/runner/releases/download/v$ver/actions-runner-win-x64-$ver.zip" -OutFile $zip

# The expected hash is in the release body, between the SHA marker comments.
$expected = (gh api repos/actions/runner/releases/latest --jq '.body' |
             Select-String 'BEGIN SHA win-x64 -->([0-9a-f]{64})').Matches.Groups[1].Value
if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $expected.ToUpper()) { throw 'HASH MISMATCH' }

Expand-Archive $zip -DestinationPath $dir -Force; Remove-Item $zip
```

Register it. The token is short-lived (about an hour) and must not be echoed or committed:

```powershell
Set-Location $dir
$tok = gh api -X POST repos/<owner>/<repo>/actions/runners/registration-token --jq '.token'
.\config.cmd --unattended --url https://github.com/<owner>/<repo> --token $tok `
             --name <host>-local --labels keel --work _work --replace
$tok = $null
```

Then set `KEEL_RUNNER_LABELS` so the workflows target it. Forks that leave the variable unset
get `ubuntu-latest`, so this is the only switch:

```powershell
gh variable set KEEL_RUNNER_LABELS --body '["self-hosted","keel"]'
```

---

## The `shell: bash` trap on Windows

**Symptom.** A step with `shell: bash` fails immediately with:

```
WSL (…) ERROR: CreateProcessCommon:800: execvpe(/bin/bash) failed: No such file or directory
```

**Cause.** `C:\WINDOWS\system32\bash.EXE` is the WSL launcher, and it shadows Git Bash on
`PATH`. If no WSL distribution is installed, every `bash` step dies. Git for Windows installs
only `Git\cmd` on `PATH` by default, so `Git\bin\bash.exe` is never found.

**Fix on the host, not in the workflows.** `shell: bash` is the portable thing to write and
every fork inherits those files. Launch the runner through a wrapper that fixes `PATH`:

```bat
@echo off
set "PATH=C:\Program Files\Git\bin;C:\Program Files\Git\usr\bin;%PATH%"
cd /d "%~dp0"
call "%~dp0run.cmd"
```

Invoke `run.cmd` by full path — on a host with `NoDefaultCurrentDirectoryInExePath` set, a bare
`call run.cmd` fails even after `cd`.

---

## Keeping it running

`config.cmd --runasservice` needs administrator rights. Without them, register a logon task —
it survives reboot and does not need elevation:

```powershell
$dir = "$HOME\actions-runner-keel"
Register-ScheduledTask -TaskName 'keel-actions-runner' -Force `
  -Action  (New-ScheduledTaskAction -Execute "$dir\run-keel.cmd" -WorkingDirectory $dir) `
  -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME) `
  -Principal (New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive) `
  -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
             -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 `
             -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable)
```

**A runner that is offline does not fail the gate — it leaves the check pending forever**, and
a required check that never reports blocks merges rather than allowing them. That is the safe
direction, but it looks like a hung PR rather than a stopped runner, so check here first:

```powershell
gh api repos/<owner>/<repo>/actions/runners --jq '.runners[] | "\(.name) \(.status) busy=\(.busy)"'
```

---

## Three things, or none of it takes effect

1. The `on: pull_request` trigger in `.github/workflows/pr-governance.yml`
2. A runner that is **online**
3. The job names in branch protection's required status checks

Any one missing and the gate is decorative. That is precisely the state POAM-014 describes, and
it is easy to arrive at by fixing two of the three.

---

## Removing it

```powershell
Unregister-ScheduledTask -TaskName 'keel-actions-runner' -Confirm:$false
Set-Location "$HOME\actions-runner-keel"
$tok = gh api -X POST repos/<owner>/<repo>/actions/runners/remove-token --jq '.token'
.\config.cmd remove --token $tok
```

**Remove the required status checks from branch protection first**, or every PR blocks on a
check that can no longer report.
