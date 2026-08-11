#!/usr/bin/env bash
# Decide whether an epic may be verified as a BATCH at G4.
# Controls: SA-11, CA-2, RA-3 (risk-proportional assurance) · ADR-0002 · Refs #34
#
# ── WHY THIS IS A SCRIPT AND NOT A CHECKLIST LINE ────────────────────────────
# The rule "flagged stories cannot be batched" is the only thing standing between
# risk-proportional verification and simply doing less verification. A rule written in prose
# is advisory (AIC-3) — it holds until an agent, or a tired human at 1am, reads past it.
#
# This platform has already shipped defects that a prose constraint failed to prevent: three
# guard-hook failures (POAM-002/003/004), and a gitleaks allowlist that read as narrow, passed
# review by eye, and had silently blinded the scanner (#32).
#
# So the eligibility test is executable, it fails closed, and it names every story that
# disqualified the batch.
#
# Usage:  bash scripts/check-batch-eligibility.sh <epic-issue-number>
# Exit:   0 = may be batch-verified · 1 = must be verified per story

set -uo pipefail

EPIC="${1:-}"
MAX_BATCH="${KEEL_MAX_BATCH:-5}"
DISQUALIFYING='security-relevant|ai-relevant'

if [ -z "$EPIC" ]; then
  echo "usage: bash scripts/check-batch-eligibility.sh <epic-issue-number>" >&2
  exit 1
fi
command -v gh >/dev/null 2>&1 || { echo "gh CLI required" >&2; exit 1; }

REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)"
[ -n "$REPO" ] || { echo "not in a GitHub repo" >&2; exit 1; }

if [ -t 1 ]; then B=$'\033[1m'; R=$'\033[0m'; G=$'\033[32m'; Y=$'\033[33m'; X=$'\033[31m'
else B=; R=; G=; Y=; X=; fi

printf '\n%sBatch eligibility — epic #%s%s\n\n' "$B" "$EPIC" "$R"

# Children come from the native sub-issue relationship, not a task list or a label. A
# checkbox in a description is prose; the API relationship is data.
children="$(gh api "repos/$REPO/issues/$EPIC/sub_issues" --paginate \
  --jq '.[] | "\(.number)\t\(.state)\t\([.labels[].name] | join(","))\t\(.title)"' 2>/dev/null)"

if [ -z "$children" ]; then
  printf '  %s✗%s epic #%s has no sub-issues.\n' "$X" "$R" "$EPIC"
  printf '     An epic with no attached stories cannot be batch-verified — there is\n'
  printf '     nothing to verify, and an empty batch passing G4 would be a false claim.\n\n'
  exit 1
fi

n=0; blocked=0
declare -a FLAGGED=()

while IFS=$'\t' read -r num state labels title; do
  [ -n "$num" ] || continue
  n=$((n + 1))
  if printf '%s' "$labels" | grep -qE "$DISQUALIFYING"; then
    flag="$(printf '%s' "$labels" | tr ',' '\n' | grep -E "$DISQUALIFYING" | paste -sd'+' -)"
    FLAGGED+=("#$num [$flag] $title")
    blocked=1
  else
    printf '  %s✓%s #%-5s eligible   %s\n' "$G" "$R" "$num" "${title:0:58}"
  fi
done <<< "$children"

if [ "${#FLAGGED[@]}" -gt 0 ]; then
  printf '\n  %sIneligible — these carry a risk flag set at G1:%s\n' "$X" "$R"
  for f in "${FLAGGED[@]}"; do printf '  %s✗%s %s\n' "$X" "$R" "$f"; done
fi

printf '\n  %d story/stories; batch cap is %d\n' "$n" "$MAX_BATCH"

if [ "$n" -gt "$MAX_BATCH" ]; then
  printf '  %s✗%s over the cap by %d.\n' "$X" "$R" "$((n - MAX_BATCH))"
  printf '     A review of many stories at once is a formality wearing a review'"'"'s clothes.\n'
  printf '     Split the epic (ADR-0002 D5).\n'
  blocked=1
fi

echo
if [ "$blocked" -eq 0 ]; then
  printf '%sBATCH VERIFICATION PERMITTED%s\n' "$G" "$R"
  printf '  Run G4 once over all %d stories: combined threat surface, control\n' "$n"
  printf '  verification, exploratory charter, accumulated scan triage.\n'
  printf '  The per-commit checks already ran and are not repeated here.\n\n'
  exit 0
else
  printf '%sBATCH VERIFICATION REFUSED%s\n' "$X" "$R"
  printf '  Flagged stories get G2 up front and their own G4 (ADR-0002 D4). Run the\n'
  printf '  remaining eligible stories as a batch by moving the flagged ones to their\n'
  printf '  own epic — do NOT remove the label to make this pass.\n\n'
  printf '  %sRemoving a risk flag to clear this check is falsifying a triage decision%s\n' "$Y" "$R"
  printf '  %sand is a PD-7 violation, not a workaround.%s\n\n' "$Y" "$R"
  exit 1
fi
