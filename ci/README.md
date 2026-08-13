# Concourse pipeline

Execution for keel's lifecycle. Ported from GitHub Actions — see #42 and
`docs/06-cicd.md`.

This pipeline produces the **evidence** gates are approved against. It does not
approve anything. Gate approval stays a human act recorded in GitHub (PD-2).

---

## What runs where, after the port

| Concern | Runs on | Why |
|---|---|---|
| Build, lint, test, coverage | Concourse | |
| SAST, secrets, SCA, IaC, suppressions | Concourse | |
| Mykronos sast / secrets / atlas | Concourse | Same `mykronos.upload` CLI, same pinned ref |
| Platform integrity | **Both** | Required PR check on Actions; also on main here |
| AI evals, guardrails, agent assurance | Concourse | |
| Compliance monitoring, metrics | Concourse | |
| SBOM, sign, verify | Concourse | |
| Release G5 | Concourse | **With a weakened gate — see below** |
| **PR governance** | **GitHub Actions** | Deliberate. See below. |

### Why PR governance stayed on Actions

`.github/workflows/pr-governance.yml` is the only workflow still enabled on its
original triggers. It reads the pull request body through the GitHub API to check
issue linkage, AI-authorship declaration, the DoD checklist, and the solo-mode
self-review record — and it is a required status check on `main`.

Concourse has no first-class pull request trigger. Every route to adding one
means depending on a third-party resource type, and the well-known options are
archived. Taking an unmaintained dependency into the pipeline that enforces
SR-3/SR-4 would be a worse outcome than leaving a GitHub-shaped check on GitHub.

The `platform-integrity` job from that workflow **also** runs here, because a PR
check cannot see a change that reaches `main` without a PR.

---

## Setting it up

### 1. Vars

```sh
cp ci/vars.example.yml ci/vars.yml     # gitignored
```

Fill in every `CHANGEME`. They are versions and checksums for tools that perform
or verify security checks; each is left unset on purpose, because a wrong pin
produces a job that runs, passes, and means nothing. `ci/vars.example.yml`
documents where to get each one.

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

### 5. Branch protection — do not skip this

Nine workflows have been reduced to `workflow_dispatch`. **Any of their job names
still listed as required status checks on `main` will now block every PR
forever**, waiting on a check that can no longer report.

Keep only `pr-governance.yml`'s checks required:

```sh
gh api repos/ToddGBenson/keel/branches/main/protection/required_status_checks \
  --method PATCH \
  -f 'checks[][context]=Process compliance' \
  -f 'checks[][context]=Platform integrity (AIC-3, AIC-8, AU-9)' \
  -f 'checks[][context]=Dependency review (SR-3, SR-4, AIC-7)'
```

Verify with `gh api repos/ToddGBenson/keel/branches/main/protection --jq '.required_status_checks'`.

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

Four capabilities did not survive intact. All four are in
`docs/compliance/poam.md` rather than described as equivalent.

| # | Gap | Impact |
|---|---|---|
| POAM-010 | **G5 human authorization is weaker.** This is the same gap POAM-006 closed on 2026-08-08; moving off Actions reopens it in a different form. Actions used a `production` environment with required reviewers — the job could not start until a named human approved, and that record was the CM-3 evidence. Concourse has a manually-triggered job: no approval workflow, no second-identity requirement, and anyone with pipeline access can trigger it. | AC-5, CM-3 |
| POAM-011 | **GitHub attestation store is unreachable.** `actions/attest-build-provenance` and `actions/attest-sbom` cannot run outside Actions. cosign attestations cover the same ground, but anything verifying with `gh attestation verify` must be repointed. | SR-4(3) |
| POAM-012 | **CodeQL SARIF no longer reaches the GitHub Security tab.** The code scanning API is Actions-only. Mykronos remains the system of record for findings and still receives the SARIF; the keel-owned `sast` lane now emits a build artifact and a printed summary. | SA-11(1) |
| POAM-013 | **Monthly cadence is approximated.** Concourse's `time` resource has no day-of-month. The monthly job fires weekly and executes on the first Monday, announcing loudly when it is not due. | CA-7 |

`authorize-production` refuses to run when `BUILD_CREATED_BY` is empty. The only
authorization control on that job is that a human starts it, so a build with no
recorded human has no authorization at all — better to fail than to deploy
anonymously.

---

## Rollback

The Actions workflows were neutered, not deleted:

1. `git revert` the commit that changed `.github/workflows/`, or restore the
   `on:` blocks from git history.
2. Restore the required status checks removed in step 5 above.
3. `fly -t <target> pause-pipeline -p keel`

The Mykronos workflows will also come back on their own at the next
`scripts/sync-platform.sh` run — the installer regenerates them and does not know
about this pipeline. When that happens, **both** the restored workflow and the
Concourse job will scan and ingest, producing duplicate ScanRuns for the same
commit. Treat a resync of those three paths as a merge conflict to resolve, not a
diff to accept. Tracked upstream as ToddGBenson/mykronos#13.
