#!/usr/bin/env bash
# Release — G5. Refs: #42
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
    echo "ADAPT: assert the change record at '${CHANGE_RECORD:-<unset>}' exists"
    echo "and contains all 13 required sections (docs/07-release-and-change.md)."
    echo
    echo "ADAPT: for each issue in scope, assert evidence/<issue>/g4/ contains"
    echo "independent QA, security, and (if AI-relevant) AI pass records."
    echo
    echo "Anything without G4 clearance is REMOVED from the release, not waived."
    echo "Scope shrinks; gates do not. This is the item most often pressured, and"
    echo "holding it is what makes every upstream gate mean something."
    echo
    echo "ADAPT: query the finding register and POA&M. Open Critical or High in"
    echo "scope is a hard block, overridable only by a documented, time-boxed,"
    echo "human-approved risk acceptance with a POA&M entry."
    echo
    echo "ADAPT: assert a rollback rehearsal record exists for this artifact."
    echo "An untested rollback plan is a hypothesis; this gate asks for a fact."
    echo

    install_cosign
    echo "ADAPT: cosign verify + verify-attestation — HARD BLOCK."
    echo "Failure here stops the release. A signature nobody verifies is"
    echo "decoration, and this is the place the verification has to happen"
    echo "(SR-4(3), SI-7)."
    ;;

  staging)
    echo "── Deploy to staging ────────────────────────────────────────────────"
    echo "ADAPT: deploy the SAME artifact by DIGEST, not by tag. Never rebuild —"
    echo "the artifact tested here must be byte-identical to the one that reaches"
    echo "production."
    echo
    echo "ADAPT: DAST against ${STAGING_URL:-<unset>} (SA-11(8))"
    echo "ADAPT: E2E — critical journeys; assert the stated NFR thresholds"
    echo "ADAPT: configuration drift check vs. the baseline (CM-2, CM-6)"
    echo
    echo "ADAPT: rollback rehearsal (CP-10) — actually roll back, verify, then"
    echo "roll forward. Include the data path. Record the window; that number"
    echo "goes in the change record and the approver needs it."
    ;;

  production)
    # ══════════════════════════════════════════════════════════════════════════
    # ⚠️  THIS IS NOT THE GATE IT REPLACED  ⚠️
    #
    # On GitHub Actions the production job sat behind an `environment:` with
    # required reviewers. It physically could not start until a named human
    # approved in the GitHub UI, and that approval record — identity, timestamp,
    # tied to the specific run — WAS the CM-3 change approval evidence.
    #
    # This job runs because a human pressed a button in Concourse. That is a
    # weaker control in three specific ways:
    #
    #   1. There is no approval WORKFLOW. Triggering and approving are the same
    #      action, so there is no record of a decision distinct from an act.
    #   2. There is no second-identity requirement. The person who wrote the
    #      change can release it, which is exactly what AC-5 exists to prevent.
    #   3. Anyone with pipeline access can trigger it. Concourse authorises per
    #      team, not per job.
    #
    # Tracked as POAM-010. Do not let anyone describe this as equivalent.
    # ══════════════════════════════════════════════════════════════════════════
    cat <<EOF

── G5 authorization ───────────────────────────────────────────────────────────
  Version        ${VERSION:-<unset>}
  Change record  ${CHANGE_RECORD:-<unset>}
  Triggered by   ${BUILD_CREATED_BY:-UNKNOWN — see the warning below}
  Build          ${CONCOURSE_URL:-}/teams/${BUILD_TEAM_NAME:-}/pipelines/${BUILD_PIPELINE_NAME:-}/jobs/${BUILD_JOB_NAME:-}/builds/${BUILD_NAME:-}
  Commit         $(git -C repo rev-parse HEAD)

EOF

    # BUILD_CREATED_BY is populated only when a user triggered the build. If it
    # is empty here, something started this job WITHOUT a human — which for a
    # production release is not a degraded record, it is a control failure.
    # Refuse rather than deploy with an anonymous authorization.
    if [ -z "${BUILD_CREATED_BY:-}" ]; then
      cat >&2 <<'EOF'
ERROR: no triggering user recorded for a production release.

BUILD_CREATED_BY is empty, which means this build was not started by a person.
The only authorization control on this job is that a human starts it, so a build
with no recorded human has no authorization at all.

Refusing to deploy. If a trigger was added to this job, remove it.
EOF
      exit 1
    fi

    install_cosign
    echo "ADAPT: re-verify signature and provenance immediately before deploy."
    echo "Time passed between preflight and authorization; verify what you are"
    echo "about to run, not what you checked an hour ago."
    echo
    echo "ADAPT: progressive deploy — canary to a small traffic slice."
    echo "Watch error rate, latency, saturation against defined thresholds for a"
    echo "defined bake time, then expand."
    echo
    echo "Automated rollback on threshold breach — no human decision in the loop,"
    echo "because the human decision arrives ten minutes late every time."
    echo
    echo "ADAPT: post-deploy verification — smoke tests, health checks, error"
    echo "rate vs. the pre-deploy baseline. Target: ${PRODUCTION_URL:-<unset>}"
    echo
    echo "ADAPT: write evidence/releases/${VERSION:-<version>}/deployment-record.md"
    echo "Then schedule the 24-hour check: did the success metric from the"
    echo "ORIGINAL idea record actually move? That step closes the loop nearly"
    echo "everyone skips, and it is why backlogs fill with features nobody uses."
    ;;

  *)
    echo "ERROR: unknown STAGE '${STAGE}'." >&2
    exit 1
    ;;
esac
