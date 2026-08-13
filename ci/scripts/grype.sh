#!/usr/bin/env bash
# SCA — dependency vulnerabilities. Refs: #42
set -euo pipefail

SEVERITY_CUTOFF="${SEVERITY_CUTOFF:-high}"

# The pin is checked after the manifest-presence test below, not before it. A
# repository with nothing to scan must not go red over a tool version it was
# never going to use.

# Same "nothing to scan" case as the IaC lane. A repo with no dependency manifest
# is legitimate; the scan must say so rather than fail on plumbing or, worse,
# report green as though it had checked something. (L0008 — this defect existed
# in BOTH jobs; fixing one was not fixing the class.)
if ! find repo -path repo/.git -prune -o \
     \( -name 'package.json' -o -name 'package-lock.json' -o -name 'yarn.lock' \
        -o -name 'requirements*.txt' -o -name 'pyproject.toml' -o -name 'Pipfile.lock' \
        -o -name 'go.mod' -o -name 'Cargo.toml' -o -name 'Gemfile.lock' \
        -o -name 'pom.xml' -o -name 'build.gradle*' -o -name 'composer.json' \) \
     -print 2>/dev/null | grep -q .; then
  cat <<'EOF'

================================================================================
SCA: no dependency manifests found

Nothing to scan. THIS IS NOT A PASS for RA-5/SR-3 — the control is not yet
applicable. It applies the moment you add a manifest.
================================================================================

EOF
  exit 0
fi

# Manifests are present, so the pin is genuinely required now.
: "${GRYPE_VERSION:?GRYPE_VERSION is required — there ARE dependency manifests to scan}"
: "${GRYPE_SHA256:?GRYPE_SHA256 is required — see ci/README.md for how to get it}"

tarball="grype.tar.gz"
curl -sSfL -o "${tarball}" \
  "https://github.com/anchore/grype/releases/download/v${GRYPE_VERSION}/grype_${GRYPE_VERSION}_linux_amd64.tar.gz"
echo "${GRYPE_SHA256}  ${tarball}" | sha256sum -c -
tar -xzf "${tarball}" grype
install -m 0755 grype /usr/local/bin/grype
grype version

# Gate on NEW findings, not TOTAL — see the note in ci/pipeline.yml. `--fail-on`
# is the absolute-count gate and is deliberately paired with a severity cutoff
# high enough that the existing backlog is driven down through the POA&M on SLA
# rather than by turning this job off.
rc=0
grype "dir:repo" \
  --output sarif \
  --file sca-results/grype.sarif \
  --fail-on "${SEVERITY_CUTOFF}" || rc=$?

python3 - <<'PY'
import json, pathlib
p = pathlib.Path("sca-results/grype.sarif")
if not p.exists():
    print("No SARIF produced.")
else:
    doc = json.loads(p.read_text())
    n = sum(len(run.get("results", [])) for run in doc.get("runs", []))
    print(f"grype findings: {n}")
PY

if [ "${rc}" -ne 0 ]; then
  echo "ERROR: grype found vulnerabilities at or above '${SEVERITY_CUTOFF}'." >&2
  echo "The SARIF is in the build artifacts. Disposition each result at G4 —" >&2
  echo "true positive / false positive (rationale AND expiry) / accepted risk." >&2
  exit "${rc}"
fi
