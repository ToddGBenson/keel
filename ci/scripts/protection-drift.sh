#!/usr/bin/env bash
# Branch-protection drift. Refs: TheHub #60979
#
# Compares main's live GitHub protection with .sdlc/protection.yaml, every
# morning, and goes red on any DRIFT. GET requests only: this job can see
# drift, never repair it. Repairing it is the owner's act (ci/README.md,
# "Branch protection").
#
# GH_TOKEN is a fine-grained token with Administration: read-only on this one
# repository, read from the credential manager as ((github_protection_token)).
# Vault seals on every reboot, so "no token" is an expected state here, and it
# must fail the lane, not read as "no drift". Nothing below prints it: no
# `set -x`, and configure-github.sh hands it to curl on stdin.
set -euo pipefail

if [ -z "${GH_TOKEN:-}" ]; then
  echo "ERROR: GH_TOKEN is empty. ((github_protection_token)) did not resolve." >&2
  echo "  This is not a pass: protection was not read. Store a fine-grained token" >&2
  echo "  (Administration: read-only, this repository only) in the credential" >&2
  echo "  manager; ci/README.md, 'protection-drift', has the steps." >&2
  exit 1
fi
: "${REPO_SLUG:?REPO_SLUG is required (owner/name)}"

cd repo

python -m pip install --quiet --disable-pip-version-check \
  --require-hashes -r ci/requirements.txt

bash scripts/configure-github.sh --verify-only --repo "$REPO_SLUG"
