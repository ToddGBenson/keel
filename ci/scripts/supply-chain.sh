#!/usr/bin/env bash
# Build once, inventory it, sign it, verify it. Refs: #42, #144
#
# The artifact tested in staging is byte-identical to the one that reaches
# production. Never rebuild per environment — a rebuild invalidates every test
# that came before it, and it is how "it worked in staging" becomes an incident.
# Configuration is injected at deploy time; the artifact is immutable and
# referenced by digest, never by a mutable tag.
#
# keel ships no image (ADR-0004). Its artifact is the platform release that
# forks sync: a checksum manifest of every platform-owned file, signed by
# .github/workflows/release.yml at the tag (scripts/platform-release.sh). A fork
# that builds an image adapts build-and-attest to build and sign it, and verify
# to check that image by digest.
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

    # ── SR-4 / SR-4(3): what is signed, and where ───────────────────────────
    #
    # Signing does NOT happen in Concourse, deliberately. Keyless signing needs
    # an OIDC identity the public Sigstore CA trusts, and a self-hosted
    # Concourse has none; a key file in a pipeline var is the long-lived secret
    # keyless signing exists to avoid (IA-5). The release is signed and its
    # provenance attested by .github/workflows/release.yml (sign-and-attest),
    # with GitHub's OIDC identity, after the G5 approval. (#144, POAM-011)
    #
    # What this job produces is the exact manifest release.yml signs, for this
    # commit, so the subject can be inspected before any tag exists.
    ( cd repo && bash scripts/platform-release.sh manifest ../artifact/platform-manifest.txt )
    echo "platform manifest: $(wc -l < artifact/platform-manifest.txt | tr -d ' ') platform-owned files (signed at release, not here)"
    ;;

  verify)
    # This stage exists because a signature nobody verifies is decoration.
    #
    # It verifies the LATEST RELEASE. Commits on main are not releases and are
    # never signed. Once a release exists it FAILS when the release carries no
    # signature, when the signature is not release.yml's on that tag, and when
    # the tag is on a commit that is not on main (repo/ is Concourse's checkout
    # of main, with tags). (#144, POAM-011; review of #145, finding 1)
    #
    # NO RELEASE YET is ADVISORY (exit 0), and says nothing was verified. The
    # one exception to "nothing to check is a failure" (2026-10-22), made by
    # the HubOps review of #145 (finding 2): keel had no release when this
    # shipped, and cutting one needs operator steps (configure-github.sh lets
    # `production` accept v* tags). A lane red on every main commit until then
    # turns `Concourse / keel` red for a reason no commit can fix, and a check
    # that is always red is read as noise. It stops applying by itself: the
    # first published release makes every later failure red.
    #
    # The API answering 403/429 is NOT "no release": unauthenticated calls
    # share 60/h per address, and a rate limit used to be reported as "no
    # published release" (finding 4). It fails as "could not check". Set
    # GITHUB_API_TOKEN (read-only, optional) to authenticate the call.
    : "${REPO_SLUG:?REPO_SLUG is required (owner/repo): it is the signer identity}"

    rel="$(mktemp -d)"
    hdr="${rel}/api-headers"
    ( umask 077; printf 'Accept: application/vnd.github+json\n' > "$hdr" )
    if [ -n "${GITHUB_API_TOKEN:-}" ]; then
      # A header file, not -H on the command line: argv is readable by every
      # process in the container.
      ( umask 077; printf 'Authorization: Bearer %s\n' "$GITHUB_API_TOKEN" >> "$hdr" )
    fi
    code="$(curl -sSL -H "@${hdr}" -o "${rel}/latest.json" -w '%{http_code}' \
              "https://api.github.com/repos/${REPO_SLUG}/releases/latest")" || code="000"
    rm -f "$hdr"
    case "$code" in
      200) ;;
      404)
        echo "ADVISORY: ${REPO_SLUG} has no release yet (HTTP 404), so nothing was verified."
        echo "ADVISORY: this passes only until the first release: once one is published, an"
        echo "ADVISORY: unsigned or unverifiable latest release fails this job. Cut one through"
        echo "ADVISORY: .github/workflows/release.yml (operator steps: docs/compliance/poam.md, POAM-011)."
        exit 0
        ;;
      403|429)
        echo "ERROR: the GitHub API refused the releases call (HTTP ${code}): most likely the" >&2
        echo "unauthenticated rate limit (60 an hour per address, shared with everything on this" >&2
        echo "host). Could not check, so this is not a pass, and not 'no release' either." >&2
        echo "Re-run later, or set GITHUB_API_TOKEN for an authenticated limit." >&2
        exit 1
        ;;
      *)
        echo "ERROR: the GitHub releases API answered HTTP ${code} for ${REPO_SLUG}. Could not check." >&2
        exit 1
        ;;
    esac
    install_cosign
    # Three lines: the tag, then each asset's URL (empty when it is missing).
    mapfile -t meta < <(python - "${rel}/latest.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assets = {a.get("name"): a.get("browser_download_url") or "" for a in d.get("assets") or []}
sys.stdout.buffer.write("\n".join([
    d.get("tag_name") or "",
    assets.get("platform-manifest.txt", ""),
    assets.get("platform-manifest.sigstore.json", ""),
]).encode("utf-8") + b"\n")
PY
)
    tag="${meta[0]:-}"; manifest_url="${meta[1]:-}"; bundle_url="${meta[2]:-}"
    if [ -z "$tag" ]; then
      echo "ERROR: the latest release of ${REPO_SLUG} has no tag." >&2
      exit 1
    fi
    echo "latest release: ${tag}"
    if [ -z "$manifest_url" ] || [ -z "$bundle_url" ]; then
      echo "ERROR: release ${tag} is UNSIGNED: it does not carry platform-manifest.txt" >&2
      echo "and platform-manifest.sigstore.json. An unverifiable release is refused." >&2
      exit 1
    fi
    curl -sSfL -o "${rel}/platform-manifest.txt" "$manifest_url"
    curl -sSfL -o "${rel}/platform-manifest.sigstore.json" "$bundle_url"

    bash repo/scripts/platform-release.sh verify \
      --manifest "${rel}/platform-manifest.txt" \
      --bundle "${rel}/platform-manifest.sigstore.json" \
      --repo "${REPO_SLUG}" --tag "${tag}" \
      --git repo --trusted-ref HEAD
    echo "verified: ${REPO_SLUG}@${tag} was signed by its own release workflow on that tag, at a commit on main."
    ;;

  *)
    echo "ERROR: unknown STAGE '${STAGE}'." >&2
    exit 1
    ;;
esac
