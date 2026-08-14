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
mkdir -p "$OUT"

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

rc=0
# shellcheck disable=SC2046  # deliberate word splitting over the file list;
# refs #44, expires: 2026-11-11
(cd "$WORK" && shellcheck -S warning -f gcc $(cat "$OUT/files.txt")) \
  | tee "$OUT/findings.txt" || rc=$?

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
