#!/usr/bin/env bash
# Platform integrity. Refs: #42
#
# Ported from the pr-governance.yml job of the same name. In keel that workflow
# is retired (TheHub #60849, 2026-10-20) — Actions cannot start, and nothing
# requires it — so this copy, after the merge, is the only run. A fork that runs
# Actions gets both: pre-merge prevention there, post-merge detection here.
set -euo pipefail

cd repo

python -m pip install --quiet --disable-pip-version-check \
  --require-hashes -r ci/requirements.txt

# Verifies agent tool grants match docs/compliance/ai-inventory.md, skills are
# registered, actions are SHA-pinned, workflows declare least-privilege
# permissions, and no generated evidence has been hand-placed in the tree.
# keel is a TEMPLATE. It ships no artifact, so it has no build to break — its
# delivery mechanism is scripts/sync-platform.sh, and the contract that mechanism
# obeys is platform/MANIFEST.yml. That makes the manifest the closest thing this
# repository has to a build output, and nothing checked it until #56.
#
# The failure is silent in the worst way: an unclassified path is never delivered
# to a fork, and no fork can notice a file it was never sent. `ci/` — the whole
# pipeline — sat unclassified after being added. So did `keel`, the CLI.
echo "── platform manifest (the template's delivery contract) ───────────────────"
python scripts/validate-manifest.py

echo "── validate-platform ──────────────────────────────────────────────────────"
python scripts/validate-platform.py

# ── control liveness (POAM-018) ───────────────────────────────────────────────
# Existence was already checked; USE was not. Five of six gates had never fired
# and fourteen controls were marked satisfied on them, and nothing noticed —
# because nothing was measuring whether a control had ever done anything.
#
# --check is a RATCHET, not an alarm. The known zeros are accepted in POAM-018
# and do not fail the build; a check that is red from birth gets muted (L0007).
# It fails when the number gets worse.
echo "── control liveness (POAM-018) ────────────────────────────────────────────"
python scripts/control-liveness.py --check

# ── POA&M due dates (TheHub #60977) ───────────────────────────────────────────
# POAM-010, POAM-014 and POAM-016 went 38-40 days past due and no lane noticed.
# This job runs daily at 06:00, so an open High or Critical item past its due
# date turns it red the morning after. Re-dating an item is an edit to
# docs/compliance/poam.md (strike the old date, write the new one), which is
# reviewed like any other change; it cannot be done quietly.
# Overdue Medium/Low items are printed but do not fail the job.
# --history: an open item is gated at the highest Risk any committed version of
# poam.md gave it, so lowering High to Medium does not get an overdue item past
# this job (keel #146 review). The repo resource is a full clone, and git is in
# the python image; if git cannot answer, poam.py exits 2 rather than gate on less.
echo "── POA&M due dates (TheHub #60977) ────────────────────────────────────────"
python scripts/poam.py --check --history

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
