#!/usr/bin/env bash
# Is the SBOM actually evidence? Refs: #42
set -euo pipefail

if [ ! -f sbom/sbom.json ]; then
  echo "No SBOM produced by syft. Nothing to check."
  exit 0
fi

COMPONENTS="$(python3 -c '
import json, sys
doc = json.load(open("sbom/sbom.json"))
print(len(doc.get("components") or []) + len(doc.get("packages") or []))
')"

echo "SBOM lists ${COMPONENTS} component(s)"

# An SBOM with nothing in it is not evidence, and archiving one is worse than
# recording none: the dashboard would show an SBOM present for a file that
# describes no software.
#
# Usually this means the repository pins nothing. Syft reads resolved dependency
# sets — lockfiles, requirements.txt, installed packages — and a project
# declaring ranges in pyproject.toml with no lockfile has no resolved set to
# record. That is a fact about the repository, not a tool failure, and the right
# response is to say so rather than to emit a confident empty document.
if [ "${COMPONENTS}" -eq 0 ]; then
  cat <<'EOF'

WARNING: No components found. This repository has no lockfile or other resolved
dependency set for syft to read, so there is no bill of materials to record.
Not archiving.

EOF
  rm -f sbom/sbom.json
fi
