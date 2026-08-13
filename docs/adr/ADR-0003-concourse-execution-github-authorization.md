# ADR-0003: Concourse executes the pipeline; GitHub authorizes the pull request and the release

**Status:** Accepted
**Date:** 2026-08-13
**Deciders:** platform owner (human), with agent-drafted analysis and a live trial
**Related:** #42, #43, ADR-0001, POAM-006, POAM-010, POAM-011, POAM-012, POAM-013,
`ci/README.md`, `docs/06-cicd.md`

> Two of the four decisions below were reversed by running the thing. They are recorded as
> reversals rather than rewritten as if they had been obvious.

## Context

All CI/CD ran on GitHub Actions: build and test, five scanners, three Mykronos ingestion
lanes, AI assurance, continuous monitoring, supply chain, and the G5 release gate. The
decision was taken to move execution to Concourse.

Three properties of the existing setup were not negotiable, because the whole assurance
chain rests on them:

1. **PD-2 — no self-approval.** Gate approval is a human act, recorded, backed by evidence.
2. **PD-3 — evidence over assertion.** A workflow run URL, a SARIF file, a signed
   attestation. Not "the scan ran".
3. **PD-7 — no faked compliance.** If a control is not met, that is a finding, not a
   softened description.

The question was therefore never "can Concourse run these jobs" — it can — but **which
controls stop being controls when they move.**

## Decisions

### D1 — Concourse owns execution; GitHub owns pull-request gating

**Chosen.** Build, scanning, Mykronos ingestion, AI assurance, compliance monitoring and
supply chain run in `ci/pipeline.yml`. `pr-governance.yml`, `ci.yml` and `security.yml`
keep their `pull_request:` trigger and lose `push`/`schedule`.

**Why the split is not arbitrary.** Concourse has no first-class pull-request trigger and
cannot report a commit status back to GitHub without a third-party resource type — and the
well-known options are archived. Depending on unmaintained code inside the pipeline whose
job is enforcing SR-3/SR-4 would be self-defeating.

`pr-governance.yml` additionally reads the PR *body* through the GitHub API: issue linkage,
AI-authorship declaration, DoD checklist, solo-mode self-review. That data does not exist
outside GitHub.

**Rejected: full port, adopting `github-pr-resource`.** Archived dependency in the
supply-chain enforcement path.

**Rejected: full port, branch-based with a status resource.** No PR body access, so the
governance checks that read it could not run at all.

**REVERSED DURING IMPLEMENTATION.** The first cut disabled `ci.yml` and `security.yml`
outright, leaving only `pr-governance.yml` on Actions. Reading the branch protection
settings showed what that actually meant: eight of `main`'s eleven required status checks
came from those two files. Removing them would have left **no SAST, secret, SCA, IaC,
coverage or suppression gate on any pull request** — a High CVE would merge cleanly and
then turn `main` red afterwards. Scanning would have become a post-merge notification
wearing the word "gate".

The reversal costs some duplicated scanning between PR and main. That is minutes. The
alternative was a merge gate that had quietly become a report.

**Consequence:** two systems, and a rule for deciding between them — *GitHub gates the pull
request, Concourse owns main and everything scheduled.*

### D2 — Release authorization stays on GitHub Actions

**Chosen.** `release.yml` remains the live G5 path. Concourse has no release lane.

**Why.** The G5 gate is a `production` environment with required reviewers. The deploy job
*physically cannot start* until a named human approves, and that record — identity,
timestamp, bound to the run — **is** the CM-3 change-approval evidence. It is a technical
control, not a documented intention.

Concourse's nearest equivalent is a job with no trigger. That is weaker in three specific
ways: triggering and approving collapse into one action, so there is no decision distinct
from an act; there is no requirement that the approver differ from the author, which is
what AC-5 exists to prevent; and authorization is per team, not per job.

**REVERSED DURING IMPLEMENTATION.** The release lane was built in Concourse first and
accepted as POAM-010, a High finding — including a guard making `authorize-production`
refuse to run when no triggering human was recorded. Writing that guard was what made the
problem concrete: it could establish that *a* human pressed the button, and nothing more.
It could not establish that the human was entitled to, or that they were not the author.

POAM-006 had closed this exact gap five days earlier. Accepting POAM-010 would have
reopened it to avoid a split pipeline — trading the strongest control in the lifecycle for
a tidier diagram.

**Rejected: keep it in Concourse with a signed approval record.** Genuinely closes the gap
and keeps one pipeline. Rejected as more machinery than the problem needs while
`release.yml` already exists and already works. Revisit if the split becomes painful.

**Consequence:** release orchestration lives apart from the rest of CI. The artifact is now
built by Concourse, so `release.yml`'s `cosign verify` must match Concourse's signing
identity, and `gh attestation verify` cannot work at all — see D4.

### D3 — No third-party Concourse resource types

**Chosen.** Only `git`, `time`, `registry-image` and `github-release` — all shipped with
Concourse. Tool binaries (OSV-Scanner, grype, trivy, cosign, the CodeQL bundle) are fetched
from upstream releases and verified against the **publisher's** checksum file, not a hash
computed from whatever arrived.

**Why.** A pipeline enforcing supply-chain controls should not pull unpinned community code
to start up. The precedent is concrete: `pip install osv-scanner` resolved to a reserved
PyPI placeholder with no CLI, and every Atlas run reported zero findings for the life of
that lane (#38).

**Consequence:** more is built by hand — CodeQL runs from the CLI bundle rather than
`github/codeql-action`. The bundle is 846 MB per SAST run, which is the real cost of this
decision.

### D4 — Name what did not survive; do not describe it as equivalent

**Chosen.** Four capabilities were lost or weakened and are POA&M entries, not footnotes:

| | Weakness | Status |
|---|---|---|
| POAM-010 | G5 authorization weaker in Concourse | **Closed by D2** |
| POAM-011 | GitHub attestation store unreachable; cosign carries provenance | Open |
| POAM-012 | CodeQL SARIF does not reach code scanning from Concourse | Open, reduced by D1 |
| POAM-013 | Monthly cadence approximated by a 7-day interval | Accepted |

D1 reduced POAM-012's scope without being aimed at it: because `security.yml` still runs on
pull requests, PR commits still populate the Security tab. Only main-branch and scheduled
runs are affected.

## Consequences

**Good.** Job logic moved from YAML `run:` blocks and `actions/github-script` into
`ci/scripts/*.sh`, which run locally exactly as CI runs them. Mykronos ingestion is
unchanged — the same package at the same pinned ref calling the same CLI — because
`upload-results` turned out to be a thin wrapper, which was verified against source rather
than assumed.

**Bad.** Two systems to reason about, and a boundary someone will eventually get wrong. The
mitigation is that the boundary follows one sentence rather than a list of exceptions.

**Unresolved.** `registry`, `staging_url` and `production_url` are empty because this
repository does not build a deployable artifact yet. Four lanes are inert until it does, and
they are configured to say so loudly rather than pass quietly.

## What this ADR is evidence of

Both reversals came from executing the pipeline, not from reviewing it. Two further defects
surfaced the same way and never appeared in any read-through:

- Windowed `time` resources emit no version until their window opens, so every scanning lane
  sat `pending` — unrunnable, and indistinguishable from "queued" in the UI. The pipeline
  looked healthy with most of its security scanning never having run.
- Tool version pins were asserted *before* the "is there anything to scan" test, turning
  `sast` red on a repository with no JavaScript — a red gate for a non-finding reason, two
  lines above the check that exists to prevent exactly that.

Both are the L0007/L0008 failure shape, reintroduced by someone who had just read those
lessons. That is the argument for `fly validate-pipeline` being necessary and nowhere near
sufficient, and it is the reason this ADR exists in the form it does.
