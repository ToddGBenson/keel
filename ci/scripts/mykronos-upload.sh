#!/usr/bin/env bash
# Normalize scanner output and upload it to the Mykronos data lake. Refs: #42
#
# Port of the `upload-results` composite action. That action installs the
# `mykronos` package at a pinned ref and calls `python -m mykronos.upload`; so
# does this. The adapters and the FindingSubmission schema they target keep
# exactly one definition, which is the reason that action exists rather than a
# snippet copy-pasted into ten templates.
#
# This script must stay argument-compatible with `mykronos.upload`. If that CLI
# changes, this breaks loudly at the pinned ref rather than uploading something
# subtly wrong.
set -euo pipefail

: "${CAPABILITY:?CAPABILITY is required}"
: "${TOOL:?TOOL is required}"
: "${MYKRONOS_INGESTION_URL:?MYKRONOS_INGESTION_URL is required}"
: "${MYKRONOS_INGESTION_TOKEN:?MYKRONOS_INGESTION_TOKEN is required}"
: "${MYKRONOS_REF:?MYKRONOS_REF is required — pin the package, never track a branch}"
: "${REPO_SLUG:?REPO_SLUG is required}"

BRANCH="${BRANCH:-main}"
TOOL_VERSION="${TOOL_VERSION:-}"
SEVERITY_THRESHOLD="${SEVERITY_THRESHOLD:-low}"
BLOCKING="${BLOCKING:-false}"

# `mykronos-results` is an OPTIONAL input, so it may be absent when the scan step
# never got far enough to produce one — which is the whole point of running this
# on `ensure:`. The uploader distinguishes the cases by CONTENT, not by the
# directory's existence: an empty directory yields no archivable candidates and
# no findings, which is how "ran and broke" is recorded distinctly from a clean
# scan. Creating it here is therefore safe and keeps `--results-path` valid.
mkdir -p mykronos-results

COMMIT_SHA="$(git -C repo rev-parse HEAD)"

# ── Trigger attribution ───────────────────────────────────────────────────────
# Concourse does not report WHY a build started, so this is inferred rather than
# read. BUILD_CREATED_BY is set only when a human triggered the build, which is
# the one case we can identify with certainty. Everything else is attributed to
# the resource that most likely fired it, and the scheduled jobs pass
# TRIGGERED_BY explicitly to remove the guess.
#
# `manual`, `push` and `schedule` are all members of the platform's TriggeredBy
# enum, so no value here is invented.
if [ -n "${TRIGGERED_BY:-}" ]; then
  trigger="${TRIGGERED_BY}"
elif [ -n "${BUILD_CREATED_BY:-}" ]; then
  trigger="manual"
else
  trigger="push"
fi

echo "Installing mykronos at ${MYKRONOS_REF}"
python -m pip install --quiet --disable-pip-version-check \
  "mykronos @ git+https://github.com/ToddGBenson/mykronos@${MYKRONOS_REF}#subdirectory=backend"

echo "Uploading ${CAPABILITY}/${TOOL} results for ${REPO_SLUG}@${COMMIT_SHA}"

# The token is on the command line, which means it is visible in a process
# listing inside this container. `mykronos.upload` declares --token required and
# offers no environment variable, so there is no alternative available today; the
# upstream composite action has the same exposure.
#
# An earlier version of this file carried a comment claiming the token was passed
# through the environment "so it never appears in a process listing", next to a
# `MYKRONOS_TOKEN=... python ... --token "${MYKRONOS_TOKEN}"` line that did not
# work at all — the prefix is applied after the argument list is expanded, so
# under `set -u` the script aborted before the CLI ever ran. A false control
# claim sitting on top of dead code. Fixed both; asked upstream for env support.
#
# --workspace is the repository root, not the build directory: findings carry
# paths relative to it, and getting this wrong makes every fingerprint unstable.
#
# --pr-number 0 is normalised to null by the uploader. Mykronos no longer scans
# pull requests anywhere — the three generated workflows are dispatch-only — so
# no build reaching this script is ever a PR build.
python -m mykronos.upload \
  --capability "${CAPABILITY}" \
  --tool "${TOOL}" \
  --tool-version "${TOOL_VERSION}" \
  --results-path "mykronos-results" \
  --ingestion-url "${MYKRONOS_INGESTION_URL}" \
  --token "${MYKRONOS_INGESTION_TOKEN}" \
  --repo "${REPO_SLUG}" \
  --commit-sha "${COMMIT_SHA}" \
  --branch "${BRANCH}" \
  --workflow-run-id "${BUILD_ID:-}" \
  --triggered-by "${trigger}" \
  --pr-number 0 \
  --workspace "${PWD}/repo" \
  --severity-threshold "${SEVERITY_THRESHOLD}" \
  --blocking "${BLOCKING}"
