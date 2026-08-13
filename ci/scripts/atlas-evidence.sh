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
SBOM_REF=""
if [ -f sbom/sbom.json ]; then
  SBOM_REF="$(curl --fail --silent --show-error --max-time 60 \
    -X POST "${MYKRONOS_INGESTION_URL}/api/ingest/raw?scan_run_id=${BUILD_ID}&filename=sbom.json" \
    -H "Authorization: Bearer ${MYKRONOS_INGESTION_TOKEN}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @sbom/sbom.json \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("raw_output_ref",""))')"
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

python3 - <<'PY' > evidence.env
import json

doc = json.load(open("evidence.json"))


def shell(value):
    # JSON booleans and nulls do not survive a naive str(); the comparisons
    # below are string comparisons and have to be given strings they expect.
    if value is True:
        return "true"
    if value is False:
        return "false"
    if value is None:
        return ""
    return str(value)


for key in (
    "trust_score",
    "min_trust_score",
    "below_minimum",
    "blocking",
    "dependency_count",
    "vulnerable_dependency_count",
):
    print(f"{key.upper()}={shell(doc.get(key))}")
PY

# shellcheck disable=SC1091
. ./evidence.env

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
