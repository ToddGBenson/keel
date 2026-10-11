# keel lane audit — 2026-10-11

Refs: #59989 (AC1, AC3, AC4), #60071 (AC1, AC2, AC3), #60013. Measured against
`ci/pipeline.yml` and `ci/tasks/*.yml` on `main` @ 5f23aa8, plus `fly jobs -p keel`
on 2026-10-11. Re-measure from the repo, not from `fly get-pipeline`: that export does
not inline `file:` task configs, which is how the original "23 of 26 jobs are stubs"
claim read the artefact backwards.

## The correction, kept so it is not re-quoted (#59989 AC1, AC3)

- **All 26 jobs run real tooling.** 26 of 26 reference a task file; every task file runs
  a script under `ci/scripts/` (19 scripts, all real). There were never 23 stubs.
- **keel does have IaC worth scanning.** checkov's `github_actions` framework performs
  ~716 checks on `.github/workflows/` (measured 2026-09-24, #97). So `iac` is a real,
  applicable control — build it, do not delete it.
- **The coverage drop after #59988 was a correction, not a regression.** It removed a
  same-name credit; it must not be "fixed" by re-crediting a job.

## Every job (#59989 AC4 — "the same question asked of the other jobs")

`no-subject` = what the lane does when it finds nothing to scan.

| job | trigger | runs | uploads to MyKronos | no-subject behaviour |
|---|---|---|---|---|
| set-pipeline | repo | self-apply | — | n/a |
| build, lint, test, full-suite | repo (+daily) | ci-stage.sh, shellcheck.sh | — | n/a |
| sast | repo, daily | codeql.sh (gating) | — | inverted-`grep -q` vacuous pass fixed earlier (codeql.sh:57-63); not re-measured here |
| secrets | repo, daily | gitleaks-gate.sh | — | n/a |
| **sca** | repo, daily | grype.sh | — | **exits 0** ("NOT A PASS for RA-5/SR-3") — same shape as iac before this change |
| **iac** | repo, daily | checkov.sh | iac | **now FAILS** (operator decision 2026-09-23); SARIF still marked `no_applicable_targets` |
| **container-scan** | **manual** | trivy.sh | — | **exits 0** ("not yet in service") — by design inert until an image exists |
| suppression-audit | repo, daily | suppression-audit.sh | — | n/a |
| mykronos-sast / -secrets / -atlas | repo, weekly | codeql / gitleaks / atlas + osv | sast, secrets, atlas | osv records an EMPTY RESULT (osv-scan.sh:98) |
| platform-integrity | repo, daily | platform-integrity.sh | — | n/a |
| ai-evals, ai-guardrails, agent-assurance | weekly (+repo) | ai.sh | — | not measured |
| compliance-daily/-weekly/-monthly, metrics-snapshot | daily/weekly | compliance.sh | — | n/a |
| build-and-attest, verify-artifact | repo | sbom-check.sh, supply-chain.sh | — | inert until an artifact exists (README) |
| **release-preflight** | **manual** | release.sh preflight | — | n/a |
| **authorize-release** | **manual**, `passed: [release-preflight]` | release.sh release | — | n/a |

**Only 4 of 26 lanes upload** (`iac`, `mykronos-sast`, `mykronos-secrets`,
`mykronos-atlas`). keel's own `sca`, `secrets` and `sast` gate the build but send
nothing to the platform. "Only four upload" and "only three are real" are different
claims; only the first is true.

**Open, for the operator — not decided here:** `sca` and `container-scan` still turn a
no-subject run green (exit 0 with a NOT-A-PASS banner), which is the exact shape the
2026-09-23 decision ruled out for `iac`. Applying the same rule to them would make
`container-scan` red on every run until keel ships an image. Decide per lane.

## iac: the chosen option and its effect (#60071 AC1, AC2, AC3)

- **Chosen (operator, 2026-09-23):** a no-subject scan is a FAILURE. Option A (a distinct
  exit code) cannot be built — Concourse has four terminal states and none is a second
  success. The SARIF marker (option B, #96/#97) is kept, so the lake still receives
  `NO_APPLICABLE_TARGETS`; the build status now agrees with it.
- **Effect on coverage numbers, stated before applying:** none for keel today. keel's
  workflows give checkov ~716 checks, so the no-subject branch is not reached. It changes
  the colour only for a fork that has nothing checkov understands — that fork's `iac` goes
  from green to red.
- **AC2 is moot, not unmet.** The dashboard question ("cannot tell no-subject from
  scanned-clean") only arises if no-subject is green. It is red now.
- **Separate defect, fixed in the same change:** the gate counted findings suppressed at
  the source. With `--soft-fail`, checkov still emits a `# checkov:skip=` check into the
  SARIF with a `suppressions` entry. The accepted CKV_GHA_7 risk (#99) therefore failed
  `iac` every day from 2026-10-08 (builds 88–90), while the platform's ingest correctly
  dropped it ("1 result(s) suppressed ... not ingested"). The gate now uses the ingest's
  rule: a suppressed result stands only when its suppression is `rejected`. **Effect:**
  `keel/iac` should return to green on its next run, with the finding still recorded in
  the log as suppressed.

## container-scan, release-preflight, authorize-release (#60013)

- **The intended trigger is manual, for all three. None is deleted.**
  - `container-scan`: inert until keel ships an image (pipeline comment, README "Inert
    lanes are inherited, not dead").
  - `release-preflight` and `authorize-release`: release G5 is a human act. The
    `passed: [release-preflight]` edge is what makes preflight run before authorize
    (AC3).
- **AC2 is not met, and is not forced.** container-scan has zero builds. A first build
  today would be a green no-subject run, i.e. the vacuous pass described above. It waits
  on the per-lane decision under "Open, for the operator".
- **AC4:** nothing here mutates the live keel pipeline. The change is committed to keel
  and applied by `set-pipeline` (self-apply) on merge.
