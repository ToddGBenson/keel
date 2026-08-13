#!/usr/bin/env bash
# IaC & configuration scanning. Refs: #42
set -euo pipefail

# The pin is checked after the presence test below, not before it. A repository
# with no IaC must not go red over a tool version it was never going to use.

# Is there any IaC to scan? A repo with no Terraform/CloudFormation/K8s/Dockerfile
# is a legitimate state, and the scan must say "nothing to scan" rather than
# either failing the gate or — worse — reporting green as though it had checked
# something.
# `-print -quit` and no pipe — see the note in ci/scripts/codeql.sh. The piped
# form inverts under `set -o pipefail` on large trees and reports "nothing to
# scan" with exit 0.
if [ -z "$(find repo -path repo/.git -prune -o \
     \( -name '*.tf' -o -name '*.tf.json' -o -name 'Dockerfile*' \
        -o -name 'docker-compose*.y*ml' -o -name '*.template.y*ml' \
        -o -path '*/k8s/*.y*ml' -o -path '*/helm/*' \) -print -quit 2>/dev/null)" ]; then
  cat <<'EOF'

================================================================================
IaC scan: no infrastructure files found

Nothing to scan. THIS IS NOT A PASS for CM-6/CM-7 — it means the control is not
applicable yet. It becomes applicable the moment you add a Dockerfile or a
Terraform module.
================================================================================

EOF
  exit 0
fi

# IaC is present, so the pin is genuinely required now. An unpinned scanner
# produces results you cannot reproduce, and the finding count is what gates this
# job.
: "${CHECKOV_VERSION:?CHECKOV_VERSION is required — there IS IaC to scan}"

python -m pip install --quiet --disable-pip-version-check "checkov==${CHECKOV_VERSION}"
checkov --version

# soft-fail: gate on the findings below, not on the tool's exit code. Checkov
# exits non-zero for conditions that are not findings, and a gate that fails for
# plumbing reasons trains people to ignore it (L0007).
checkov --directory repo \
  --quiet \
  --soft-fail \
  --output sarif \
  --output-file-path iac-results || true

sarif="iac-results/results.sarif"

# DEFECT FIXED 2026-08-07, preserved here: the Actions version ran the upload
# with `if: always()` against a SARIF checkov had not produced, so the step failed
# for a reason unrelated to any finding. Key on the file existing.
if [ ! -f "${sarif}" ]; then
  echo "ERROR: checkov produced no SARIF at ${sarif}." >&2
  echo "IaC files were present, so this is a tool failure, not a clean result." >&2
  exit 1
fi

n="$(python3 -c '
import json
doc = json.load(open("iac-results/results.sarif"))
print(sum(len(r.get("results", [])) for r in doc.get("runs", [])))
')"

echo "checkov findings: ${n}"

# The actual gate: fail on findings, not on tooling noise.
if [ "${n}" -ne 0 ]; then
  echo "ERROR: ${n} IaC misconfiguration(s) — see iac-results/results.sarif" >&2
  exit 1
fi
