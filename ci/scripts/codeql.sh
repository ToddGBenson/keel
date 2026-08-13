#!/usr/bin/env bash
# SAST via the CodeQL CLI. Refs: #42
#
# github/codeql-action does not exist outside GitHub Actions. It is, underneath,
# a downloader for `codeql-bundle-linux64.tar.gz` plus three CLI calls. This runs
# the same bundle and the same calls, so the analysis is the same analysis.
#
# ── WHAT CHANGED, HONESTLY ────────────────────────────────────────────────────
# The Actions version uploaded SARIF to the GitHub code scanning API, which is
# where its results were read. That API is not reachable from Concourse. For the
# Mykronos lane this costs nothing — Mykronos is the system of record for
# findings and the uploader still receives the SARIF. For the keel-owned `sast`
# lane it means results land as a build artifact and a printed summary instead of
# in the Security tab. Recorded in docs/compliance/poam.md.
set -euo pipefail

: "${CODEQL_LANGUAGE:?CODEQL_LANGUAGE is required}"
: "${CODEQL_BUNDLE_VERSION:?CODEQL_BUNDLE_VERSION is required — pin the bundle}"
: "${CODEQL_BUNDLE_SHA256:?CODEQL_BUNDLE_SHA256 is required — see ci/README.md}"

CODEQL_QUERIES="${CODEQL_QUERIES:-security-extended}"

# ── Language identifiers ──────────────────────────────────────────────────────
# The Actions matrix uses names like `javascript-typescript` and `java-kotlin`.
# The CLI uses the underlying extractor names, and the query packs use a third
# spelling. Mapping all three here rather than hoping they coincide — they do not.
case "${CODEQL_LANGUAGE}" in
  python)                cli_lang=python;     pack=python;     find_pat='-name *.py' ;;
  javascript-typescript) cli_lang=javascript; pack=javascript; find_pat='-name *.js -o -name *.jsx -o -name *.ts -o -name *.tsx -o -name *.mjs -o -name *.cjs' ;;
  javascript)            cli_lang=javascript; pack=javascript; find_pat='-name *.js -o -name *.jsx -o -name *.mjs -o -name *.cjs' ;;
  go)                    cli_lang=go;         pack=go;         find_pat='-name *.go' ;;
  java-kotlin)           cli_lang=java;       pack=java;       find_pat='-name *.java -o -name *.kt' ;;
  csharp)                cli_lang=csharp;     pack=csharp;     find_pat='-name *.cs' ;;
  ruby)                  cli_lang=ruby;       pack=ruby;       find_pat='-name *.rb' ;;
  c-cpp)                 cli_lang=cpp;        pack=cpp;        find_pat='-name *.c -o -name *.cc -o -name *.cpp -o -name *.h' ;;
  *)
    echo "ERROR: unknown CODEQL_LANGUAGE '${CODEQL_LANGUAGE}'." >&2
    echo "Add it to the mapping in ci/scripts/codeql.sh rather than guessing." >&2
    exit 1
    ;;
esac

# ── Is there anything to scan? ────────────────────────────────────────────────
# THIRD occurrence of this defect class in the Actions workflows (L0008): a
# scanner configured for input that is not present fails on plumbing, and a red
# gate for a non-finding reason trains people to ignore it. SCA and IaC had it
# too.
#
# The rule: detect the input, skip LOUDLY when it is absent, and never let
# "nothing to scan" render as a green pass.
# shellcheck disable=SC2086
if ! find repo -path repo/.git -prune -o -path repo/node_modules -prune -o \( ${find_pat} \) -print 2>/dev/null | grep -q .; then
  cat <<EOF

================================================================================
SAST SKIPPED — no ${CODEQL_LANGUAGE} source found

SA-11(1) is NOT satisfied for code in this run — no code was analysed.
This is a scope statement, not a pass. It becomes applicable as soon as source
is added. Secret, IaC, and dependency scanning still ran.
================================================================================

EOF
  # The results directory stays empty on purpose. For the Mykronos lane that is
  # the signal the uploader reads to record "no applicable targets" rather than
  # a clean scan.
  exit 0
fi

# ── Fetch and verify the bundle ───────────────────────────────────────────────
# The bundle is the thing performing the security analysis. Fetching it
# unverified would undercut the entire job, so the checksum is required and a
# mismatch is fatal.
bundle="codeql-bundle-linux64.tar.gz"
url="https://github.com/github/codeql-action/releases/download/codeql-bundle-${CODEQL_BUNDLE_VERSION}/${bundle}"

echo "Fetching CodeQL bundle ${CODEQL_BUNDLE_VERSION}"
curl -sSfL -o "${bundle}" "${url}"
echo "${CODEQL_BUNDLE_SHA256}  ${bundle}" | sha256sum -c -

tar -xzf "${bundle}"
export PATH="${PWD}/codeql:${PATH}"
codeql version --format=terse

# ── Build the database ────────────────────────────────────────────────────────
# No --command for python/javascript/ruby: they are extracted directly from
# source. Compiled languages need a build command here, which is what the
# Actions `autobuild` step was doing. If you enable one, pass it explicitly
# rather than relying on autodetection — a silent autobuild failure produces an
# empty database and a clean-looking report.
echo "Building CodeQL database for ${cli_lang}"
codeql database create codeql-db \
  --language="${cli_lang}" \
  --source-root=repo \
  --overwrite

# ── Analyse ───────────────────────────────────────────────────────────────────
# CODEQL_QUERIES is the Actions `queries:` list, e.g.
# "security-extended,security-and-quality". Each entry maps to a suite inside the
# bundle's query pack.
suites=()
IFS=',' read -ra requested <<< "${CODEQL_QUERIES}"
for q in "${requested[@]}"; do
  q="$(echo "${q}" | xargs)"   # trim
  [ -z "${q}" ] && continue
  suites+=("codeql/${pack}-queries:codeql-suites/${pack}-${q}.qls")
done

if [ ${#suites[@]} -eq 0 ]; then
  echo "ERROR: CODEQL_QUERIES resolved to no suites." >&2
  exit 1
fi

echo "Analysing with: ${suites[*]}"
codeql database analyze codeql-db \
  --format=sarif-latest \
  --output="mykronos-results/codeql.sarif" \
  --sarif-category="/language:${CODEQL_LANGUAGE}" \
  -- "${suites[@]}"

# ── Report ────────────────────────────────────────────────────────────────────
# A green badge on a job that scanned nothing is the most common form of false
# assurance in a pipeline, so say what was actually found either way.
python3 - <<'PY'
import json, pathlib, sys, collections

sarif = pathlib.Path("mykronos-results/codeql.sarif")
if not sarif.exists():
    print("No SARIF produced.")
    sys.exit(0)

doc = json.loads(sarif.read_text())
results = [r for run in doc.get("runs", []) for r in run.get("results", [])]

# SARIF severity lives in the rule, not the result, so build the lookup first.
levels = collections.Counter()
for run in doc.get("runs", []):
    rules = {
        r.get("id"): r
        for r in run.get("tool", {}).get("driver", {}).get("rules", [])
    }
    for res in run.get("results", []):
        rule = rules.get(res.get("ruleId"), {})
        sev = (
            rule.get("properties", {}).get("security-severity")
            or res.get("level")
            or "unknown"
        )
        levels[str(sev)] += 1

print(f"\nCodeQL findings: {len(results)}")
for sev, n in sorted(levels.items()):
    print(f"  {sev}: {n}")
PY

if [ "${UPLOAD_TO_MYKRONOS:-false}" != "true" ]; then
  cat <<'EOF'

NOTE: this lane no longer publishes to GitHub code scanning — that API is not
reachable from Concourse. The SARIF above is the evidence; read it. Findings for
this repository are tracked in Mykronos via the `mykronos-sast` job.
EOF
fi
