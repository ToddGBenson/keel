#!/usr/bin/env bash
# Run the unit suites on a pull request head that pr-pick.sh checked out. Refs: TheHub #61778
#
# The same suites GitHub Actions runs as `unit-suites` (.github/workflows/unit-results.yml):
# every test/*.test.py, every test/*.test.js where node exists, the guard hook self-test
# and the agent evals. Every suite runs even after one fails; the task fails if any did.
#
# This task runs the pull request's code, so it is given no credential: no deploy key,
# no ingestion token, no params at all. The script itself is the BASE branch's copy
# (repo/), so a pull request cannot change how it is judged by editing this file.
#
# `pr-meta/.none` means pr-pick.sh found nothing to judge: a pass that runs nothing. That
# state is read from pr-meta/, which the picker owns. It is never read from pr/, the pull
# request's own tree: a file the author commits there must not decide whether the suites
# run (TheHub #62015).
set -uo pipefail

PR_DIR="${PR_DIR:-pr}"
META_DIR="${META_DIR:-pr-meta}"
if [ -f "$META_DIR/.none" ]; then
  echo "No pull request head to judge this run."
  exit 0
fi
[ -f "$META_DIR/.pr" ] || { echo "pr-meta/ has no picked head (.pr missing); refusing to judge." >&2; exit 1; }
read -r number sha branch < "$META_DIR/.pr"
# The checkout must be the head that was picked. A mismatch is refused, never judged.
checked_out=$(tr -d ' \n\r\t' < "$PR_DIR/.git/HEAD" 2>/dev/null || true)
if [ -z "$sha" ] || [ "$checked_out" != "$sha" ]; then
  echo "pr/ is not at the picked head (picked '${sha}', checked out '${checked_out}'); refusing to judge." >&2
  exit 1
fi
echo "Unit suites on #${number} ${sha} (${branch})."

# The pull request's own pins, as Actions installs them.
python -m pip install --quiet --disable-pip-version-check --root-user-action=ignore \
  --require-hashes -r "$PR_DIR/ci/requirements.txt" || { echo "pip install from $PR_DIR/ci/requirements.txt failed" >&2; exit 1; }

# The suites run from the pull request's checkout, as they do from the repository root
# on Actions. Paths below are inside pr/, which validate-pipeline.py does not judge (it
# checks repo/ references), so they are named through variables.
cd "$PR_DIR" || exit 1
git config --global --add safe.directory "$(pwd)" 2>/dev/null || true
SELFTEST=.claude/hooks/selftest.sh
EVALS=evals/run-agent-evals.sh

rc=0
failed=()
# TheHub #62268: each suite's time, so a run that overruns its timeout on a small worker
# says which suite took it. The slowest are listed again at the end.
timings=()
suite() {
  local name=$1 t0=$SECONDS took; shift
  echo "── ${name} ──"
  if "$@"; then took=$((SECONDS - t0)); echo "   ${name}: pass (${took} s)"
  else took=$((SECONDS - t0)); echo "   ${name}: FAIL (${took} s)"; rc=1; failed+=("$name"); fi
  timings+=("${took} ${name}")
}
shopt -s nullglob
for t in test/*.test.py; do suite "$(basename "$t" .py)" python "$t"; done
js=(test/*.test.js)
if [ "${#js[@]}" -gt 0 ]; then
  if command -v node >/dev/null 2>&1; then
    for t in "${js[@]}"; do suite "$(basename "$t" .js)" node "$t"; done
  else
    echo "── ${#js[@]} node test file(s) not run: no node in this image (they run on Actions and ./keel check) ──"
  fi
fi
suite guard-selftest bash "$SELFTEST"
suite agent-evals    bash "$EVALS"

echo
echo "Slowest suites (seconds), of ${SECONDS} s in all:"
printf '%s\n' "${timings[@]}" | sort -rn | head -n 5 | sed 's/^/   /'
if [ "$rc" -eq 0 ]; then
  echo "All unit suites passed on #${number} ${sha}."
else
  echo "Failed on #${number} ${sha}: ${failed[*]}"
fi
exit "$rc"
