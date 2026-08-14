#!/usr/bin/env bash
# Platform integrity. Refs: #42
#
# Ported from the pr-governance.yml job of the same name. That workflow stays
# enabled and keeps running these on pull requests, where they are a required
# check. This copy covers what a PR check cannot: a change that reaches main
# without one.
set -euo pipefail

cd repo

python -m pip install --quiet --disable-pip-version-check pyyaml

# Verifies agent tool grants match docs/compliance/ai-inventory.md, skills are
# registered, actions are SHA-pinned, workflows declare least-privilege
# permissions, and no generated evidence has been hand-placed in the tree.
echo "── validate-platform ──────────────────────────────────────────────────────"
python scripts/validate-platform.py

# Per the control-assessment skill: TEST beats EXAMINE. Three real defects in
# these guards were found only by exercising them (POAM-002/003/004), including
# one that blocked edits REMOVING a secret. Four assertions in there are
# regression tests for those.
# ── TEST SUITES MOVED OUT, 2026-08-13 ────────────────────────────────────────
# The guard self-test, the dashboard generator tests and the agent evals used to
# run here. They are test suites, and they now run in the `test` job — which
# until today echoed "ADAPT" and passed while every real test in the repository
# ran under a job called "platform integrity".
#
# Nothing lost coverage: both jobs run on every main commit. What changed is that
# each job's name is now true. This one verifies the platform's own control
# integrity — agent tool grants against the inventory, skill registration, action
# SHA pinning, workflow permissions, evidence integrity — and the job called
# `test` runs the tests.
echo
echo "Test suites run in the \`test\` job (ci/scripts/ci-stage.sh), not here."
