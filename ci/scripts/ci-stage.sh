#!/usr/bin/env bash
# CI stage — build, lint, test, or full-suite. Refs: #42
#
# ── ADAPT ME ──────────────────────────────────────────────────────────────────
# These are the same stubs the Actions workflow carried, moved rather than
# invented. Replace the commands with your toolchain. The STRUCTURE is the
# process control: required checks, coverage that cannot drop, fail-on-new rather
# than fail-on-total.
#
# Being a real script rather than YAML `run:` blocks is the one genuine gain from
# the port — you can execute this locally, exactly as CI does, with
# `STAGE=test bash ci/scripts/ci-stage.sh` from a directory containing `repo/`.
set -euo pipefail

: "${STAGE:?STAGE is required (build|lint|test|full-suite)}"

case "${STAGE}" in

  build)
    echo "ADAPT: language setup + dependency cache."
    echo "Cache dependencies, never cache RESULTS — a cached test result is not evidence."
    echo
    echo "ADAPT: install with a frozen lockfile — integrity verified (SR-3, SR-4)"
    echo "  npm ci                                    # not \`npm install\`"
    echo "  pip install -r requirements.txt --require-hashes"
    echo "  go mod download && go mod verify"
    echo
    echo "ADAPT: build command"
    ;;

  lint)
    echo "ADAPT: linter"
    echo "ADAPT: type checker"
    echo "ADAPT: formatter --check"
    ;;

  test)
    : "${COVERAGE_THRESHOLD:?COVERAGE_THRESHOLD is required}"
    echo "ADAPT: unit test command with coverage output"
    echo
    echo "ADAPT: integration tests against real collaborators."
    echo "Unit-mocked authz proves nothing about the real authorizer, and mocked"
    echo "persistence proves nothing about migrations."
    echo
    echo "MUST include the negative-case tests for every allocated control —"
    echo "the test proving the control DENIES is the security evidence (SA-11)."
    echo
    echo "ADAPT: assert coverage >= ${COVERAGE_THRESHOLD}%"
    echo "A coverage DROP vs. main fails even when above the threshold — otherwise"
    echo "a large untested change passes by diluting an already-high number."
    echo
    # Evidence of a FAILING run is evidence too, which is why this task always
    # declares the output rather than writing it only on success.
    echo "ADAPT: copy test-results/ and coverage/ into ../test-evidence/"
    ;;

  full-suite)
    echo "ADAPT: every test, including the slow ones"
    echo "ADAPT: E2E — critical journeys only."
    echo "Few. Slow, brittle, and irreplaceable for proving the whole hangs together."
    ;;

  *)
    echo "ERROR: unknown STAGE '${STAGE}'." >&2
    exit 1
    ;;
esac
