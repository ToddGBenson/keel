# Concourse pipeline

Execution for keel's lifecycle. Ported from GitHub Actions — see #42 and
`docs/06-cicd.md`.

This pipeline produces the **evidence** gates are approved against. It does not
approve anything. Gate approval stays a human act recorded in GitHub (PD-2).

---

## What runs where, after the port

> ## ⚠️ READ THIS FIRST — Concourse is the whole pipeline, and nothing gates a merge
>
> As of 2026-08-13: the repository is **private**, GitHub Actions **cannot run** (billing —
> `job was not started because recent account payments have failed or your spending limit
> needs to be increased`), **all ten workflows are disabled**, and every required status check
> has been removed from `main`.
>
> **Nothing verifies a change before it lands.** `required_approving_review_count` is 0 and
> there are no status checks. Everything below is detection *after* the fact — which is why
> the deterministic lanes were put back on per-commit triggers.
>
> **Two capabilities have no Concourse equivalent and are simply gone:**
>
> - **Process compliance** — it read the pull request *body* (issue linkage, AI-authorship
>   declaration, DoD checklist, and the self-review artifact that is POAM-008's compensating
>   control). Concourse has no pull-request concept. Solo operation was accepted on the basis
>   that this check enforced a self-review in place of a second approver. Nothing enforces it.
> - **Dependency review** — a GitHub feature, not a tool. grype and osv-scanner cover the SCA
>   function; the new-vulnerabilities-in-this-diff framing is not reproduced.
>
> Tracked as **POAM-014 (Critical)**. Closing it: fix Actions billing, go public again, or add
> a self-hosted runner (free on private repos — the box already running Concourse would do).

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

## Where things run

Everything is in `ci/pipeline.yml`. There is no second system.

| Concern | Job | Trigger |
|---|---|---|
| Pipeline updates itself from `main` | `set-pipeline` | per commit |
| Build, lint, test, full suite | `build` `lint` `test` `full-suite` | per commit + daily |
| **SAST — CodeQL, python + js, GATES on findings** | `sast` | per commit + daily |
| Secrets, SCA, IaC, suppressions | `secrets` `sca` `iac` `suppression-audit` | per commit + daily |
| Container scan | `container-scan` | manual (inert until an image exists) |
| Platform / control integrity | `platform-integrity` | per commit + daily |
| Mykronos ingestion | `mykronos-*` | per commit + weekly — **PAUSED, no token** |
| AI evals, guardrails, agent assurance | `ai-*` `agent-assurance` | per commit / weekly |
| Compliance monitoring, metrics | `compliance-*` `metrics-snapshot` | daily / weekly |
| SBOM, sign, verify | `build-and-attest` `verify-artifact` | per commit |
| **Release G5** | `release-preflight` → `deploy-staging` → `authorize-production` | **manual only** |

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

### Why the pull-request half stayed on Actions

Concourse has no first-class pull-request trigger, and cannot report a commit
status back to GitHub without a third-party resource type — the well-known
options are archived. Taking an unmaintained dependency into the pipeline that
enforces SR-3/SR-4 would be worse than leaving GitHub-shaped checks on GitHub.

`pr-governance.yml` additionally reads the PR *body* through the GitHub API.
That data does not exist outside GitHub.

Eleven required status checks protect `main`, and eight of them come from
`ci.yml` and `security.yml`. The first cut of this port disabled both outright —
which would have left no SAST, secret, SCA, IaC, coverage or suppression gate on
any pull request at all. A High CVE would have merged cleanly and turned `main`
red afterwards. Both keep their `pull_request:` trigger for that reason; they
lost only `push` and `schedule`, which Concourse now owns.

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
anthropic_api_key · registry_user · registry_password
```

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

### 5. Branch protection — no change needed, but verify

All eleven required status checks on `main` still report, because `ci.yml`,
`security.yml` and `pr-governance.yml` all keep their `pull_request:` trigger.
**Do not remove any of them.**

This is worth stating because the first cut of this port did disable `ci.yml` and
`security.yml`, which would have made eight of those eleven unable to ever report
— blocking every PR forever on checks that no longer exist, and inviting exactly
the wrong fix: deleting the requirement instead of restoring the trigger.

Confirm they are intact:

```sh
gh api repos/ToddGBenson/keel/branches/main/protection \
  --jq '.required_status_checks.contexts'
```

Expect eleven, including `Build`, `Lint & static typing`, `Test & coverage`,
`Secret scanning (IA-5)`, `SCA — dependency vulnerabilities (RA-5, SR-3)`,
`IaC & configuration (CM-6, CM-7)`, `Suppression audit` and
`SAST — CodeQL (SA-11(1)) (javascript-typescript)`.

If any of those stop reporting, the fault is a missing `pull_request:` trigger,
not an over-strict branch protection rule.

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
