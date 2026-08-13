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
