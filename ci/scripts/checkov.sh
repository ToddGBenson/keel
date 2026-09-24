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

  # …and now SAY it somewhere other than this log. [#59989/#60071]
  #
  # The paragraph above has been correct and unread since this script was
  # written. Exiting 0 with no output made "nothing to scan" indistinguishable
  # from "scanned and found nothing" everywhere downstream: the job goes green,
  # and the platform records either a clean scan or — if the lane uploads with
  # no file at all — a FAILED one, because `normalize_results` treats a missing
  # results directory as a broken scanner rather than an absent subject. Both
  # readings are wrong, in opposite directions.
  #
  # So write a real SARIF carrying the marker the platform now understands. The
  # property bag is SARIF 2.1.0 §3.8, which exists for exactly this, so a tool
  # or viewer that does not know the key ignores it and sees an empty run.
  #
  # `reason` is the tool's own words on purpose: the platform cannot know which
  # file types were looked for, and a status with no reason is what gets argued
  # about six months later.
  mkdir -p iac-results
  cat > iac-results/results.sarif <<'EOF'
{
  "version": "2.1.0",
  "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
  "runs": [
    {
      "tool": {
        "driver": {
          "name": "checkov",
          "informationUri": "https://www.checkov.io/"
        }
      },
      "results": [],
      "properties": {
        "mykronos": {
          "scanStatus": "no_applicable_targets",
          "reason": "No IaC to scan: no *.tf, *.tf.json, Dockerfile*, docker-compose*.yml, *.template.yml, k8s manifest or helm chart anywhere in the repository. The control is not applicable, not satisfied."
        }
      }
    }
  ]
}
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
