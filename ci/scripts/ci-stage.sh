#!/usr/bin/env bash
# CI stage — build, lint, test, or full-suite. Refs: #42, TheHub #60850
#
# ── THESE WERE STUBS UNTIL 2026-08-13 ────────────────────────────────────────
# All four stages echoed "ADAPT: ..." and exited 0, mirroring three GitHub
# Actions jobs that were required status checks and also verified nothing. Four
# Concourse jobs, permanently green, having done no work — while the repository's
# real tests ran only under `platform-integrity`.
#
# What is language-specific here is still yours to replace. What is now real:
# a shellcheck pass over 3,785 lines of shell, syntax checks for every language,
# the pipeline's own structural validation, and the actual test suites.
#
# `full-suite` is TEMPLATE ONLY (TheHub #60850, 2026-10-20). keel's pipeline has
# no full-suite job, because keel has no slow suite; the stage is kept for a fork
# that does, and it FAILS until adapted rather than echoing and exiting 0.
#
# Runs locally exactly as CI runs it:
#   mkdir -p /tmp/wk && cd /tmp/wk && ln -s ~/src/keel repo
#   STAGE=lint bash repo/ci/scripts/ci-stage.sh
set -euo pipefail

: "${STAGE:?STAGE is required (build|lint|test|full-suite)}"

cd repo

case "${STAGE}" in

  build)
    # No build manifest, so no artifact — stated as a scope statement rather than
    # echoed as a fake build. Fails the moment a manifest appears with no build
    # step behind it, so this cannot quietly stay green once there is something
    # to compile.
    if [ -f package.json ] || [ -f pyproject.toml ] || [ -f go.mod ] \
       || [ -f Cargo.toml ] || [ -f pom.xml ]; then
      echo "ERROR: a build manifest exists but no build step is configured." >&2
      echo "This job would report success without building anything. Adapt it." >&2
      exit 1
    fi
    cat <<'EOF'

================================================================================
BUILD: nothing to build

No build manifest in this repository, so there is no artifact to produce. This
is a SCOPE STATEMENT, not a pass.

ADAPT: install from a frozen lockfile so integrity is verified (SR-3, SR-4) —
`npm ci` not `npm install`, `pip install --require-hashes`, `go mod verify` —
then build once, reproducibly, and emit the digest. Deploys reference the digest.
================================================================================

EOF
    ;;

  lint)
    echo "── shellcheck ─────────────────────────────────────────────────────────"
    # Runs in its own task on the shellcheck image; see ci/tasks/shellcheck.yml.
    # Here we assert it was not skipped, because a lint stage that silently omits
    # the only linter for the repository's largest language is the exact shape of
    # false assurance this pipeline keeps rediscovering.
    if [ ! -f ../shellcheck-report/status ]; then
      echo "ERROR: no shellcheck report. The shellcheck task did not run." >&2
      echo "This is not a pass — 3,785 lines of shell went unchecked." >&2
      exit 1
    fi
    cat ../shellcheck-report/status

    echo "── shell syntax ───────────────────────────────────────────────────────"
    find . -path ./.git -prune -o -name '*.sh' -print -exec bash -n {} \;

    echo "── python syntax ──────────────────────────────────────────────────────"
    python -m compileall -q scripts test

    echo "── yaml parses ────────────────────────────────────────────────────────"
    python -m pip install --quiet --disable-pip-version-check \
      --require-hashes -r ci/requirements.txt
    python - <<'PY'
import glob, sys, yaml
bad = 0
targets = sorted(
    glob.glob('.github/workflows/*.yml')
    + glob.glob('ci/**/*.yml', recursive=True)
    + ['platform/MANIFEST.yml', 'automation-policy.yml'])
for f in targets:
    try:
        yaml.safe_load(open(f, encoding='utf-8'))
    except Exception as exc:
        print(f"FAIL {f}: {exc}")
        bad = 1
print(f"{len(targets)} YAML files parse" if not bad else "")
sys.exit(bad)
PY

    echo "── concourse pipeline structure ───────────────────────────────────────"
    # The checks `fly validate-pipeline` does not do: task files that exist,
    # scripts that exist, params the task actually declares, and the
    # no-third-party-resource-types rule this pipeline claims for itself.
    python scripts/validate-pipeline.py

    echo "── test/manifest.txt names every test file (TheHub #60980) ────────────"
    # The one list of test files. Fails on a test/*.test.py or test/*.test.js
    # it does not name (that file would run nowhere) and on an entry with no
    # file behind it. This stage and the test stage below run what it lists;
    # neither names a test file itself.
    python scripts/test-manifest.py check

    echo "── lint-stage test files (test/manifest.txt: lint) ────────────────────"
    # Here rather than under `test` because they need PyYAML, which this stage
    # has just installed from ci/requirements.txt.
    python scripts/test-manifest.py run --stage lint --node-missing skip

    echo "── gate records: key validation, failed gates recorded (TheHub #60981) ─"
    # Needs PyYAML: the writer reads the checklist ids from .sdlc/process.yaml.
    python test/gate-record.test.py

    echo "── platform validator: gate commands name evidence/ (TheHub #60981) ───"
    python test/validate-platform.test.py

    # ADAPT: your formatter and type checker.
    echo "ADAPT: formatter --check, type checker"
    ;;

  test)
    echo "── dashboard generator tests ──────────────────────────────────────────"
    python test/dashboard.test.py

    echo "── control liveness counts records, not directories (TheHub #60981) ───"
    python test/control-liveness.test.py

    echo "── IaC lane gate tests (#59989 / #60071) ───────────────────────────────"
    python test/checkov-gate.test.py

    echo "── SCA lane gate tests: gate by default, report-only for upload (#133) ─"
    python test/grype-gate.test.py

    echo "── container-scan lane: no image is a failure, not a pass (#60935) ────"
    python test/trivy-gate.test.py

    echo "── POA&M due dates: parse, count, overdue, --check (#60977) ───────────"
    python test/poam.test.py

    echo "── JUnit wrapper tests (unit results to MyKronos) ─────────────────────"
    python test/junit-suite.test.py

    echo "── test-stage test files (test/manifest.txt: test) ────────────────────"
    # Every entry the manifest tags `test`, in its order; the lint stage checks
    # the manifest names every test file. A failure does not stop the files
    # after it, and the summary names each one. The .js entry needs node, which
    # this Python image does not have: it says so and is not counted as a pass.
    # GitHub Actions 'Unit suites' (unit-results.yml, on every PR) runs it with
    # node, as `./keel check` does.
    python scripts/test-manifest.py run --stage test --node-missing skip

    echo "── guard hook self-test ───────────────────────────────────────────────"
    # TEST beats EXAMINE. Three real defects in these guards were found only by
    # exercising them (POAM-002/003/004).
    bash .claude/hooks/selftest.sh

    echo "── guard hook bypass corpus (TheHub #60818) ───────────────────────────"
    # selftest.sh was green while the keel#93 bypasses worked. This replays every
    # previously fixed bypass through the real hooks, in both parser modes, and
    # fails if any is allowed again. Needs PyYAML, so install it here as lint does.
    python -m pip install --quiet --disable-pip-version-check       --require-hashes -r ci/requirements.txt
    python test/hook-bypass-corpus.test.py

    echo "── platform release: signed, and an unsigned one is refused (#144) ─────"
    # After the pip install above: the release.yml checks need PyYAML.
    python test/platform-release.test.py
    # keel's own lanes (supply-chain.sh, release.yml). Project-owned and
    # separate from the platform-owned test above, because a fork adapts
    # these files and must be able to edit the test that asserts on them.
    python test/supply-chain.test.py

    echo "── agent assurance (AIC-12 structural) ────────────────────────────────"
    bash evals/run-agent-evals.sh

    # ADAPT (forks): unit and integration tests for application code, with a
    # coverage floor (80% is a sensible start) AND no drop against main — a drop
    # fails even above the floor, or a large untested change passes by diluting
    # an already-high number. Add the threshold param to ci/tasks/ci-stage.yml in
    # the same change as the gate that reads it.
    #
    # MUST include the negative-case test for every control the threat model
    # allocated — the test proving the control DENIES is the security evidence.
    #
    # keel has no application code, so it has no coverage step. There used to be
    # one that echoed "ADAPT: assert coverage >= 80%" and measured nothing, with
    # COVERAGE_THRESHOLD="80" set on the job (TheHub #60850). An unmeasured
    # threshold reads as a control; its absence does not.
    ;;

  full-suite)
    # TEMPLATE: every test, including the slow ones, and E2E for critical
    # journeys only. Few. Slow, brittle, and irreplaceable for proving the whole
    # thing hangs together.
    echo "ERROR: STAGE=full-suite is a TEMPLATE stage and has not been adapted." >&2
    echo "keel's own pipeline does not run it (TheHub #60850): it used to echo" >&2
    echo "ADAPT lines and exit 0, which is a green job that verified nothing." >&2
    echo "Replace this branch with the real slow suite before wiring the job." >&2
    exit 1
    ;;

  *)
    echo "ERROR: unknown STAGE '${STAGE}'." >&2
    exit 1
    ;;
esac
