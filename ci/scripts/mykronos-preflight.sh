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
curl --fail --silent --show-error --max-time 20 \
  -H "Authorization: Bearer ${MYKRONOS_INGESTION_TOKEN}" \
  "${MYKRONOS_INGESTION_URL}/api/ingest/health" > /dev/null

echo "Mykronos is reachable."
