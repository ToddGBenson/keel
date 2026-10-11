#!/bin/sh
# Runs shellcheck over every shell script in the repository. Refs: #42
#
# POSIX sh, not bash: this runs on the shellcheck image, which is Alpine and has
# busybox sh only. It is itself linted by the check it performs.
#
# Why this exists: shell is the largest body of code here — 3,785 lines across 28
# files — and until 2026-08-13 nothing checked any of it. Two of the High defects
# found during the Concourse port were shell bugs. shellcheck catches one of them
# outright (SC2097/SC2098, the assignment-prefix bug that made every Mykronos
# upload abort before calling the CLI) and does not catch the other (a
# pipefail/SIGPIPE inversion). One of two is worth having, and the claim is
# deliberately not larger than that.
#
# -S warning, not style: style findings on 28 existing scripts would have meant
# starting red, and a check that starts red gets muted before it ever catches
# anything (L0007).
set -eu

REPO="${REPO_DIR:-repo}"
OUT="${OUT_DIR:-shellcheck-report}"
RESULTS="${RESULTS_DIR:-mykronos-results}"
mkdir -p "$OUT" "$RESULTS"
# Absolute, because both shellcheck runs below `cd "$WORK"` first and read the
# file list from inside it. Relative, `$OUT/files.txt` did not exist from there:
# `cat` failed, shellcheck was called with no files, printed its usage and
# exited 3, and `| tee` reported tee's 0 instead. So until #105 this task printed
# "clean (30 files)" having read none of them. Measured 2026-10-11 by running
# this script in its own image.
OUT="$(cd "$OUT" && pwd)"
RESULTS="$(cd "$RESULTS" && pwd)"

shellcheck --version | head -2

# Line endings: a Windows checkout carries CRLF, which shellcheck reports as
# SC1017 on every line — 139 findings that say nothing about the code. Git
# normalises to LF via .gitattributes so the runner never sees them, but the
# scripts are also run locally, and a check whose output is 139 false positives
# on a developer machine is a check that gets ignored. Strip CR into a working
# copy rather than reporting noise.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

count=0
find "$REPO" -path "$REPO/.git" -prune -o -name '*.sh' -print | sort | while read -r f; do
  rel="${f#"$REPO"/}"
  mkdir -p "$WORK/$(dirname "$rel")"
  tr -d '\r' < "$f" > "$WORK/$rel"
  count=$((count + 1))
  echo "$rel"
done > "$OUT/files.txt"

n="$(wc -l < "$OUT/files.txt" | tr -d ' ')"
echo "Checking $n shell script(s)"

if [ "$n" -eq 0 ]; then
  # Not a pass. A repository with no shell is legitimate; a repository whose
  # shell became invisible to the linter is not, and the two must not look alike.
  echo "ERROR: found no shell scripts to check. Expected at least one." >&2
  echo "If this repository genuinely has no shell, remove this task." >&2
  exit 1
fi

# ── The MyKronos copy (#105, B-051) ──────────────────────────────────────────
# CodeQL implements no shell, so without this upload MyKronos reads keel as ~70%
# unread by any analyser. json1 because that is what its `sast_shellcheck`
# adapter parses; ShellCheck emits no SARIF. `-S style`, not the gate's
# `warning`: the platform filters against its own threshold, and dropping
# findings here would make "none" ambiguous between a clean scan and a narrow
# one. Written BEFORE the gate below so a gate failure still has results for the
# `ensure:` upload in the lint job to report.
#
# Exit 1 means ShellCheck had something to say, which is a result. Anything
# higher is the scanner failing, and an empty file would parse as zero findings
# - a clean scan for a scan that did not happen. Either way the file is removed,
# so the uploader sees an empty results directory and records a run that broke.
jrc=0
# shellcheck disable=SC2046  # deliberate word splitting over the file list;
# refs #105, expires: 2026-11-11
(cd "$WORK" && shellcheck -S style -f json1 $(cat "$OUT/files.txt")) \
  > "$RESULTS/shellcheck.json" || jrc=$?
if [ "$jrc" -gt 1 ] || [ ! -s "$RESULTS/shellcheck.json" ]; then
  rm -f "$RESULTS/shellcheck.json"
  echo "ERROR: shellcheck (json1) exited $jrc with no usable report." >&2
  echo "The scan did not complete; nothing is uploaded as if it had." >&2
  exit 1
fi
echo "MyKronos report: $(grep -o '"code":' "$RESULTS/shellcheck.json" | wc -l | tr -d ' ') comment(s), severity>=style"

rc=0
# Redirect, then print: `| tee` returned tee's status, not shellcheck's, so this
# gate could not fail (#105). The file is printed afterwards for the log.
# shellcheck disable=SC2046  # deliberate word splitting over the file list;
# refs #44, expires: 2026-11-11
(cd "$WORK" && shellcheck -S warning -f gcc $(cat "$OUT/files.txt")) \
  > "$OUT/findings.txt" || rc=$?
cat "$OUT/findings.txt"

if [ "$rc" -ne 0 ]; then
  echo "shellcheck: FAILED ($n files)" > "$OUT/status"
  echo "" >&2
  echo "shellcheck found issues at severity>=warning. Fix them, or add a" >&2
  echo "targeted 'shellcheck disable=SCxxxx' with an issue reference AND an" >&2
  echo "expiry date — the suppression audit enforces both." >&2
  exit "$rc"
fi

echo "shellcheck: clean ($n files, severity>=warning)" > "$OUT/status"
cat "$OUT/status"
