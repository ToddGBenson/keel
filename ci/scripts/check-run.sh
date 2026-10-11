#!/bin/sh
# Report a commit-chain job's start or end to MyKronos, which posts it on GitHub
# as the `Concourse / keel` check run. Refs: #107
#
# Concourse never calls GitHub for this. MyKronos posts the check run through its
# own GitHub App with an installation token it mints itself (MyKronos D-136), and
# keeps one check run per commit, so every later report updates the same run. The
# only credential here is the ingestion token the MyKronos lanes already use.
#
# POSIX sh, not bash: the task image is curlimages/curl, which has no bash, no git
# and no jq. That is why the sha is read from .git/HEAD and the body is built with
# printf.
#
# This can fail, on purpose. A refused report is a red step with MyKronos's reason
# in the build log (`--fail-with-body`). The retry is inside curl, on connection
# failures and 5xx only, so a 4xx is never retried into a different answer.
set -eu

: "${MYKRONOS_INGESTION_URL:?MYKRONOS_INGESTION_URL is required}"
: "${MYKRONOS_INGESTION_TOKEN:?MYKRONOS_INGESTION_TOKEN is required}"
: "${REPO_SLUG:?REPO_SLUG is required}"
: "${JOB:?JOB is required}"
: "${PHASE:?PHASE is required (start|end)}"

# The git resource leaves a detached HEAD, so .git/HEAD holds the sha itself.
# Anything else (a branch ref, a short sha, no checkout) is refused, not guessed:
# a check on the wrong commit is worse than none.
SHA=""
if [ -f repo/.git/HEAD ]; then
  SHA=$(tr -d ' \n\r\t' < repo/.git/HEAD)
fi
case "$SHA" in
  *[!0-9a-f]*) SHA="" ;;
esac
if [ "${#SHA}" -ne 40 ]; then
  echo "No checked-out commit to report on, so ${JOB} posted nothing."
  echo "The check stays as it was, and one still in progress blocks."
  exit 1
fi

case "$PHASE" in
  start) CONCLUSION_JSON=null ;;
  end)
    case "${CONCLUSION:-}" in
      success|failure) CONCLUSION_JSON="\"${CONCLUSION}\"" ;;
      *) echo "PHASE=end needs CONCLUSION=success or failure, got '${CONCLUSION:-}'."; exit 1 ;;
    esac
    ;;
  *) echo "PHASE must be start or end, got '${PHASE}'."; exit 1 ;;
esac

# Every value is fixed by ci/pipeline.yml or is the hex sha checked above, so
# nothing here needs escaping.
BODY=$(printf '{"repo_full_name":"%s","commit_sha":"%s","job":"%s","phase":"%s","conclusion":%s}' \
  "$REPO_SLUG" "$SHA" "$JOB" "$PHASE" "$CONCLUSION_JSON")

# The token comes from the environment and goes in a header, the same way
# mykronos-preflight.sh sends it.
curl --fail-with-body --silent --show-error --connect-timeout 10 --max-time 45 \
  --retry 2 --retry-delay 5 --retry-connrefused \
  -X POST \
  -H "Authorization: Bearer ${MYKRONOS_INGESTION_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$BODY" "${MYKRONOS_INGESTION_URL}/api/ingest/check-runs"
echo
echo "Reported ${PHASE} for ${JOB} on ${SHA}."
