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

COUNT="$(python3 -c '
import json
try:
    doc = json.load(open("mykronos-results/gitleaks.json"))
except (json.JSONDecodeError, FileNotFoundError):
    doc = []
print(len(doc) if isinstance(doc, list) else 0)
')"

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
