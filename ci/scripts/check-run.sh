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
# in the build log (`--fail-with-body`). The retry is this script's, not curl's: it
# retries only curl's transient exits (6, 7, 28, 35, 52, 56) and a 408, 429 or 5xx,
# so a 4xx is never retried into a different answer.
#
# [TheHub #62097] An unreachable reporter must not turn a passing suite red. A report
# of a PASSING suite that cannot get through is retried five times over about two
# minutes; if every try fails it posts nothing that says `failure` (at most one
# `cancelled`, "no verdict reached", which MyKronos never lets replace a failure),
# and exits non-zero so Concourse shows the error. The pipeline wraps that step in
# `try:` so its failure is not the job's, and the job's own `on_failure` hook does
# not post `failure` for a suite that passed. A suite that really FAILED still posts
# `failure`, with the same retries, and if that post is unreachable the step exits
# non-zero and the build stays red in Concourse.
set -eu

: "${MYKRONOS_INGESTION_URL:?MYKRONOS_INGESTION_URL is required}"
: "${MYKRONOS_INGESTION_TOKEN:?MYKRONOS_INGESTION_TOKEN is required}"
: "${REPO_SLUG:?REPO_SLUG is required}"
: "${JOB:?JOB is required}"
: "${PHASE:?PHASE is required (start|end)}"

# The git resource leaves a detached HEAD, so .git/HEAD holds the sha itself.
# Anything else (a branch ref, a short sha, no checkout) is refused, not guessed:
# a check on the wrong commit is worse than none.
#
# [TheHub #61778] pr-checks reports on a pull request head, not on repo/'s commit.
# It names a file holding only that sha (HEAD_FILE, written by pr-pick.sh) rather
# than mapping the pull request's checkout over repo/: this script and its task file
# always come from main's repo/, so no pull-request code runs with the token.
HEAD_FILE="${HEAD_FILE:-repo/.git/HEAD}"
SHA=""
if [ -f "$HEAD_FILE" ]; then
  SHA=$(tr -d ' \n\r\t' < "$HEAD_FILE")
fi
case "$SHA" in
  *[!0-9a-f]*) SHA="" ;;
esac
if [ "${#SHA}" -ne 40 ]; then
  echo "No checked-out commit to report on, so ${JOB} posted nothing."
  # [TheHub #61778] pr-checks: a run that found no pull request head to judge
  # (or failed before checking one out) has nothing to report on, and that is
  # not an error. Only that job sets this; the commit chain still refuses.
  if [ "${NO_COMMIT_OK:-}" = "1" ]; then
    exit 0
  fi
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
body_for() {
  printf '{"repo_full_name":"%s","commit_sha":"%s","job":"%s","phase":"%s","conclusion":%s}' \
    "$REPO_SLUG" "$SHA" "$JOB" "$PHASE" "$1"
}

# One POST, retried on a transient failure. Returns 0 when MyKronos answered 2xx,
# 1 when it refused (an answer: not retried), 2 when it never answered (unreachable,
# or a 408, 429 or 5xx on every try). The token comes from the environment and goes
# in a header, the same way mykronos-preflight.sh sends it.
#
# The backoff is 10, 20, 30 and 60 seconds between five tries: about two minutes.
# Five tries of --max-time 45 plus that is 345s, and the one `cancelled` post after
# them is 45s more, so the 10m step timeout in ci/pipeline.yml holds with room.
post() {
  _body=$1
  _tries=${2:-5}
  _try=1
  while :; do
    _rc=0
    _out=$(curl --fail-with-body --silent --show-error --connect-timeout 10 --max-time 45 \
      -w '\n%{http_code}' \
      -X POST \
      -H "Authorization: Bearer ${MYKRONOS_INGESTION_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$_body" "${MYKRONOS_INGESTION_URL}/api/ingest/check-runs") || _rc=$?
    _code=$(printf '%s\n' "$_out" | tail -n 1)
    _resp=$(printf '%s\n' "$_out" | sed '$d')
    if [ -n "$_resp" ]; then printf '%s\n' "$_resp"; fi
    if [ "$_rc" -eq 0 ]; then
      return 0
    fi
    _transient=0
    case " 6 7 28 35 52 56 " in *" $_rc "*) _transient=1 ;; esac
    if [ "$_rc" -eq 22 ]; then
      case "$_code" in 408|429|5[0-9][0-9]) _transient=1 ;; esac
    fi
    if [ "$_transient" -eq 0 ]; then
      echo "MyKronos refused the report (curl exit ${_rc}); not retrying." >&2
      return 1
    fi
    if [ "$_try" -ge "$_tries" ]; then
      echo "MyKronos did not answer after ${_try} tries (curl exit ${_rc})." >&2
      return 2
    fi
    case "$_try" in 1) _wait=10 ;; 2) _wait=20 ;; 3) _wait=30 ;; *) _wait=60 ;; esac
    echo "Report try ${_try} failed (curl exit ${_rc}); retrying in ${_wait}s." >&2
    sleep "$_wait"
    _try=$((_try + 1))
  done
}

_status=0
post "$(body_for "$CONCLUSION_JSON")" 5 || _status=$?

if [ "$_status" -eq 0 ]; then
  echo "Reported ${PHASE} for ${JOB} on ${SHA}."
  exit 0
fi

if [ "$_status" -eq 2 ] && [ "$PHASE" = end ] && [ "${CONCLUSION:-}" = success ]; then
  # The suite passed and only the report failed. Say so where MyKronos can be
  # reached, once, as a verdict of "none reached" and never as a failure.
  echo "check-run: reporter unreachable; suite passed. Not reporting failure for ${JOB} on ${SHA}."
  post "$(body_for '"cancelled"')" 1 >/dev/null 2>&1 || true
fi
echo "The ${PHASE} report for ${JOB} on ${SHA} did not get through, so this step fails." >&2
exit 1
