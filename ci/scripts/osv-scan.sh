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
# ── EXIT 128 IS OVERLOADED ────────────────────────────────────────────────────
# 128 with "No package sources found" means the repository declares no
# dependencies — a docs repo, a shell-script repo, a project before its first
# manifest. That is a legitimate state, not an error and not a finding, and keel
# is exactly such a repository.
#
# Treating it as a failure costs both directions: the lane goes permanently red
# for repos that will never have a manifest, so operators learn to ignore it —
# and a genuinely broken scanner then looks exactly like an empty repository.
#
# Ported from the upstream Mykronos template 2.1.0 (mykronos PR #45), which fixed
# this in the Actions workflow. This script was a port of 2.0.0 and carried the
# old behaviour, so the Concourse lane failed on keel while the workflow it
# replaced would have passed.
#
# Match on the MESSAGE, not the code alone: a different 128 is still a real
# failure.
NO_PACKAGES=0

run_osv() {
  local rc=0 out
  out="$(cd repo && osv-scanner scan source --recursive --no-resolve "$@" . 2>&1)" || rc=$?
  printf '%s
' "$out"

  if [ "$rc" -eq 128 ] && printf '%s' "$out" | grep -qi 'no package sources found'; then
    NO_PACKAGES=1
    return 0
  fi

  # Exit 1 means vulnerabilities were found, which is a result and not an error.
  # Everything else fails: a capability that scanned nothing must not report a
  # clean supply chain.
  if [ "$rc" -gt 1 ]; then
    echo "ERROR: osv-scanner exited ${rc} — that is a scan failure, not a findings result" >&2
    exit "$rc"
  fi
}

run_osv --format sarif --output-file "${PWD}/mykronos-results/osv.sarif"
run_osv --format json  --output-file "${PWD}/osv-json/osv.json"

if [ "$NO_PACKAGES" -eq 1 ]; then
  # Loudly. A silent empty result is the failure mode this change could otherwise
  # introduce, and a false green is worse than the false red it replaces —
  # nobody investigates a green lane.
  cat <<'EOF'

================================================================================
No package sources found.

This repository declares no dependencies for osv-scanner to read, so there is
nothing to scan. Recording an EMPTY RESULT.

This is NOT a clean bill of health for dependencies that exist. It is a statement
that none were declared. It becomes a real scan the moment a manifest appears.
================================================================================

EOF

  # A valid, explicitly-empty SARIF, so downstream reads "scanned, found nothing"
  # rather than "produced no output" — the latter is what the upload step reports
  # as a scan failure, which is precisely how this lane went red.
  #
  # A heredoc is fine here, unlike upstream: that constraint is a Jinja
  # delimiter collision in the template set, and this is a plain shell script.
  cat > mykronos-results/osv.sarif <<'EOF'
{"$schema":"https://json.schemastore.org/sarif-2.1.0.json",
 "version":"2.1.0",
 "runs":[{"tool":{"driver":{"name":"osv-scanner",
   "informationUri":"https://github.com/google/osv-scanner","rules":[]}},
  "results":[],
  "invocations":[{"executionSuccessful":true,"exitCode":128,
   "exitCodeDescription":"no package sources found - repository declares no dependencies"}]}]}
EOF

  # Fail loudly if that JSON is malformed rather than shipping a broken artifact
  # that reads as evidence.
  python3 -c 'import json,sys; json.load(open("mykronos-results/osv.sarif"))'     || { echo "ERROR: generated an invalid empty SARIF" >&2; exit 1; }

  printf '%s' '{"results":[]}' > osv-json/osv.json
fi

# The atlas counts step downstream reads this file unconditionally.
test -s osv-json/osv.json || printf '%s' '{"results":[]}' > osv-json/osv.json

echo "OSV scan complete."
