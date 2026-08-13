#!/usr/bin/env bash
# Suppression audit. Refs: #42
#
# A suppression with no rationale and no expiry is a control failure. Blanket
# suppressions are how a scanner quietly stops being a control.
set -euo pipefail

cd repo

PATTERN='nosec|noqa|eslint-disable|codeql\[|# type: ignore|checkov:skip|trivy:ignore'

# Scan CODE, not prose. The first run of this job in Actions failed against the
# platform's own documentation, which necessarily quotes these tokens while
# explaining the rule — docs/, skills, and lesson files all discuss suppressions
# by name.
#
# This is L0007: a checker that fires on documentation about the thing gets
# muted, and a muted control detects nothing. Same class as L0002. Restrict to
# source extensions and exclude the directories whose job is to talk about this.
#
# ci/ is excluded for the same reason — this script and its neighbours quote the
# tokens while implementing the rule.
set +e
HITS="$(grep -rInE "${PATTERN}" \
  --include='*.py'   --include='*.js'   --include='*.ts'  --include='*.tsx' \
  --include='*.jsx'  --include='*.go'   --include='*.rs'  --include='*.rb' \
  --include='*.java' --include='*.cs'   --include='*.php' --include='*.sh' \
  --include='*.tf'   --include='*.yaml' --include='*.yml' \
  --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor \
  --exclude-dir=.github --exclude-dir=docs --exclude-dir=.claude \
  --exclude-dir=platform --exclude-dir=evidence --exclude-dir=scripts \
  --exclude-dir=ci .)"
set -e

if [ -z "${HITS}" ]; then
  echo "No suppressions found."
  exit 0
fi

echo "${HITS}" > /tmp/all_suppressions.txt
TOTAL="$(wc -l < /tmp/all_suppressions.txt)"

# A valid suppression cites an issue (#123) AND an expiry (expires: YYYY-MM-DD).
BAD="$(grep -vE '#[0-9]+' /tmp/all_suppressions.txt \
       | grep -viE 'expires?:? *[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)"

echo "Total suppressions: ${TOTAL}"

if [ -n "${BAD}" ]; then
  cat >&2 <<EOF

================================================================================
Suppressions missing a rationale (issue ref) and/or an expiry date:

${BAD}

Every suppression needs an issue reference and an \`expires: YYYY-MM-DD\`.
Suppressions are reviewed quarterly. An unjustified one fails G4.
================================================================================

EOF
  exit 1
fi

echo "All suppressions carry an issue reference and an expiry date."
