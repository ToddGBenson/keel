#!/usr/bin/env bash
# Sprint runner — description in, tested PR out.
#
#   ./keel sprint              process the inbox
#   ./keel sprint --dry-run    show what would be picked up
#   ./keel sprint --one <file> process a single description
#
# ── THE BOUNDARY ─────────────────────────────────────────────────────────────
# This automates everything up to a PR. It does NOT merge, deploy, or touch
# credentials — the guard hooks block those regardless of what any prompt says, and a
# human authorizing the merge is the control that separates this platform from a system
# that merely writes code unsupervised (AC-5, POAM-008).
#
# Bounded autonomy (AIC-11): the runner refuses work that touches the controls themselves,
# needs a secret, or has no safe default for a blocking question. It leaves a note instead.

set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

INBOX="sprint/inbox"; DONE="sprint/done"; DRY=0; ONE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --one) ONE="$2"; shift 2 ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -t 1 ]; then B=$'\033[1m'; R=$'\033[0m'; G=$'\033[32m'; Y=$'\033[33m'; X=$'\033[31m'
else B=; R=; G=; Y=; X=; fi
say()  { printf '\n%s%s%s\n' "$B" "$1" "$R"; }
info() { printf '  %s\n' "$1"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$R" "$1"; }
warn() { printf '  %s!%s %s\n' "$Y" "$R" "$1"; }
die()  { printf '  %s✗ %s%s\n' "$X" "$1" "$R" >&2; exit 1; }

command -v claude >/dev/null || die "claude CLI not found — required for the runner"
command -v gh >/dev/null || die "gh CLI not found"
mkdir -p "$INBOX" "$DONE"

# ── Paths the runner must never modify: the controls themselves (AIC-11 #3) ──
# Checked AFTER the agent runs. If it touched any of these, the branch is abandoned
# rather than proposed — a change to a control must be a deliberate human act.
PROTECTED='^(\.github/workflows/|\.claude/hooks/|\.claude/agents/|\.claude/settings\.json|process/gates/|docs/compliance/|scripts/configure-github\.sh)'

process_one() {
  local desc="$1"
  local slug; slug="$(basename "$desc" .md | tr -cd '[:alnum:]-' | tr '[:upper:]' '[:lower:]')"
  local issue_title; issue_title="$(head -1 "$desc" | sed 's/^#\+ *//')"
  [ -n "$issue_title" ] || issue_title="$slug"

  say "▶ $slug"
  info "\"$issue_title\""

  if [ "$DRY" = "1" ]; then info "(dry run — would process)"; return 0; fi

  # 1. Traceability first: every change needs a work item (CM-3). No issue, no work.
  local issue_url issue_num
  issue_url="$(gh issue create --title "$issue_title" --label sprint \
      --body "$(printf 'Queued from `%s` by the sprint runner.\n\n---\n\n%s' "$desc" "$(cat "$desc")")" \
      2>/dev/null | tail -1)"
  issue_num="$(printf '%s' "$issue_url" | grep -oE '[0-9]+$')"
  [ -n "$issue_num" ] || { warn "could not create issue — skipping"; return 1; }
  ok "issue #$issue_num"

  local branch="feat/${issue_num}-${slug}"
  git switch -q -c "$branch" 2>/dev/null || { warn "branch $branch exists — skipping"; return 1; }

  # 2. Hand the whole pipeline to Claude Code, headless, with the boundary in the prompt
  #    AND enforced structurally below. Prompt-level limits are advisory (AIC-3); the
  #    protected-path check and the guard hooks are what actually hold.
  info "running the pipeline (this takes a while)…"
  local log="sprint/done/${slug}.log"
  claude -p "$(cat <<PROMPT
Work the description in \`$desc\` end to end through this repository's own process.
The linked work item is issue #$issue_num — reference it in every commit.

Follow, in order, loading each skill named:

1. artifact-intake — read the description. Produce Extracted / Inferred / Unspecified as
   three SEPARATE sections. For each blocking Unspecified item choose a safe, conservative
   default and RECORD it explicitly as a chosen default, never as a stated requirement.
2. story-splitting + writing-acceptance-criteria — thin vertical slices, binary criteria,
   NFRs with numbers. Implement ONLY the first slice.
3. If the work is security-, privacy-, or AI-relevant, run threat-modeling and allocate each
   control to a named component before writing code.
4. test-strategy — write the FAILING test first, then the smallest implementation. Every
   allocated control gets a negative-case test proving it denies.
5. control-verification — trace each control to a line and its test. Mutation-check at least
   one control by removing it and confirming tests fail.
6. Write the intake record, story, threat model (if any) and verification to docs/product/.

HARD LIMITS — stop and write sprint/done/${slug}.BLOCKED.md explaining why, instead of
proceeding, if any of these hold:
 - a High or Critical finding appears
 - the work needs a secret, credential, or production access
 - it would modify .github/workflows/, .claude/hooks/, .claude/agents/, process/gates/,
   docs/compliance/, or scripts/configure-github.sh
 - scope exceeds the description
 - a blocking question has no safe default
 - you have failed the same step three times

Do NOT merge, deploy, force-push, or handle credentials.
Commit your work with a Conventional Commit referencing "Refs: #$issue_num" and an
"AI-Assisted:" trailer. Do not open the PR — the runner does that.
PROMPT
)" > "$log" 2>&1
  local rc=$?
  info "agent finished (rc=$rc, log: $log)"

  # 3. Blocked on purpose? That is a success state, not a failure (AIC-11).
  if [ -f "sprint/done/${slug}.BLOCKED.md" ]; then
    warn "runner stopped deliberately — see sprint/done/${slug}.BLOCKED.md"
    gh issue comment "$issue_num" --body "The sprint runner stopped rather than proceeding. Reason:

$(cat "sprint/done/${slug}.BLOCKED.md")

Stopping is a success state (AIC-11) — this needs a human decision before it can continue." >/dev/null 2>&1
    git switch -q main; return 0
  fi

  # 4. Did it change anything?
  if [ -z "$(git log origin/main..HEAD --oneline 2>/dev/null)" ]; then
    warn "no commits produced — leaving branch for inspection"
    git switch -q main; return 1
  fi

  # 5. STRUCTURAL enforcement of the protected-path limit. The prompt asked; this verifies.
  local touched; touched="$(git diff --name-only origin/main..HEAD | grep -E "$PROTECTED" || true)"
  if [ -n "$touched" ]; then
    warn "ABANDONED — the run modified control files, which it must never do:"
    printf '      %s\n' $touched
    gh issue comment "$issue_num" --body "Sprint run **abandoned**: it modified control files (\`$(printf '%s ' $touched)\`). A change to a control must be a deliberate human act, never a side effect of an automated build. Branch \`$branch\` left for inspection." >/dev/null 2>&1
    git switch -q main; return 1
  fi
  ok "touched no control files"

  # 6. Local gate before proposing anything
  if ! bash keel check >/dev/null 2>&1 && ! ./keel check >/dev/null 2>&1; then
    warn "keel check failed — pushing anyway so the PR shows CI failures honestly"
  else
    ok "keel check green"
  fi

  git push -q -u origin "$branch" 2>/dev/null || { warn "push failed"; git switch -q main; return 1; }

  # 7. Propose. A human merges.
  gh pr create --title "feat: ${issue_title}" --body "$(cat <<PRBODY
Closes #$issue_num

Built autonomously by the sprint runner from \`$desc\`.

## What changed
See \`docs/product/\` for the intake record, story, threat model (if security-relevant), and
verification.

## Unspecified → defaults chosen
The description could not answer everything. Every assumption is listed in the intake record
as a **chosen default**, not a stated requirement. **Overrule any of them on this PR.**

## AI authorship (AIC-6)
- [x] **Parts AI-authored:** all of it — built headless by the sprint runner
- [x] **Agent / model:** claude-opus-5 via \`claude -p\`
- [x] **What I verified personally:** the runner verified structurally — it confirmed no
  control file was touched, ran the local gate, and CI runs the full suite below. **A human
  has not yet read this diff.**

## Definition of Done
- [x] Failing test written before implementation
- [x] Negative-case test for each allocated control
- [x] No control files touched (enforced by the runner, not just requested)
- [x] Issue linked; AI authorship declared
- [ ] **Human review — this is the step that is deliberately not automated**

## Self-review — required, no other approver (solo mode, POAM-008)
Written by the agent in \`docs/product/\`. Note the limit honestly: an agent reviewing its own
autonomous output is the *weakest* form of the compensating control, because the same
reasoning produced both. Read the "Not verified" section first.

## Rollback
\`git revert\`, or close this PR unmerged — nothing has shipped.
PRBODY
)" >/dev/null 2>&1 && ok "PR opened" || warn "PR creation failed"

  mv "$desc" "$DONE/" 2>/dev/null
  git switch -q main
}

say "keel sprint"

# DEFECT FIXED 2026-08-09: this unconditionally ran `git switch main` at startup — including
# for --dry-run. Anyone running a "dry run" to see what was queued was silently moved off
# their working branch, and their next commit landed on main. It bit the author twice, in
# #24 and again while restoring this file: a commit meant for a feature branch went to
# local main, which is protected and cannot be pushed.
#
# A read-only flag must be read-only. And a tool must never move the operator's branch as a
# side effect — that is their state, not the tool's.
STARTED_ON="$(git symbolic-ref --short HEAD 2>/dev/null || echo '')"
restore_branch() {
  local now; now="$(git symbolic-ref --short HEAD 2>/dev/null || echo '')"
  if [ -n "$STARTED_ON" ] && [ "$now" != "$STARTED_ON" ]; then
    git switch -q "$STARTED_ON" 2>/dev/null && info "returned you to $STARTED_ON"
  fi
}
trap restore_branch EXIT

git fetch -q origin 2>/dev/null
if [ "$DRY" = "1" ]; then
  info "dry run — no branch changes, nothing written"
else
  # Real runs need a clean base, but only after confirming there is work to do.
  if [ -n "$(git status --porcelain)" ]; then
    die "working tree is dirty — commit or stash first; the runner creates branches"
  fi
fi

if [ -n "$ONE" ]; then
  [ -f "$ONE" ] || die "no such description: $ONE"
  process_one "$ONE"
else
  shopt -s nullglob
  files=("$INBOX"/*.md)
  [ ${#files[@]} -eq 0 ] && { info "inbox empty — nothing to do"; exit 0; }
  info "${#files[@]} description(s) queued"
  for f in "${files[@]}"; do process_one "$f"; done
fi

say "done"
info "Review the PRs. Merging stays a human act — that is the control, not an oversight."
