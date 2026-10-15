#!/usr/bin/env bash
# Fail fast if Mykronos is unreachable. Refs: #42
#
# Better to stop in ten seconds than scan for twenty minutes and find at upload
# time that the results have nowhere to go — and silently skipping is not an
# option.
set -euo pipefail

: "${MYKRONOS_INGESTION_URL:?MYKRONOS_INGESTION_URL is required}"
: "${MYKRONOS_INGESTION_TOKEN:?MYKRONOS_INGESTION_TOKEN is required}"

echo "Checking ${MYKRONOS_INGESTION_URL}/api/ingest/health"

# --max-time 20, matching the Actions version. The token goes in a header from an
# environment variable, never on the command line, so it cannot surface in a
# process listing.
#
# --retry re-tries a connection that was refused, reset or timed out and a 5xx,
# and does NOT re-try the 401 that means the token is wrong: re-try being unable
# to ask, never the answer (the same shape as mykronos's own preflight, PS-12).
# On 2026-10-15 one 20s timeout at 15:56 UTC failed iac, mykronos-sast,
# mykronos-secrets and mykronos-atlas together, and they stayed red until the
# next commit.
curl --fail --silent --show-error --connect-timeout 10 --max-time 20   --retry 4 --retry-delay 5 --retry-connrefused \
  -H "Authorization: Bearer ${MYKRONOS_INGESTION_TOKEN}" \
  "${MYKRONOS_INGESTION_URL}/api/ingest/health" > /dev/null

echo "Mykronos is reachable."
