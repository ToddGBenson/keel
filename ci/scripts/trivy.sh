#!/usr/bin/env bash
# Container image scanning. Refs: #42, TheHub #60935
#
# ADAPT: inert until you ship containers. The job has no trigger, so it runs only
# when someone starts it. Left visible rather than deleted -- a job that is
# plainly not running beats one that silently does not exist.
#
# NO IMAGE IS A FAILURE (operator decision, TheHub #60935, 2026-10-22), the rule
# `iac` follows since 2026-09-23. This used to exit 0 with a NOT-A-PASS banner,
# which made the lane's first ever build (2026-10-11) a green run that scanned
# nothing. Started by hand with no IMAGE_REF, it is now red, and stays red until
# this repository ships an image and IMAGE_REF is set. That is the intended
# reading: "not in service" is not a pass.
set -euo pipefail

if [ -z "${IMAGE_REF:-}" ]; then
  cat >&2 <<'EOF'

================================================================================
Container scan: IMAGE_REF is not set -- FAILING

Nothing was scanned, so RA-5/SR-11 has no evidence from this run. A no-subject
scan is a failure, not a pass (TheHub #60935). This lane is not in service
until this repository ships a container image.

To enable: build and push the image, set IMAGE_REF on the container-scan job,
pin TRIVY_VERSION and TRIVY_SHA256 in ci/vars.yml, and give the job a trigger.
================================================================================

EOF
  exit 1
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
