#!/usr/bin/env bash
# Dependency scanning for the Atlas capability. Refs: #42
#
# Carried over from .github/workflows/mykronos-atlas.yml with its reasoning
# intact. Every comment below records a defect that actually shipped.
set -euo pipefail

: "${OSV_VERSION:?OSV_VERSION is required}"
: "${OSV_SHA256:?OSV_SHA256 is required}"

# NOT `pip install osv-scanner` — that name on PyPI is a reserved placeholder
# ("Reserved name placeholder. No functionality.", 0.0.1) which installs cleanly
# and provides no CLI. Every Atlas run since that lane shipped died on
# `osv-scanner: command not found`, was swallowed by a blanket `|| true`, and
# reported zero findings.
#
# OSV-Scanner is a Go binary released on GitHub; pin the version and verify the
# published checksum so a swapped artifact cannot land in the one lane whose job
# is catching swapped artifacts.
curl -sSfL -o /usr/local/bin/osv-scanner \
  "https://github.com/google/osv-scanner/releases/download/v${OSV_VERSION}/osv-scanner_linux_amd64"
echo "${OSV_SHA256}  /usr/local/bin/osv-scanner" | sha256sum -c -
chmod +x /usr/local/bin/osv-scanner
osv-scanner --version

# `--recursive` is required, not a tuning knob: `scan source` looks only at the
# directory it is given, and real repos keep their manifests in subdirectories
# (backend/, frontend/). Without it the scan walked the repo root, matched
# nothing, and exited 128 "no packages found" — a clean-looking empty result.
# `.gitignore` is honoured during the walk, so node_modules and friends stay out.
#
# `--no-resolve` disables transitive resolution of manifests, which calls
# deps.dev. That call returns `rpc error: code = Internal` for any
# requirements.txt containing sqlalchemy — reproduced down to a one-line file at
# every version tested — and an extractor error is exit 127, which fails the
# whole lane. It stayed invisible while the scan also found vulnerabilities,
# because exit 1 outranks it; the first repo to fix its last CVE turned a green
# lane red. Direct manifest and lockfile scanning is unaffected and still finds
# everything the advisories cover.
#
# Exit 1 means vulnerabilities were found, which is a result and not an error, so
# that one code is tolerated. Everything else fails: 127 is a general error, 128
# means nothing was scanned, and a capability that scanned nothing must not
# report a clean supply chain. A blanket `|| true` here is what hid both of the
# bugs above for the entire life of this lane.
run_osv() {
  local rc=0
  ( cd repo && osv-scanner scan source --recursive --no-resolve "$@" . ) || rc=$?
  if [ "$rc" -gt 1 ]; then
    echo "ERROR: osv-scanner exited ${rc} — that is a scan failure, not a findings result" >&2
    exit "$rc"
  fi
}

run_osv --format sarif --output-file "${PWD}/mykronos-results/osv.sarif"
run_osv --format json  --output-file "${PWD}/osv-json/osv.json"

# The atlas counts step downstream reads this file unconditionally. An absent one
# there would be an unhelpful crash; an empty result set is a legitimate answer.
test -s osv-json/osv.json || echo '{"results":[]}' > osv-json/osv.json

echo "OSV scan complete."
