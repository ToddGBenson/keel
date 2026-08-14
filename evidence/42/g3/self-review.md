# Self-review — #42

Mode: solo (POAM-008)
PR: #43   Author: Todd Benson (claude-opus-5, AI-authored)   Date: 2026-08-13
Opened: 2026-08-13 07:44 UTC   Reviewed: 2026-08-13 08:56 UTC   **Cooling-off: 1h 12m ❌**

> **This record does not satisfy the cooling-off requirement.** The `self-review` skill is
> explicit that it must not run in the session that wrote the code, because a cold read by
> the same mental model is not a review. It was run in-session at the operator's direction.
> The agent passes are unaffected — they had no access to the implementation reasoning — but
> the cold-read section below is worth less than it looks, and should be redone before merge.

---

## Verified independently

Things I executed and read the output of, not things I reasoned about:

- **`fly validate-pipeline -c ci/pipeline.yml` → `looks good`.** AC-1 met. Also set the real
  pipeline on a live Concourse 7.14.3 (`keel-port-trial`, pinned to this branch) and ran 19
  jobs green — so `fly` accepts the top-level YAML-anchor keys that one review pass suspected
  it would reject. **That finding is refuted by execution.**
- **CodeQL CLI end-to-end.** Ran `sast` with `CODEQL_LANGUAGE=python`: 846 MB bundle
  downloaded, `sha256sum -c` passed, database built, and **both** requested suites resolved
  from the pack (`security-extended` and `security-and-quality` — quality queries appear in
  the log). 8 findings, SARIF written. This was the riskiest ported path and it works.
- **Every pinned asset URL resolves** exactly as the scripts construct it — grype, trivy,
  cosign, CodeQL bundle, OSV-Scanner — checked by range request. Checksums were taken from
  each publisher's own checksums file, not hashed from a local download; the CodeQL digest
  was cross-checked against two independent sources (release API asset digest and the
  published `.checksum.txt`) and they agree.
- **Mykronos CLI compatibility, against source at the pinned ref `8b329fc`.** Fetched
  `actions/upload-results/action.yml`, `upload.py` and `schemas.py`. Every flag exists;
  `sast`/`secrets`/`atlas` are members of `Capability`; `manual`/`push`/`schedule` are
  members of `TriggeredBy`; `--pr-number 0` normalises to `None` at `upload.py:288`. This is
  argument compatibility **by inspection, not by a live upload** — see Not verified.
- **Both HIGH review findings reproduced before I acted on them.** The assignment-prefix
  unbound-variable abort, and the `find | grep -q .` inversion — measured as correct at 200
  files and silently skipped at 2000.
- **Regression cases for each fix**, run after: presence test at 2000 files now demands the
  pin (i.e. detects source); truncated gitleaks report → exit 1; `# nosec refs #123` with no
  expiry → exit 1; atlas response parsing across hostile / missing-field / non-boolean /
  valid → 1,1,1,0 with the injection payload proven not to execute.
- **Guard self-test 38/38 after modifying `guard-write.sh`**, and `validate-platform.py`
  clean after modifying `MANIFEST.yml`, `CODEOWNERS` and `sprint.sh`.
- **All 11 required status checks report on PR #43.** Read the live check list rather than
  assuming; this is what proved the planned branch-protection trim was the wrong fix.

## Agent findings

Three fresh invocations, given only the diff and the story — no implementation rationale.

- **`developer` — request changes.** 15 confirmed, 4 suspected. Two HIGH, both real, both
  breaking: the Mykronos token abort and the pipefail/SIGPIPE presence-test inversion.
- **`security-engineer` — G4 BLOCKED on one High.** The change-control perimeter (`sprint.sh`
  PROTECTED, CODEOWNERS, `guard-write.sh`, `install-hooks.sh`, `validate-platform.py`) was
  keyed to `.github/workflows/` and did not follow the gates to `ci/`. Also found the
  response-body-as-shell injection, and that POAM-011 overstated what cosign carries.
- **`qa-engineer` — REJECT.** Ten load-bearing decision branches, zero constrained by any
  test, all failing open. Independently found the gitleaks fail-open and the suppression
  AND/OR bug by execution.

Fixed in `294a442`: both HIGHs, the injection, the gitleaks fail-open, the suppression
AND/OR, the `--exclude-dir=ci` blind spot, the unreachable SBOM input, the `ensure: do:`
short-circuit, the SBOM-archive abort, `TRIGGERED_BY`, unused credential params, the four
change-control path lists, `ci/` in `MANIFEST.yml`, PR-time Python SAST, and the inaccurate
ADR-0003 / POAM-011 / POAM-013 claims.

## Not verified

Say unverified, not passed.

- **The Mykronos ingestion path has never run.** Those three jobs were paused throughout —
  no ingestion token in the trial, and I would not point them at the live service with bad
  credentials. Compatibility is established by reading the pinned source. **Given that a
  defect in exactly this script survived my own testing and was caught only by review, one
  live upload is the single highest-value thing outstanding.**
- **grype's and checkov's download-and-verify paths.** Both jobs ran green — and both
  short-circuited on the loud "nothing to scan" branch, because this repo has no dependency
  manifests and no IaC. The URLs resolve; the code that consumes them has not executed.
- **`build-and-attest` and `verify-artifact`.** Never run. `verify-artifact` currently prints
  "Failure here is a hard block. An unverifiable artifact does not deploy" having verified
  nothing — the most misleading string in the change, and it stays until the build is real.
- **The GitHub `production` environment's required reviewers.** POAM-010's closure rests on
  it. It is a repo setting, not a file; POAM-006 claims it was verified on 2026-08-08 and I
  did not re-test it. Closing a High on an untested premise is the weakest link in this PR.
- **`.claude/hooks/selftest.sh`, `test/dashboard.test.py` and `evals/run-agent-evals.sh`
  inside `python:3.13`** — `platform-integrity` and `agent-assurance` both passed on the real
  Concourse, so this is *partly* verified; the monthly compliance path invoking the same
  scripts has not run.
- **POAM-013's cadence** over a long horizon, under `interval` drift. The claim was
  downgraded rather than defended.
- **Whether `github-release` writes `commit_sha`, and whether it holds the commit or the tag
  object.** If either assumption is wrong, `IS_RELEASE` is permanently false and the Atlas
  trust-floor gate — the only blocking control in that lane — never fires, silently. **Not
  fixed. Carried as an open defect.**

## Cold-read notes

Discounted per the cooling-off failure above, but recorded:

- **What I did not want to look at: the review findings themselves.** My instinct on reading
  25 findings was to triage them as mostly-nits. Two were pipeline-breaking, one was a shell
  injection I wrote, and one was a security gate that reports clean on a corrupt input. The
  reflex to defend was wrong every time it fired.
- **I built what was asked, then changed the ask twice** — PR gating and G5 both moved back
  to Actions after the port proved the cost. Both were right, but story #42's acceptance
  criteria now describe something other than what shipped (AC-5 explicitly). **The AC was
  not re-baselined with the Product Owner, and the PR body asserted "only pr-governance is
  live ✅", which is false at HEAD.** That is a PD-3 problem I introduced and did not catch.
- **The pattern across every defect found: I verified the things I built and not the things
  I copied.** The presence test, the suppression AND/OR and the token handling were all
  ported and all broken — two of them broken *by* the porting. I ran the new logic and
  trusted the old.
- **ADR-0003 argues that executing the pipeline is what surfaces this class of defect, and
  four more of the same class shipped in the same commit as that argument.** Writing the
  lesson is not the same as applying it.

## Residual risk accepted

- **Single-identity review.** No independent human read this diff. The three agent passes are
  a compensating control under POAM-008, not a substitute — and their independence is real
  (they found what I could not) but bounded: they read the same requirement I did.
- **Cooling-off not observed.** Recorded above rather than omitted.
- **No automated test protects any of it.** All ten decision branches the QA pass enumerated
  remain unconstrained; the regression cases I ran live in this session's shell history, not
  in the repo. `ci/scripts/selftest.sh` — modelled on `.claude/hooks/selftest.sh`, which
  already exists and is already wired into `platform-integrity` — is the concrete next step
  and is **not** in this PR.
- Next external sample review due: 2026-10-01.

## Recommendation

**Do not merge on this record alone.** The blocking defects are fixed and verified, but three
things are outstanding and two of them are one-liners:

1. Re-baseline AC-5 and AC-6 on #42 with the Product Owner, and correct the false statement
   in the PR body.
2. One live Mykronos upload, and re-verify the `production` environment reviewers.
3. `ci/scripts/selftest.sh`, or an explicit decision to accept the untested branches with a
   POA&M entry naming them.
