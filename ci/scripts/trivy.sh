#!/usr/bin/env bash
# Container image scanning. Refs: #42
#
# ADAPT: inert until you ship containers. The Actions version carried `if: false`;
# here the job simply has no trigger. Left visible rather than deleted — a job
# that is plainly not running beats one that silently does not exist.
set -euo pipefail

if [ -z "${IMAGE_REF:-}" ]; then
  cat <<'EOF'

================================================================================
Container scan: IMAGE_REF is not set.

This lane is not yet in service. THIS IS NOT A PASS for RA-5/SR-11 — it means
the control is not applicable until this repository ships a container image.

To enable: build and push the image, set IMAGE_REF on the container-scan job,
pin TRIVY_VERSION and TRIVY_SHA256 in ci/vars.yml, and give the job a trigger.
================================================================================

EOF
  exit 0
fi

: "${TRIVY_VERSION:?TRIVY_VERSION is required}"
: "${TRIVY_SHA256:?TRIVY_SHA256 is required}"

tarball="trivy.tar.gz"
curl -sSfL -o "${tarball}" \
  "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
echo "${TRIVY_SHA256}  ${tarball}" | sha256sum -c -
tar -xzf "${tarball}" trivy
install -m 0755 trivy /usr/local/bin/trivy
trivy --version

# --ignore-unfixed is deliberate: gate on what you can actually act on.
trivy image "${IMAGE_REF}" \
  --format sarif \
  --output container-results/trivy.sarif \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  --exit-code 1
