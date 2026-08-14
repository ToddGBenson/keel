#!/usr/bin/env bash
# CI stage — build, lint, test, or full-suite. Refs: #42
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
    python -m pip install --quiet --disable-pip-version-check pyyaml
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

    # ADAPT: your formatter and type checker.
    echo "ADAPT: formatter --check, type checker"
    ;;

  test)
    echo "── dashboard generator tests ──────────────────────────────────────────"
    python test/dashboard.test.py

    echo "── guard hook self-test ───────────────────────────────────────────────"
    # TEST beats EXAMINE. Three real defects in these guards were found only by
    # exercising them (POAM-002/003/004).
    bash .claude/hooks/selftest.sh

    echo "── agent assurance (AIC-12 structural) ────────────────────────────────"
    bash evals/run-agent-evals.sh

    echo "── self-review check tests ────────────────────────────────────────────"
    # Not a silent skip: scripts/selfreview-check.js is loaded only by
    # .github/workflows/pr-governance.yml, which runs on GitHub Actions and
    # nowhere else. Its 33 assertions run there, in the same job as the code they
    # cover. Adding node to this image to exercise logic Concourse never executes
    # would be ceremony.
    if command -v node >/dev/null 2>&1; then
      node test/selfreview-check.test.js
    else
      echo "Not applicable here — runs in the Actions platform-integrity job,"
      echo "alongside the workflow that is the only consumer of that module."
    fi

    # ADAPT: unit and integration tests for application code, with coverage
    # >= ${COVERAGE_THRESHOLD:-80}% and no drop against main. There is no
    # application code in this repository yet.
    #
    # MUST include the negative-case test for every control the threat model
    # allocated — the test proving the control DENIES is the security evidence.
    echo "── coverage ───────────────────────────────────────────────────────────"
    echo "ADAPT: assert coverage >= ${COVERAGE_THRESHOLD:-80}% and no drop vs main."
    echo "A coverage DROP fails even when above the threshold — otherwise a large"
    echo "untested change passes by diluting an already-high number."
    ;;

  full-suite)
    echo "ADAPT: every test, including the slow ones."
    echo "ADAPT: E2E — critical journeys only. Few. Slow, brittle, and"
    echo "irreplaceable for proving the whole thing hangs together."
    ;;

  *)
    echo "ERROR: unknown STAGE '${STAGE}'." >&2
    exit 1
    ;;
esac
