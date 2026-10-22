#!/usr/bin/env bash
# SCA — dependency vulnerabilities. Refs: #42
set -euo pipefail

SEVERITY_CUTOFF="${SEVERITY_CUTOFF:-high}"

# GATE decides whether this run fails the build on findings. Refs: #133
#   true  (default) -- the `sca` job. Fails at or above SEVERITY_CUTOFF, exactly
#                      as it did before GATE existed.
#   false           -- the `mykronos-sca` upload lane. Findings are a result for
#                      the uploader to record, not a reason to fail the step, so
#                      `--fail-on` is not passed. The upload lane does not decide
#                      CI outcomes, same as `mykronos-secrets`.
# Anything else is refused: a typo must not switch the gate off.
GATE="${GATE:-true}"
case "${GATE}" in
  true|false) ;;
  *) echo "ERROR: GATE must be 'true' or 'false', got '${GATE}'" >&2; exit 2 ;;
esac

# The pin is checked after the manifest-presence test below, not before it, so
# a run with nothing to scan fails for THAT reason and says so, rather than over
# a tool version it was never going to use.

# NOTHING TO SCAN IS A FAILURE (operator decision, TheHub #60935, 2026-10-22).
# The same rule the 2026-09-23 decision applied to `iac`, and for the same
# reason: a lane that exits 0 when it checked nothing is a green build that
# asserts nothing, and the NOT-A-PASS banner it printed went unread in a log
# while the job status said "passed". See ci/lane-audit-2026-10-11.md.
#
# It applies in BOTH modes. GATE=false means "findings do not fail the step";
# it never meant "not scanning is fine". With no manifest there is no SARIF,
# so the upload lane has nothing true to record either.
#
# A repository with no dependency manifest is still legitimate. The fix for a
# red `sca` there is to remove the lane from that fork's pipeline on purpose,
# with a reason, not to let it pass by default.
#
# `-print -quit` and no pipe: `find ... | grep -q .` inverts under `set -o
# pipefail` once find's output outruns the pipe buffer, because grep closes the
# pipe and find exits 141. That renders as "nothing to scan" on exactly the
# large repositories where scanning matters. See the long note in
# ci/scripts/codeql.sh.
if [ -z "$(find repo -path repo/.git -prune -o \
     \( -name 'package.json' -o -name 'package-lock.json' -o -name 'yarn.lock' \
        -o -name 'requirements*.txt' -o -name 'pyproject.toml' -o -name 'Pipfile.lock' \
        -o -name 'go.mod' -o -name 'Cargo.toml' -o -name 'Gemfile.lock' \
        -o -name 'pom.xml' -o -name 'build.gradle*' -o -name 'composer.json' \) \
     -print -quit 2>/dev/null)" ]; then
  cat >&2 <<'EOF'

================================================================================
SCA: no dependency manifests found -- FAILING

Nothing was scanned, so RA-5/SR-3 has no evidence from this run. A no-subject
scan is a failure, not a pass (TheHub #60935; the rule `iac` follows since
2026-09-23). If this repository genuinely has no dependencies, remove the `sca`
lane from its pipeline deliberately and record why.
================================================================================

EOF
  exit 1
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
#
# With GATE=false there is no `--fail-on`, so a non-zero exit can only mean grype
# itself failed. That is reported as a scan failure below, never as a clean scan.
fail_on=()
if [ "${GATE}" = "true" ]; then
  fail_on=(--fail-on "${SEVERITY_CUTOFF}")
fi

rc=0
grype "dir:repo" \
  --output sarif \
  --file sca-results/grype.sarif \
  ${fail_on[@]+"${fail_on[@]}"} || rc=$?

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

if [ "${rc}" -ne 0 ] && [ "${GATE}" = "false" ]; then
  echo "ERROR: grype exited ${rc} with no --fail-on — that is a scan failure, not a findings result." >&2
  exit "${rc}"
fi

if [ "${rc}" -ne 0 ]; then
  echo "ERROR: grype found vulnerabilities at or above '${SEVERITY_CUTOFF}'." >&2
  echo "The SARIF is in the build artifacts. Disposition each result at G4 —" >&2
  echo "true positive / false positive (rationale AND expiry) / accepted risk." >&2
  exit "${rc}"
fi
