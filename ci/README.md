# Concourse pipeline

Execution for keel's lifecycle. Ported from GitHub Actions — see #42 and
`docs/06-cicd.md`.

This pipeline produces the **evidence** gates are approved against. It does not
approve anything. Gate approval stays a human act recorded in GitHub (PD-2).

---

## What runs where, after the port

> ## ⚠️ READ THIS FIRST — the Concourse check run is the gate; PR Governance is retired
>
> **Read 2026-10-20.** The repository is **private**. GitHub Actions does not start, because of
> billing. `PR Governance` (`.github/workflows/pr-governance.yml`) is `disabled_manually` and
> **retired** (TheHub #60849, option C). Branch protection on `main` requires one approving
> review, linear history and resolved conversations. It requires **no status checks**
> (`required_status_checks: null`), and `enforce_admins` is **off**.
>
> **The decision (2026-10-20): the merge gate is the Concourse check run, `Concourse / keel`.**
> It becomes a **required** status check once TheHub #60580 lands. Concourse builds, tests and
> scans each commit. `verify-artifact` posts the verdict to GitHub through MyKronos, and only
> after every verifying lane has passed on that commit. See
> [`Concourse / keel`](#concourse--keel-the-commit-chains-verdict-on-github-107) below.
>
> **What gates a merge today: a human review, and nothing automated.** The check run lands on
> `main` commits only, so it cannot be required yet. A required context that never arrives on a
> pull request head blocks every merge. Until #60580, Concourse detects a bad change after the
> merge and does not prevent it. That is **POAM-014**, still open at High.
>
> **What retiring PR Governance gives up**, stated rather than implied. It read the PR *body*:
> issue linkage, the AI-authorship declaration, the DoD checklist, and the self-review artifact
> that is POAM-008's compensating control. It also ran dependency review. Nothing reads the PR
> body now. Those checks are reviewer-enforced, and `platform-integrity` (a Concourse job)
> still runs the non-PR half after merge.
>
> *History, because the sequence matters:* on 2026-08-13 the repository went private, Actions
> stopped starting on billing, all ten workflows were disabled and every required check was
> removed — nothing gated a merge at all. The gate was restored on a self-hosted runner (#58).
> That runner was retired on 2026-08-14, the day the repository went public (#63), and
> `PR Governance` ran on hosted runners as three required checks with `enforce_admins` on. The
> repository later went private again. By 2026-10-11 the workflow was disabled and branch
> protection required no checks (POAM-014). This box said otherwise until 2026-10-20.

## keel is a template, not a service

It ships no artifact and has no production environment. What it distributes is **itself**, to
forks, via `scripts/sync-platform.sh` under the contract in `platform/MANIFEST.yml`
(ADR-0004).

Three consequences that change how this pipeline reads:

- **The manifest is the build output.** A template has no build to break, so the failure moves:
  an unclassified path is never delivered to a fork, and no fork can notice a file it was never
  sent. `scripts/validate-manifest.py` runs in `platform-integrity`; when first written it
  found **nine** ungoverned paths, including `keel` itself.
- **A release is a tag, and its blast radius is wider than a deploy.** A bad service deploy
  affects one environment and rolls back in minutes. A bad platform release is fast-forwarded
  into every fork's platform-owned paths, overwriting local edits by design.
  `authorize-release` still refuses to run without a recorded human.
- **Inert lanes are inherited, not dead.** `container-scan`, `build-and-attest` and
  `verify-artifact` do nothing here on purpose. They are what a fork gets on the day it first
  ships an image. Deleting them because the template has no image would be deleting the point.
- **A stub is not an inert lane.** An inert lane runs real tooling and says loudly that it
  found nothing to act on. A stub echoes `ADAPT: ...` and exits 0: a green build that asserts
  nothing. Six of those ran in keel's own pipeline until 2026-10-20 and were removed (TheHub
  #60850). Their stages stay in the scripts as template. See
  [Template lanes keel does not run](#template-lanes-keel-does-not-run).

### Template lanes keel does not run

keel ships these stages to forks (`ci/` is `merge_required` in `platform/MANIFEST.yml`). keel
does not run them, because it has nothing for them to check:

| Stage | Script | What a fork replaces it with |
|---|---|---|
| `STAGE=full-suite` | `ci/scripts/ci-stage.sh` | the slow suite and E2E for critical journeys, as a job `passed:` the fast lanes |
| coverage, in `STAGE=test` | `ci/scripts/ci-stage.sh` | a real coverage gate: a floor plus no drop vs `main`, with the threshold param added in the same change |
| `STAGE=evals`, `STAGE=guardrails` | `ci/scripts/ai.sh` | the eval harness and guardrail suite for an AI feature, with `((anthropic_api_key))` |
| `PERIOD=daily`, `weekly`, `metrics` | `ci/scripts/compliance.sh` | deployed-artifact rescans, drift against an IaC baseline, the retro metrics snapshot |

Each one now **fails** until it is adapted. Before 2026-10-20 each echoed its ADAPT lines and
exited 0, and keel's pipeline ran all of them: `full-suite` sat in the commit chain, so a green
`Concourse / keel` passed through a job that tested nothing, and the `test` job carried
`COVERAGE_THRESHOLD: "80"` that nothing measured. To bring one into a fork's pipeline, add a job
that runs the stage (the deleted job definitions are in this file's git history at
`git show d5db77b:ci/pipeline.yml`), and replace the stage before the first run.

MyKronos did not count any of the six as coverage. Its `ci.py` maps only keel's
`mykronos-*` jobs, and the other jobs report `unknown` there.

## Where things run

Everything is in `ci/pipeline.yml`. There is no second system.

| Concern | Job | Trigger |
|---|---|---|
| Pipeline updates itself from `main` | `set-pipeline` | per commit |
| Build, lint, test | `build` `lint` `test` | per commit + daily |
| **SAST — CodeQL, python + js, GATES on findings** | `sast` | per commit + daily |
| Secrets, SCA, IaC, suppressions | `secrets` `sca` `iac` `suppression-audit` | per commit + daily |
| Container scan | `container-scan` | manual (inert until an image exists; zero builds as of 2026-10-11, see `lane-audit-2026-10-11.md`) |
| Platform / control integrity | `platform-integrity` | per commit + daily |
| Mykronos ingestion | `mykronos-*` | per commit + weekly — running since 2026-09-08 |
| Agent assurance (structural evals, tool-grant drift) | `agent-assurance` | weekly |
| Monthly compliance bundle (tool-grant audit, guard self-test, agent evals) | `compliance-monthly` | weekly, executes days 1-7 |
| SBOM, sign, verify | `build-and-attest` `verify-artifact` | per commit |
| **Release G5** | `release-preflight` → `authorize-release` (`passed:` edge) | **manual only** |

`sast` **gates** — it is the only thing in the system that blocks anything, and it blocks a
build rather than a merge. It fails on CodeQL security findings at severity ≥ medium; quality
findings do not gate, or `security-and-quality` becomes a style gate and the lane gets
switched off within a week.

`authorize-production` has no trigger and refuses to run when Concourse records no triggering
human. That is the entire G5 control now — see POAM-006/010.

### Trying a pipeline change on a branch

`set-pipeline` applies `ci/pipeline.yml` **from the repo**, and that file pins
`branch: main`. So a hand-applied branch config —

```sh
sed 's|branch: main|branch: my-branch|' ci/pipeline.yml > /tmp/p.yml
fly -t mykronos set-pipeline -p keel -c /tmp/p.yml -l ci/vars.yml
```

— survives only until `set-pipeline` next runs, which reverts it to main's copy.
Main is the definition; that is the point of the job, not a defect.

To experiment on a branch, do one of:

- set it under a **different pipeline name** (`-p keel-branch`), or
- **pause `set-pipeline`** for the duration.

This is not theoretical. The fix for a broken git resource lived on a branch,
`set-pipeline` reverted the pipeline to main's broken version, and the repo
resource then stopped authenticating — so nothing could run, including
`set-pipeline`. The revert loop stopped because the pipeline broke, not because
anything caught it.

### Repository access

The repo is private, so the `repo` resource authenticates over **SSH with a
read-only deploy key** (`((git_private_key))`), not HTTPS with a token. A personal
access token would work and would put a credential that can write to every
repository the owner has into a pipeline whose need is to read one. The deploy
key is scoped to this repository and registered `read_only`.

If `check-resource` ever reports `could not read Username for 'https://github.com'`,
the pipeline has been reverted to an HTTPS config — see the trap above.

## Where a check belongs — the model, and how it changed

| | Question it answers | Trigger |
|---|---|---|
| **Prevent** | Is this change safe to merge? | **Nothing does this any more — POAM-014** |
| **Detect** | Is `main` still clean, against today's advisories, by a route prevention missed? | daily / weekly |
| **Ingest** | What are the findings for this exact commit, in the system of record? | per commit |
| **Assure** | Are the agents themselves still constrained? | weekly |
| **Authorize** | Did a named human approve the release? | manual, `authorize-production` |

The original split was by *engine* — Actions gates the PR, Concourse owns main — and the
measurable result was duplication: CodeQL ran twice per language per change, gitleaks three
times, grype/checkov/suppression-audit twice each. `main` could not be reached except through
a PR that had already run all of them, so the second run re-answered a question the first had
answered. That is not defence in depth; it is the same depth twice, and it teaches people to
read a red main job as a flake.

So the deterministic lanes moved to a cadence, and only four properties justified running
anything after the merge: **time-dependent**, **route-dependent**, **commit-keyed**, or **too
slow for the PR budget**.

**That premise is now false.** There is no PR run. So the deterministic lanes are back on
per-commit triggers — post-merge detection is no longer a duplicate of anything, it is the
whole of it, and a daily cadence would leave up to 24 hours of unverified `main`.

**If Actions ever run again, revert that hunk.** The duplication argument becomes correct
again the moment something blocks a merge. The reasoning is in `ci/pipeline.yml` beside the
triggers, not only here.

### What was fixed along the way

Three checks used to verify nothing: `Build`, `Lint & static typing` and `Test & coverage`
each echoed `ADAPT: ...` and exited 0 — required, green on every PR, asserting nothing — while
every real test ran under a job called *Platform integrity*. The names were backwards.

The largest language had no check at all: **3,785 lines of shell across 28 files**, with
`shellcheck` appearing only as a string inside the suppression-audit pattern. It catches
SC2097/SC2098 — the assignment-prefix bug that made every Mykronos upload abort before calling
the CLI — and does not catch the pipefail/SIGPIPE inversion. One of two, and it has since
caught an SC2183 in a later commit.

### Deliberately not required

- **Container image scan** — inert until this repo ships an image. Requiring a
  check that can never report would block every PR.
- **SCA and IaC skip loudly and pass**, because there are no manifests and no IaC.
  That is correct: they become applicable the moment either appears, and the skip
  prints "THIS IS NOT A PASS" rather than going quietly green. They stay required
  so the day input arrives, the gate is already in place.
- **Task images are pinned by tag, not digest.** `scripts/validate-pipeline.py`
  warns rather than fails. Digest-pinning `python:3.13` would stop base-image CVE
  fixes arriving — a patch-currency risk traded for a supply-chain one. Promote to
  an error once Dependabot updates digests.

### Why the pull-request half was on Actions, and why it is retired

Concourse has no first-class pull-request trigger, and cannot report a commit
status back to GitHub without a third-party resource type — the well-known
options are archived. Taking an unmaintained dependency into the pipeline that
enforces SR-3/SR-4 would be worse than leaving GitHub-shaped checks on GitHub.
That reasoning kept `pr-governance.yml` on Actions after the port.

Two things changed. Actions stopped starting on billing, so the workflow was
disabled and its checks stopped being required. And Concourse found a way to
report to GitHub without a resource type: it posts to MyKronos, and MyKronos
posts the check run through its own GitHub App (#107, below). So on 2026-10-20
the operator chose the Concourse check run as the gate and retired
`PR Governance` (TheHub #60849, option C). The workflow file stays, with its
triggers reduced to `workflow_dispatch`, which is the convention for every
retired workflow here. `.github/workflows/` is `merge_required`, so a fork that
does run Actions still receives it.

`pr-governance.yml` read the PR *body* through the GitHub API, and that data
does not exist outside GitHub. No Concourse check replaces that part. It is
reviewer-enforced now, and the box at the top of this file says so.

This section used to say that eleven required status checks protect `main`,
eight of them from `ci.yml` and `security.yml`. That stopped being true on
2026-08-13. Both workflows are reduced to `workflow_dispatch`, and nothing is
required.

### Why release authorization stayed on Actions

The G5 gate is a `production` environment with required reviewers: the deploy job
physically cannot start until a named human approves, and that record — identity,
timestamp, bound to the run — **is** the CM-3 change-approval evidence.

Concourse's nearest equivalent is a job with no trigger. Triggering and approving
collapse into one action, nothing requires the approver to differ from the
author, and authorization is per team rather than per job.

This lane was built in Concourse first and accepted as POAM-010, a High finding.
It was then moved back, because accepting it would have reopened POAM-006 — the
same gap, closed five days earlier — to save a split pipeline. See ADR-0003 § D2.

**Consequence to act on:** the artifact is now built by Concourse, so
`release.yml`'s `cosign verify` must match Concourse's signing identity, and
`gh attestation verify` will not work at all (POAM-011). Adapt those steps before
the first real release.

### `Concourse / keel`: the commit chain's verdict, on GitHub (#107)

Concourse's verdict on a `main` commit now shows on that commit in GitHub, as one
check run named **`Concourse / keel`**. `build` reports it in progress before it
builds. `verify-artifact` reports success as its last step, because it is the end
of the only chain in this pipeline (`build`/`lint`/`test`/`sast`/`secrets`/`sca`/`iac`
→ `build-and-attest` → `verify-artifact`). Every job in that chain reports failure
from `on_failure:` and `on_error:`.

Concourse does not call GitHub for this. `ci/scripts/check-run.sh` posts the job's
start or end to MyKronos (`POST /api/ingest/check-runs`) with
`((mykronos_ingestion_token))`, the token the MyKronos lanes already use. MyKronos
posts the check run through its own GitHub App (app id 4551328) and keeps one
check run per commit. That is the pattern MyKronos D-136 built for TheHub, reused
here under TheHub #60580. It does not reopen the archived-resource-type question
above: there is no new resource type, and no GitHub credential in the pipeline.

The scanning lanes `sast`, `secrets`, `sca` and `iac` are part of this verdict
since TheHub #60850. `build-and-attest` gathers them: its `passed:` names all
seven verifying lanes, so `verify-artifact` reports success only for a commit
that passed every one. A scanner can only report failure, so the colour no
longer depends on which job finished last (the objection MyKronos D-151
recorded). The cost is time: the verdict now waits on `sca` and the serial
CodeQL `sast`, which took 12-22 minutes on push builds in October 2026.
`suppression-audit`, `platform-integrity` and the MyKronos lanes stay out.

**The trade, stated plainly: this check lands on `main` commits only, and that is
why it is not required.** Verification runs after the merge (POAM-014). `repo`
tracks `main`, and Concourse never sees a pull request's head. So:

- **A pull request never carries `Concourse / keel` yet.** Requiring it on `main`
  today would make every pull request wait for a check that cannot arrive. With
  `enforce_admins` off, the owner's merges would bypass it. Anyone else, and
  Dependabot, could never merge at all. This is what TheHub #60580 has to change
  before the requirement below is switched on.
- **It does not prevent anything.** It turns a red `main` from "visible in
  Concourse, if you look" into "visible on the commit in GitHub". That is
  detection, not prevention, and POAM-014 stays open.
- **A daily re-run does not reopen a verdict.** `build` also fires on
  `daily-0300`. MyKronos leaves an existing verdict alone on a start, and the
  re-run's own failure, if any, replaces it.
- **MyKronos is now on the commit path.** If MyKronos is unreachable, `build`
  goes red at the start report, and a failed chain job's report fails as well.
  That is the visible failure this asked for. It also means an outage there
  stops keel's chain until it is fixed.
- **A commit Concourse skips stays in progress.** When two commits land close
  together, the chain takes the newer one, and the older commit's check stays
  `in_progress`.

**Requiring it: decided, not yet applied (TheHub #60849, option C).** This is
keel's merge gate. It is switched on when TheHub #60580 lands, by #60580 or by
the owner. It is never switched on before then, for the reason in the first
bullet above. Nothing in this repository changes branch protection.
`required_status_checks` is off on `main` today, so the sub-resource `PATCH`
returns `404 Required status checks not enabled`. Enabling it means a `PUT` of
the whole protection, which restates every other setting exactly as read on
2026-10-20 (unchanged since 2026-10-11). Re-read with
`gh api repos/ToddGBenson/keel/branches/main/protection` first, and change the
body if anything has moved. Pinning `app_id` means a status of the same name
from anything else cannot satisfy it.

```sh
gh api -X PUT repos/ToddGBenson/keel/branches/main/protection --input - <<'JSON'
{
  "required_status_checks": {
    "strict": false,
    "checks": [{"context": "Concourse / keel", "app_id": 4551328}]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "require_last_push_approval": false,
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": false
}
JSON
```

Undo it with
`gh api -X DELETE repos/ToddGBenson/keel/branches/main/protection/required_status_checks`.

---

## Setting it up

### 1. Vars

```sh
cp ci/vars.example.yml ci/vars.yml     # gitignored
```

Tool pins are already resolved (2026-08-13) — CodeQL, grype, checkov, trivy and
cosign, each checksummed against the publisher's own checksums file rather than
hashed from a local download. `ci/vars.example.yml` records how to refresh them.

`registry`, `staging_url` and `production_url` are deliberately **empty**, not
placeholders: this repository does not build a deployable artifact yet, and
filling them in would make four inert lanes look configured. Set them in the
same change that makes the build real.

Note `concourse_external_url` defaults to `http://localhost:8080`, which means
build URLs written into evidence records will not resolve for anyone else.
Repoint it as soon as this Concourse has a routable address.

### 2. Credentials

Secrets are never passed with `-l`. `fly get-pipeline` prints the pipeline config
back to anyone on the team, including anything a `-l` file put in it. Put these
in the credential manager instead:

```
github_token · webhook_token · mykronos_ingestion_token
registry_user · registry_password
```

`anthropic_api_key` is needed only by a fork that wires the `ai-evals` template
lane. keel's own pipeline no longer references it.

With Vault at the default paths, `((foo))` resolves from
`/concourse/<team>/<pipeline>/foo`, then `/concourse/<team>/foo`.

### 3. Set the pipeline

```sh
fly -t <target> validate-pipeline -c ci/pipeline.yml
fly -t <target> set-pipeline -p keel -c ci/pipeline.yml -l ci/vars.yml
fly -t <target> unpause-pipeline -p keel
```

### 4. Webhook (optional, recommended)

The `repo` resource polls every minute. To get push-time builds instead, add a
GitHub webhook pointing at:

```
<concourse_external_url>/api/v1/teams/<team>/pipelines/keel/resources/repo/check/webhook?webhook_token=<webhook_token>
```

### 5. Branch protection — read it, do not assume it

This section used to say eleven required status checks protect `main`. **Read on
2026-10-11 and again on 2026-10-20, none do:** `required_status_checks` is off,
because Actions cannot run here and every required check was removed so that
anything could merge (POAM-014). Reviews (one approval, `enforce_admins` off),
linear history and conversation resolution are on. `PR Governance` is
`disabled_manually` and retired (TheHub #60849).

```sh
gh api repos/ToddGBenson/keel/branches/main/protection   --jq '{checks: .required_status_checks, admins: .enforce_admins.enabled}'
```

`Concourse / keel` is the check that will be required, once TheHub #60580 lands.
The section above gives the command and says why it must not be applied sooner.

---

## Layout

```
ci/
├── pipeline.yml          jobs, resources, schedules
├── vars.example.yml      non-secret vars + how to resolve each CHANGEME
├── tasks/                thin task definitions — image, inputs, outputs, params
└── scripts/              the logic
```

Tasks are thin on purpose. The logic lives in `ci/scripts/*.sh`, which means it
runs locally exactly as CI runs it — the one unambiguous gain from moving off
Actions, where the same logic was trapped in YAML `run:` blocks and
`actions/github-script`:

```sh
mkdir -p /tmp/wk && cd /tmp/wk && ln -s ~/src/keel repo
STAGE=test bash repo/ci/scripts/ci-stage.sh
```

Scripts expect the build directory as cwd, with `repo/` and any declared
input/output directories as siblings — the Concourse convention.

---

## Deliberate design choices

**No third-party resource types.** Everything is a resource Concourse ships
(`git`, `time`, `registry-image`, `github-release`). A pipeline enforcing
supply-chain controls should not pull unpinned community code to start up.

**Tool binaries are checksum-verified.** OSV-Scanner, grype, trivy and cosign are
fetched from GitHub releases and checked against a pinned SHA-256 before running.
This is not ceremony: `pip install osv-scanner` silently installed a reserved
PyPI placeholder with no CLI, and every Atlas run reported zero findings for the
life of that lane (#38).

**So is the one Python package.** The pipeline needs exactly one third-party
Python library — PyYAML, for the validators that parse the manifest, the agent
inventory and the workflows. It is declared in `ci/requirements.txt`, pinned to an
exact version and carrying the SHA-256 of every distribution PyPI publishes for
that release, and every install site uses
`pip install --require-hashes -r ci/requirements.txt`. A fetched package is code on
the same terms as a fetched binary, and it runs in a container with the repository
checked out. The file doubles as the dependency manifest the Atlas lane previously
had nothing to scan (mykronos#323).

**Scanners do not decide build outcomes on the Mykronos lanes.** The scan tasks
exit 0 regardless; threshold and blocking policy belong to the uploader, which
applies this repository's configured policy. A scanner deciding CI outcomes on
its own bypasses that.

**"Nothing to scan" never renders as green.** Every lane that can encounter
absent input detects it and says so loudly (L0007, L0008). A skip is a scope
statement, not a pass.

---

## Known gaps from the port

Four capabilities were at risk. Two were fixed by changing the design rather than
accepting the finding; two remain open. All are in `docs/compliance/poam.md`
rather than described as equivalent.

| # | Gap | Impact | Status |
|---|---|---|---|
| POAM-010 | **G5 human authorization is weaker in Concourse.** No approval workflow, no second-identity requirement, team-level access. Same gap POAM-006 closed on 2026-08-08. | AC-5, CM-3 | **Closed** — G5 moved back to Actions (ADR-0003 § D2) |
| POAM-011 | **GitHub attestation store is unreachable.** `actions/attest-build-provenance` and `actions/attest-sbom` cannot run outside Actions. cosign attestations cover the same ground, but anything verifying with `gh attestation verify` must be repointed — including `release.yml`, which now verifies a Concourse-built artifact. | SR-4(3) | **Open** |
| POAM-012 | **CodeQL SARIF from Concourse does not reach the Security tab.** The code scanning API is Actions-only. | SA-11(1) | **Open, reduced** — `security.yml` still runs on PRs, so PR commits still populate it. Only main and scheduled runs are affected, and Mykronos is the system of record. |
| POAM-013 | **Monthly cadence is approximated.** Concourse's `time` resource has no day-of-month, so `compliance-monthly` runs on a 7-day interval gated on day-of-month ≤ 7 — exactly once per calendar month, on an unpredictable date. | CA-7 | **Accepted** |

Watch for one thing POAM-012 causes: the Security tab retains **stale** CodeQL
results from before the port for main-branch commits. Stale results that look
current are worse than an empty tab. Do not cite it as SA-11(1) evidence for a
main-branch commit after 2026-08-13.

---

## Rollback

Nothing was deleted, and `main` never lost a required check:

1. `git revert` the commit that changed `.github/workflows/`, restoring `push`
   and `schedule` to `ci.yml` and `security.yml`. Their `pull_request` triggers
   were never removed, so PR gating is unaffected either way.
2. `fly -t <target> pause-pipeline -p keel`

Release authorization needs no rollback — it never left `release.yml`.

The Mykronos workflows will come back on their own at the next
`scripts/sync-platform.sh` run — the installer regenerates them and does not know
about this pipeline. When that happens, **both** the restored workflow and the
Concourse job will scan and ingest, producing duplicate ScanRuns for the same
commit. Treat a resync of those three paths as a merge conflict to resolve, not a
diff to accept. Tracked upstream as ToddGBenson/mykronos#13.
