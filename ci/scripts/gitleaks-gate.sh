#!/usr/bin/env bash
# The keel security lane's secret gate. Refs: #42
#
# Any hit fails. If one fires, the correct response is to ROTATE the credential,
# then remove it. A deleted commit is not a rotated credential.
set -euo pipefail

report="mykronos-results/gitleaks.json"

# gitleaks writes nothing when it finds nothing, so an absent report is the clean
# case — but only if the scan actually ran. The scan task declares this file's
# directory as an output, so the directory existing and the file not is the
# normal clean result.
if [ ! -d "mykronos-results" ]; then
  echo "ERROR: no results directory — the scan did not run. This is not a pass." >&2
  exit 1
fi

if [ ! -f "${report}" ]; then
  echo "No secrets detected."
  exit 0
fi

# ── THIS GATE MUST FAIL CLOSED ────────────────────────────────────────────────
# The first version caught JSONDecodeError and returned 0, and returned 0 for any
# non-list document. A truncated report — worker killed mid-write, disk full — or
# a gitleaks output-format change therefore read as "no secrets detected" and
# exited 0. Two independent fail-open paths in the one control that implements
# IA-5.
#
# An unreadable report is now a failure. If this gate cannot tell whether there
# are secrets, it does not get to say there are none.
if ! COUNT="$(python3 -c '
import json, sys

with open("mykronos-results/gitleaks.json") as handle:
    doc = json.load(handle)

if not isinstance(doc, list):
    print(f"gitleaks report is {type(doc).__name__}, expected a list", file=sys.stderr)
    sys.exit(1)

print(len(doc))
')"; then
  cat >&2 <<'EOF'

ERROR: the gitleaks report exists but could not be parsed.

This is NOT a pass. A malformed report means the scan's result is unknown, and an
unknown result must not be reported as clean (IA-5). Usual causes: the task was
killed mid-write, the worker ran out of disk, or gitleaks changed its output
format — check the scan task's log before assuming the repository is clean.
EOF
  exit 1
fi

if [ "${COUNT}" -eq 0 ]; then
  echo "No secrets detected."
  exit 0
fi

cat >&2 <<EOF

================================================================================
${COUNT} secret(s) detected (IA-5).

The report is redacted, so this build log does not carry the credential. Read
mykronos-results/gitleaks.json in the build artifacts for locations.

ROTATE the credential first. Removing the commit is not rotation — the value
was published the moment it was pushed, and history rewriting does not unpublish
it.
================================================================================

EOF
exit 1
