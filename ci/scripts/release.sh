#!/usr/bin/env bash
# Release — G5. Refs: #42, #50
set -euo pipefail

: "${STAGE:?STAGE is required (preflight|release)}"

install_cosign() {
  : "${COSIGN_VERSION:?COSIGN_VERSION is required}"
  : "${COSIGN_SHA256:?COSIGN_SHA256 is required}"
  curl -sSfL -o /usr/local/bin/cosign \
    "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-amd64"
  echo "${COSIGN_SHA256}  /usr/local/bin/cosign" | sha256sum -c -
  chmod +x /usr/local/bin/cosign
}

case "${STAGE}" in

  preflight)
    echo "── G5 preflight — is this template fit to release? ───────────────────"
    # A template's preflight is not "does the artifact verify". It is "will a
    # fork receive what we think we are sending".
    echo "── the delivery contract ─────────────────────────────────────────────"
    python -m pip install --quiet --disable-pip-version-check pyyaml
    python scripts/validate-manifest.py

    echo "── the platform's own integrity ──────────────────────────────────────"
    python scripts/validate-platform.py

    echo "── the pipeline forks inherit ────────────────────────────────────────"
    python scripts/validate-pipeline.py

    echo
    echo "ADAPT: assert the change record exists and carries all 13 required"
    echo "sections (docs/07-release-and-change.md), and that every issue in scope"
    echo "cleared G4. Anything without G4 clearance is REMOVED from the release,"
    echo "not waived — scope shrinks, gates do not."
    echo
    cat <<'EOF'
⚠️  POAM-014 IS OPEN AND CRITICAL: this repository has no merge gate. Nothing
verified any change in this release before it reached main. A release assembled
under that condition carries a materially weaker assurance chain, and the change
record must say so rather than cite gates that did not run.
EOF
    ;;

  release)
    # ══════════════════════════════════════════════════════════════════════════
    # ⚠️  A TEMPLATE RELEASE HAS A WIDER BLAST RADIUS THAN A DEPLOY  ⚠️
    #
    # This does not ship a service. It marks a version that every fork will
    # fast-forward into its platform-owned paths — overwriting local edits there
    # by design. A bad service deploy affects one environment and rolls back in
    # minutes. A bad platform release reaches every fork, on their schedule, and
    # each one discovers it alone.
    #
    # The authorisation control is exactly as weak as the one described in
    # POAM-010: triggering and approving are one action, nothing requires the
    # approver to differ from the author, and anyone with pipeline access can
    # press it. Do not describe it as more.
    # ══════════════════════════════════════════════════════════════════════════
    cat <<EOF

── G5 authorisation — platform release ────────────────────────────────────────
  Version        ${VERSION:-<unset>}
  Change record  ${CHANGE_RECORD:-<unset>}
  Authorised by  ${BUILD_CREATED_BY:-UNKNOWN — see below}
  Build          ${CONCOURSE_URL:-}/teams/${BUILD_TEAM_NAME:-}/pipelines/${BUILD_PIPELINE_NAME:-}/jobs/${BUILD_JOB_NAME:-}/builds/${BUILD_NAME:-}
  Commit         $(git -C repo rev-parse HEAD)

EOF

    if [ -z "${BUILD_CREATED_BY:-}" ]; then
      cat >&2 <<'EOF'
ERROR: no triggering user recorded for a platform release.

The only authorisation control on this job is that a human starts it, so a build
with no recorded human has no authorisation at all. Refusing. If a trigger was
added to this job, remove it.
EOF
      exit 1
    fi

    echo "ADAPT: tag the release, and write the fork-facing note that says what"
    echo "changed in PLATFORM-OWNED paths — those are the ones a sync overwrites"
    echo "without asking. merge_required changes need a sentence each, because a"
    echo "human on the other end has to reconcile them by hand."
    echo
    echo "ADAPT: write evidence/releases/${VERSION:-<version>}/release-record.md"
    echo "Then check back: did any fork actually sync it? A platform release with"
    echo "no adopters is not a release, it is a tag."
    ;;

  *)
    echo "ERROR: unknown STAGE '${STAGE}'." >&2
    exit 1
    ;;
esac
