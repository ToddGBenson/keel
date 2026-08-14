#!/usr/bin/env bash
# Agent assurance — the runnable half of AIC-12.
# Controls: AI RMF MEASURE 2.3/2.5, MANAGE 4.1 · 800-53 CA-2, CA-7
#
# AIC-12 says "evaluate the agents themselves." Two halves, and honesty about which
# is which is the whole point (see docs/lessons/0006 — never claim what you don't run):
#
#   STRUCTURAL  — invariants a machine can check with no model. Runs here, in CI, every
#                 time. If the developer agent lost its "never approve its own work"
#                 boundary, or an agent's tool grant drifted from the inventory, this fails.
#
#   BEHAVIORAL  — does the agent still DO its job on a seeded case? Needs a live model, so
#                 it cannot run for free in CI. Enumerated here as an operator checklist to
#                 run monthly via the Task tool. The cases live in evals/agents/*.md with
#                 their expected verdicts, so "did it still catch the planted bug" is a
#                 repeatable measurement, not a vibe.
#
# Usage:  bash evals/run-agent-evals.sh          (structural + the behavioral checklist)

set -uo pipefail
cd "$(dirname "$0")/.." || { echo "cannot reach repo root" >&2; exit 1; }
PY="$(command -v python3 || command -v python || echo python)"
fail=0
if [ -t 1 ]; then G=$'\033[32m'; Y=$'\033[33m'; X=$'\033[31m'; B=$'\033[1m'; R=$'\033[0m'; else G=; Y=; X=; B=; R=; fi
ok()  { printf '  %s✓%s %s\n' "$G" "$R" "$1"; }
bad() { printf '  %s✗%s %s\n' "$X" "$R" "$1"; fail=1; }

printf '%s\n' "${B}Agent assurance — structural (AIC-12)${R}"

# ── 1. Each agent still carries its hard boundary ───────────────────────────
# The one sentence that, if deleted, silently turns a control off. A prompt-level
# check — weak on its own, but its ABSENCE is a strong signal something was edited out.
# Needles are deliberately tolerant of phrasing ("do not" / "does not" / "never") — the
# check exists to catch a DELETED boundary, not to police wording. Over-tight needles
# produced four false failures on the first run (L0007). Use extended regex.
check_phrase() { # file  ere-needle  label
  if grep -qiE "$2" ".claude/agents/$1" 2>/dev/null; then ok "$1: $3"
  else bad "$1: MISSING boundary — $3"; fi
}
check_phrase developer.md         "never review"                    "does not review its own work (AC-5)"
check_phrase developer.md         "test.*first|failing test"        "test-first"
check_phrase security-engineer.md "block"                           "blocking authority on Critical/High"
check_phrase security-engineer.md "do(es)? not write the"           "does not write the code it verifies"
check_phrase qa-engineer.md       "do(es)? not fix"                 "does not fix what it finds"
check_phrase ai-risk-officer.md   "block"                           "blocking authority on AI Critical/High"
check_phrase product-owner.md     "cannot override"                 "cannot override a security/AI rejection"
check_phrase release-manager.md   "do(es)? not authorize|human"     "does not self-authorize the release"
check_phrase compliance-officer.md "assess|do(es)? not"             "assesses, does not implement"
check_phrase architect.md         "do(es)? not implement|not.*implement" "does not implement"

# ── 2. Tool grants match the inventory (the enforceable half of AIC-3) ──────
if "$PY" scripts/validate-platform.py --quiet >/dev/null 2>&1; then
  ok "tool grants match ai-inventory.md (validate-platform)"
else
  bad "tool-grant drift — run: $PY scripts/validate-platform.py"
fi

# ── 3. Seeded behavioral cases are present and well-formed ──────────────────
# Case files are NNN-*.md; README.md is not a case. "Expected verdict" may appear under a
# heading, so don't anchor to line start (that was a false failure on run one).
n_cases=0
for c in evals/agents/[0-9]*.md; do
  [ -e "$c" ] || continue
  n_cases=$((n_cases+1))
  grep -qi 'Expected verdict' "$c" || bad "$(basename "$c"): no 'Expected verdict'"
done
[ "$n_cases" -gt 0 ] && ok "$n_cases seeded behavioral case(s) present" || bad "no seeded cases in evals/agents/"

echo
printf '%s\n' "${B}Agent assurance — behavioral (operator, monthly)${R}"
echo "  Run each case via the Task tool against a FRESH agent invocation. Record"
echo "  pass/fail to evidence/ai-assurance/agent-evals/\$(date)/. A regression is a"
echo "  defect against the agent definition — fix it through /learn."
echo
for c in evals/agents/[0-9]*.md; do
  [ -e "$c" ] || continue
  title="$(grep -m1 '^# ' "$c" | sed 's/^# //')"
  printf '    %s→%s %s\n' "$Y" "$R" "$title"
done

echo
if [ "$fail" -eq 0 ]; then
  printf '%s\n' "  ${G}structural assurance: all invariants hold${R}"
else
  printf '%s\n' "  ${X}structural assurance FAILED — an agent lost a documented control${R}"
  echo "  This is a control failure, not a style issue. File it and fix via /learn."
  exit 1
fi
