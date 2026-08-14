#!/usr/bin/env bash
# Build once, inventory it, sign it, verify it. Refs: #42
#
# The artifact tested in staging is byte-identical to the one that reaches
# production. Never rebuild per environment — a rebuild invalidates every test
# that came before it, and it is how "it worked in staging" becomes an incident.
# Configuration is injected at deploy time; the artifact is immutable and
# referenced by digest, never by a mutable tag.
set -euo pipefail

: "${STAGE:?STAGE is required (build-and-attest|verify)}"

install_cosign() {
  : "${COSIGN_VERSION:?COSIGN_VERSION is required — pin it in ci/vars.yml}"
  : "${COSIGN_SHA256:?COSIGN_SHA256 is required — see ci/README.md}"
  curl -sSfL -o /usr/local/bin/cosign \
    "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-amd64"
  echo "${COSIGN_SHA256}  /usr/local/bin/cosign" | sha256sum -c -
  chmod +x /usr/local/bin/cosign
  cosign version
}

case "${STAGE}" in

  build-and-attest)
    echo "ADAPT: build once, reproducibly where the toolchain allows."
    echo "Emit the artifact digest — deploys reference the DIGEST, never a tag."
    echo "  echo sha256:... > artifact/digest"

    # The SBOM arrives as an input from the syft task rather than being
    # regenerated here, so the inventory describes the same tree that was built.
    # HARD FAILURE, not a warning. CM-8 is a component inventory for the thing
    # being built; an artifact lane that ships without one has not satisfied it,
    # and the previous `WARNING:` here ran on every single build for weeks while
    # the job stayed green.
    #
    # Enforced here rather than by making the task input required, because
    # verify-artifact shares this task file and legitimately has no SBOM.
    if [ ! -f sbom/sbom.json ]; then
      echo "ERROR: no SBOM. CM-8 is not satisfied and this is not a pass." >&2
      echo "The build-and-attest job must run the sbom + sbom-check tasks before" >&2
      echo "this one. If syft found no components it deletes the file on purpose —" >&2
      echo "see ci/scripts/sbom-check.sh — which means this repository has no" >&2
      echo "resolved dependency set and there is nothing to inventory." >&2
      exit 1
    fi
    cp sbom/sbom.json artifact/sbom.cdx.json
    echo "SBOM carried forward (CM-8)." 

    echo
    echo "ADAPT: fetch the previous release SBOM and diff component sets."
    echo "An unexpected component delta is a supply-chain signal — investigate"
    echo "before shipping. This diff is presented at G5 (change record item 10)."
    echo

    install_cosign

    # ── SR-4 / SR-4(3): provenance ────────────────────────────────────────────
    #
    # THIS IS WHERE THE PORT LOST SOMETHING. On Actions this step was
    # actions/attest-build-provenance and actions/attest-sbom, which write to
    # GitHub's attestation store and are checkable with `gh attestation verify`.
    # That store is only writable from Actions. There is no Concourse equivalent
    # and no way to fake one.
    #
    # cosign attestations below cover the same ground and are the stronger,
    # portable half — but anything that was verifying via `gh attestation verify`
    # must be repointed at cosign. Recorded as POAM-011.
    echo "ADAPT: cosign attest --predicate <provenance.json> --type slsaprovenance \\"
    echo "         \${REGISTRY}/<image>@\$(cat artifact/digest)"
    echo "ADAPT: cosign attest --predicate artifact/sbom.cdx.json --type cyclonedx \\"
    echo "         \${REGISTRY}/<image>@\$(cat artifact/digest)"
    echo
    echo "ADAPT: cosign sign --yes \${REGISTRY}/<image>@\$(cat artifact/digest)"
    echo "Keyless via OIDC where your Concourse supports it — no long-lived"
    echo "signing keys to manage or leak (IA-5). If it does not, a KMS key is the"
    echo "next best thing; a key file in a pipeline var is not."
    ;;

  verify)
    install_cosign

    # This stage exists because a signature nobody verifies is decoration. The
    # same verification MUST also run in the deploy path and MUST refuse on
    # mismatch — verifying only here proves the signature was made, not that it
    # is checked before use.
    echo "ADAPT: cosign verify \\"
    echo "  --certificate-identity-regexp '<your concourse OIDC identity>' \\"
    echo "  --certificate-oidc-issuer '<your issuer>' \\"
    echo "  \${REGISTRY}/<image>@<digest>"
    echo
    echo "ADAPT: cosign verify-attestation --type slsaprovenance ..."
    echo
    echo "Failure here is a hard block. An unverifiable artifact does not deploy."
    ;;

  *)
    echo "ERROR: unknown STAGE '${STAGE}'." >&2
    exit 1
    ;;
esac
