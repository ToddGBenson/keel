#!/usr/bin/env bash
# IaC & configuration scanning. Refs: #42
set -euo pipefail

# ── WHY THERE IS NO LONGER A find(1) PRESENCE TEST ────────────────────────────
# [#59989/#60071] This script used to decide whether there was anything to scan
# BEFORE running checkov, with:
#
#   find repo \( -name '*.tf' -o -name 'Dockerfile*' -o -name 'docker-compose*'
#                -o -name '*.template.y*ml' -o -path '*/k8s/*' -o -path '*/helm/*' \)
#
# and on this repository that test returns nothing. It was wrong, and the
# measurement that proved it was sitting in the data lake the whole time: the
# GitHub Actions lane (.github/workflows/mykronos-iac.yml) runs checkov over the
# same repo with NO presence test, and has been reporting
#
#   CKV_GHA_7  .github/workflows/release.yml  HIGH  open
#
# on every push since 2026-09-05. checkov ships frameworks for GitHub Actions,
# GitLab CI, Azure Pipelines, Bitbucket, Ansible, Serverless and OpenAPI — none
# of which that find expression looks for. So the test was not asking "is there
# IaC here", it was asking "is there IaC of the six kinds somebody listed", and
# answering NO on a repository with an open high-severity finding.
#
# Left alone, this would have been worse than what it replaced. The whole point
# of #59989 was that a lane reading as covered when it had scanned nothing is
# false assurance; a lane reading NOT APPLICABLE on a repo with an open high
# finding is the same error made affirmatively.
#
# THE TOOL DECIDES NOW. checkov is the only thing that knows what checkov
# scans, so it is run unconditionally and the number of CHECKS IT PERFORMED
# (`summary.passed + failed + skipped`) is what separates "no subject" from
# "scanned, clean". A list that has to be maintained against a scanner's
# framework support will drift, and drift silently, every time that scanner
# gains a framework.

# The pin is required unconditionally now. It used to be checked only after the
# presence test, so that a repo with no IaC would not go red over a tool version
# it was never going to use — but the tool is always going to be used now, and
# an unpinned scanner produces results you cannot reproduce.
: "${CHECKOV_VERSION:?CHECKOV_VERSION is required}"

python -m pip install --quiet --disable-pip-version-check "checkov==${CHECKOV_VERSION}"
checkov --version

# soft-fail: gate on the findings below, not on the tool's exit code. Checkov
# exits non-zero for conditions that are not findings, and a gate that fails for
# plumbing reasons trains people to ignore it (L0007).
#
# Both formats. The SARIF is what gets uploaded and what carries findings; the
# JSON is the only place checkov reports its `summary` counts, which are the
# numbers this script needs and SARIF has nowhere to put.
checkov --directory repo \
  --quiet \
  --soft-fail \
  --output sarif \
  --output json \
  --output-file-path iac-results \
  || true

# MEASURED, not assumed: with TWO --output flags checkov names its files
# `results_sarif.sarif` and `results_json.json`. With one it writes
# `results.sarif`. The first cut of this rewrite hardcoded the single-output
# name, ran, and reported "checkov produced no SARIF ... this is a tool
# failure" against a SARIF sitting right beside it. Both names are accepted so
# that adding or removing an --output flag cannot resurrect that.
sarif="iac-results/results_sarif.sarif"
[ -f "${sarif}" ] || sarif="iac-results/results.sarif"
report="iac-results/results_json.json"

# DEFECT FIXED 2026-08-07, preserved here: the Actions version ran the upload
# with `if: always()` against a SARIF checkov had not produced, so the step failed
# for a reason unrelated to any finding. Key on the file existing.
if [ ! -f "${sarif}" ]; then
  echo "ERROR: checkov produced no SARIF at ${sarif}." >&2
  echo "checkov ran, so this is a tool failure, not a clean result." >&2
  exit 1
fi

# Checks performed across every framework checkov reported on. With more than
# one framework the JSON is a LIST of report objects, with one it is a single
# object, and treating the two the same is how this kind of parser silently
# reads zero.
resources="$(python3 - "${report}" <<'PY'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.is_file():
    # No JSON is not "nothing to scan". Say so and let the caller fail: a
    # missing report read as zero is exactly the instrument failure this
    # script is being rewritten to stop making.
    print("MISSING")
    raise SystemExit(0)

doc = json.loads(path.read_text() or "null")
reports = doc if isinstance(doc, list) else [doc]
total = 0
for report in reports:
    if not isinstance(report, dict):
        continue
    summary = report.get("summary")
    if isinstance(summary, dict):
        # CHECKS PERFORMED, not `resource_count`. Measured against this
        # repository 2026-09-24: checkov reports
        #     "passed": 715, "failed": 1, "resource_count": 0
        # because the github_actions framework counts no "resources" while
        # checking 716 things. A presence test keyed on resource_count would
        # have declared NO APPLICABLE TARGETS over an open HIGH finding --
        # the same error the find(1) test made, reached by a different route.
        for key in ("passed", "failed", "skipped"):
            total += int(summary.get(key) or 0)
print(total)
PY
)"

if [ "${resources}" = "MISSING" ]; then
  echo "ERROR: checkov produced a SARIF but no JSON report at ${report}." >&2
  echo "Without it there is no way to tell an empty repository from a clean" >&2
  echo "one, and guessing in either direction is the defect this lane had." >&2
  exit 1
fi

echo "checkov performed ${resources} check(s)"

n="$(python3 - "${sarif}" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
print(sum(len(r.get("results", [])) for r in doc.get("runs", [])))
PY
)"

echo "checkov findings: ${n}"

# ── NOTHING TO SCAN ───────────────────────────────────────────────────────────
# checkov itself performed no check, in any framework it supports. That
# is a legitimate state and it is NOT a pass for CM-6/CM-7 — the control is not
# applicable yet, and becomes applicable the moment the repository gains
# something checkov understands.
#
# It is recorded in the SARIF rather than only printed, because the paragraph
# this script used to print has been correct and unread since it was written.
# The marker rides in the run's property bag (SARIF 2.1.0 §3.8, the documented
# extension point), where mykronos/adapters/sarif.py reads it and maps it to
# ScanStatus.NO_APPLICABLE_TARGETS — a status the platform already had, already
# treats as a reporting outcome and already excludes from alerting.
#
# checkov's own SARIF is PATCHED rather than replaced, so the tool metadata,
# its version and anything else it recorded survive into the lake.
if [ "${resources}" -eq 0 ] && [ "${n}" -eq 0 ]; then
  python3 - "${sarif}" <<'PY'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
doc = json.loads(path.read_text())
runs = doc.get("runs") or []
if not runs:
    # An empty SARIF cannot carry a per-run marker, so give it a run to carry
    # one. Without this the document falls through to "scanned, found nothing".
    runs = [{"tool": {"driver": {"name": "checkov"}}, "results": []}]
    doc["runs"] = runs
for run in runs:
    run.setdefault("properties", {})["mykronos"] = {
        "scanStatus": "no_applicable_targets",
        "reason": (
            "checkov performed 0 checks across every framework it supports, so "
            "there is nothing in this repository for it to scan. The control is "
            "not applicable, not satisfied."
        ),
    }
path.write_text(json.dumps(doc, indent=2))
PY

  cat <<'EOF'

================================================================================
IaC scan: checkov performed 0 checks

Nothing to scan. THIS IS NOT A PASS for CM-6/CM-7 — it means the control is not
applicable yet. It becomes applicable the moment this repository gains anything
checkov understands, which is a longer list than Terraform and Dockerfiles: it
includes GitHub Actions workflows, GitLab CI, Azure Pipelines, Ansible,
Serverless and OpenAPI.

Recorded as `no_applicable_targets` in the SARIF, not only here.
================================================================================

EOF
  exit 0
fi

# The actual gate: fail on findings, not on tooling noise.
if [ "${n}" -ne 0 ]; then
  echo "ERROR: ${n} IaC misconfiguration(s) — see ${sarif}" >&2
  exit 1
fi
