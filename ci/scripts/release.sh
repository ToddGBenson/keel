#!/usr/bin/env bash
# Release — G5. Refs: #42, #50
set -euo pipefail

: "${STAGE:?STAGE is required (preflight|staging|production)}"

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
    echo "── G5 preflight — evidence check ────────────────────────────────────"
    echo "ADAPT: assert the change record at '${CHANGE_RECORD:-<unset>}' exists and"
    echo "contains all 13 required sections (docs/07-release-and-change.md)."
    echo
    echo "ADAPT: for each issue in scope, assert evidence/<issue>/g4/ contains"
    echo "independent QA, security, and (if AI-relevant) AI pass records."
    echo
    echo "Anything without G4 clearance is REMOVED from the release, not waived."
    echo "Scope shrinks; gates do not. This is the item most often pressured, and"
    echo "holding it is what makes every upstream gate mean something."
    echo
    echo "ADAPT: query the finding register and POA&M. Open Critical or High in"
    echo "scope is a hard block."
    echo
    # This one is NOT hypothetical today.
    cat <<'EOF'
⚠️  POAM-014 IS OPEN AND CRITICAL: this repository currently has no merge gate.
Nothing verified any change in this release before it reached main — not lint,
not tests, not SAST, not the governance checks. A release assembled under that
condition carries a materially weaker assurance chain, and the change record must
say so rather than cite gates that did not run.
EOF
    echo
    echo "ADAPT: assert a rollback rehearsal record exists for this artifact."
    echo "An untested rollback plan is a hypothesis; this gate asks for a fact."
    install_cosign
    echo "ADAPT: cosign verify + verify-attestation — HARD BLOCK."
    ;;

  staging)
    echo "── Deploy to staging ────────────────────────────────────────────────"
    echo "ADAPT: deploy the SAME artifact by DIGEST, never by tag. Never rebuild —"
    echo "the artifact tested here must be byte-identical to the one that reaches"
    echo "production."
    echo
    echo "ADAPT: DAST against ${STAGING_URL:-<unset>} (SA-11(8))"
    echo "ADAPT: E2E — critical journeys; assert the stated NFR thresholds"
    echo "ADAPT: configuration drift check vs. the baseline (CM-2, CM-6)"
    echo
    echo "ADAPT: rollback rehearsal (CP-10) — actually roll back, verify, then roll"
    echo "forward. Include the data path. Record the window; the approver needs it."
    ;;

  production)
    # ══════════════════════════════════════════════════════════════════════════
    # ⚠️  THIS IS THE WEAK FORM OF THE GATE  ⚠️
    #
    # The strong form was a GitHub `production` environment with required
    # reviewers — the job could not start until a named human approved, and that
    # record was the CM-3 evidence. Making the repository private removed that
    # rule outright, and Actions cannot run at all, so the strong form is not
    # available at any price short of changing those facts.
    #
    # This is what remains: a job with no trigger. Triggering and approving are
    # one action; nothing requires the approver to differ from the author; anyone
    # with pipeline access can press it. POAM-006 and POAM-010 stay open.
    # ══════════════════════════════════════════════════════════════════════════
    cat <<EOF

── G5 authorization ───────────────────────────────────────────────────────────
  Version        ${VERSION:-<unset>}
  Change record  ${CHANGE_RECORD:-<unset>}
  Triggered by   ${BUILD_CREATED_BY:-UNKNOWN — see below}
  Build          ${CONCOURSE_URL:-}/teams/${BUILD_TEAM_NAME:-}/pipelines/${BUILD_PIPELINE_NAME:-}/jobs/${BUILD_JOB_NAME:-}/builds/${BUILD_NAME:-}
  Commit         $(git -C repo rev-parse HEAD)

EOF

    # BUILD_CREATED_BY is populated only when a user triggered the build. Empty
    # means something started this WITHOUT a person — and for a production release
    # that is not a degraded record, it is no authorization at all.
    if [ -z "${BUILD_CREATED_BY:-}" ]; then
      cat >&2 <<'EOF'
ERROR: no triggering user recorded for a production release.

The only authorization control on this job is that a human starts it, so a build
with no recorded human has no authorization. Refusing to deploy. If a trigger was
added to this job, remove it.
EOF
      exit 1
    fi

    install_cosign
    echo "ADAPT: re-verify signature and provenance immediately before deploy."
    echo "Time passed since preflight; verify what you are about to run."
    echo
    echo "ADAPT: progressive deploy — canary to a small traffic slice, watch error"
    echo "rate, latency and saturation against thresholds for a defined bake time,"
    echo "then expand. Automated rollback on breach — the human decision arrives"
    echo "ten minutes late every time."
    echo
    echo "ADAPT: post-deploy verification against ${PRODUCTION_URL:-<unset>}"
    echo "ADAPT: write evidence/releases/${VERSION:-<version>}/deployment-record.md"
    echo "Then schedule the 24-hour check: did the success metric from the ORIGINAL"
    echo "idea record actually move? That closes the loop nearly everyone skips."
    ;;

  *)
    echo "ERROR: unknown STAGE '${STAGE}'." >&2
    exit 1
    ;;
esac
