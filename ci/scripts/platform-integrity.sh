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
echo "── guard hook self-test ───────────────────────────────────────────────────"
bash .claude/hooks/selftest.sh

# The dashboard generator has real logic (truncation disclosure, escaping,
# degraded rendering). Its tests are mutation-verified — removing the truncation
# notice or the escaper each fails 2 assertions.
echo "── dashboard generator tests ──────────────────────────────────────────────"
python test/dashboard.test.py

# test/selfreview-check.test.js is NOT run here, and that is not a silent skip.
# It tests scripts/selfreview-check.js, which is only ever loaded by
# .github/workflows/pr-governance.yml — a workflow that runs on GitHub Actions
# and nowhere else. The test runs there, in the same job, on the same runner that
# executes the code. Running it in this container would need node in the image to
# exercise logic this engine never runs.
echo "── self-review check tests ────────────────────────────────────────────────"
echo "Not applicable here: pr-governance.yml runs only on GitHub Actions, and its"
echo "tests run there. See the platform-integrity job in that workflow."
