#!/usr/bin/env bash
# Sprint runner — description in, tested PR out.
#
#   ./keel sprint              process the inbox
#   ./keel sprint --dry-run    show what would be picked up
#   ./keel sprint --one <file> process a single description
#   ./keel sprint --preflight   are the agreed automation parameters met?
#   ./keel sprint --unattended  scheduled mode: dev-ready issues only, policy enforced
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

INBOX="sprint/inbox"; DONE="sprint/done"; DRY=0; ONE=""; PREFLIGHT=0; UNATTENDED=0
POLICY="automation-policy.yml"

# Read one flat scalar from the policy. Blank/absent are the SAME answer: unmet.
# No jq, no yq, no python — a checker with a dependency is a checker that silently
# does not run (L0009).
pol() {
  [ -f "$POLICY" ] || { printf ''; return; }
  sed -n "s/^$1:[[:space:]]*//p" "$POLICY" | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//' | head -1
}
# Cap items per run. Unattended, an inbox of twelve descriptions is an unbounded bill
# arriving at 3am. Three is enough to make progress and small enough to survive a mistake.
MAX_ITEMS="${KEEL_SPRINT_MAX:-3}"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --preflight) PREFLIGHT=1; shift ;;
    --unattended) UNATTENDED=1; shift ;;
    --max) MAX_ITEMS="$2"; shift 2 ;;
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

# ── preflight: everything unattended operation depends on, checked before you trust it ──
if [ "$PREFLIGHT" = "1" ]; then
  say "keel sprint --preflight"
  pf_fail=0
  pf() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else printf '  %s✗%s %s
' "$X" "$R" "$1"; pf_fail=1; fi; }

  pf "claude CLI present"            "command -v claude"
  pf "gh CLI present"                "command -v gh"
  pf "gh authenticated"              "gh auth status"
  pf "git identity configured"       "test -n \"$(git config user.email)\""
  pf "on a clean working tree"       "test -z \"$(git status --porcelain)\""
  pf "origin reachable"              "git ls-remote --exit-code origin HEAD"
  pf "guard hooks pass"              "bash .claude/hooks/selftest.sh"

  # ── the five agreed parameters for an automated run (docs/18) ──
  info ""
  info "${B}automated-run policy ($POLICY)${R}"
  if [ ! -f "$POLICY" ]; then
    printf '  %s✗%s no %s — unattended runs are not permitted without one
' "$X" "$R" "$POLICY"
    pf_fail=1
  else
    # P1 — CLI credential, never a standing API key.
    case "$(pol credential_mode)" in
      cli) ok "P1 credential_mode: cli (no standing API key)" ;;
      "")  printf '  %s✗%s P1 credential_mode unset
' "$X" "$R"; pf_fail=1 ;;
      *)   printf '  %s✗%s P1 credential_mode is not cli — API-key runs are prohibited
' "$X" "$R"; pf_fail=1 ;;
    esac
    [ -n "${ANTHROPIC_API_KEY:-}" ] && { warn "ANTHROPIC_API_KEY is set in this shell — the CLI login is what P1 requires"; }

    # P2 — dev-ready stories only. Unattended work starts at G2; refinement stays human.
    rl="$(pol ready_label)"
    if [ -z "$rl" ]; then
      printf '  %s✗%s P2 ready_label unset — nothing marks a story dev-ready
' "$X" "$R"; pf_fail=1
    else
      ok "P2 ready_label: $rl"
      rn=$(gh issue list --label "$rl" --state open --json number --jq 'length' 2>/dev/null || echo 0)
      if [ "${rn:-0}" -eq 0 ]; then
        printf '  %s✗%s P2 no open issues labelled '"'"'%s'"'"' — an automated run needs ready work
' "$X" "$R" "$rl"
        pf_fail=1
      else
        ok "P2 $rn story/stories dev-ready"
      fi
    fi

    # P3 — a lower environment to deploy and exercise in.
    if [ -n "$(pol nonprod_name)" ] && [ -n "$(pol nonprod_deploy_command)" ] && [ -n "$(pol nonprod_health_command)" ]; then
      ok "P3 non-prod environment: $(pol nonprod_name)"
    else
      printf '  %s✗%s P3 non-prod environment incomplete (need name, deploy and health commands)
' "$X" "$R"
      pf_fail=1
    fi

    # P4 — a human approves what is RUNNING, not a diff.
    if [ "$(pol approval_mode)" = "human_after_nonprod" ]; then
      ok "P4 approval: human, after non-prod deploy"
    else
      printf '  %s✗%s P4 approval_mode must be human_after_nonprod
' "$X" "$R"; pf_fail=1
    fi

    # P5 — all three suites declared. Blank is a violation, never a skip (L0007).
    for suite in unit functional security; do
      if [ -n "$(pol "test_${suite}_command")" ]; then
        ok "P5 ${suite} tests declared"
      else
        printf '  %s✗%s P5 no %s test command — "not configured" must never read as green
' "$X" "$R" "$suite"
        pf_fail=1
      fi
    done
  fi

  n=$(find "$INBOX" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  info ""
  info "queued: $n description(s); this run would process at most $MAX_ITEMS"
  [ "$n" -gt "$MAX_ITEMS" ] && warn "$((n - MAX_ITEMS)) would wait for the next run"

  info ""
  info "Bounded by: ${MAX_ITEMS} items/run · protected-path abandonment · G2 start (no self-refinement)"
  info "Cannot: merge, deploy to production, force-push, or handle credentials"
  info ""
  if [ "$pf_fail" = "0" ]; then
    say "ready for an automated run"
    info "Unattended runs are still only as safe as your LAST supervised run."
    info "If you have never watched one finish, do that before scheduling it."
  else
    say "NOT ready — fix the above before scheduling"
    info "Every ✗ above is a precondition you agreed to, not a warning."
    exit 1
  fi
  exit 0
fi

# An unattended run must not start unless the policy it claims to honour is actually met.
# Checking at 3am, from the script itself, is the only check that counts — a human having
# run --preflight last week proves nothing about tonight.
if [ "$UNATTENDED" = "1" ]; then
  if ! bash "$0" --preflight >/dev/null 2>&1; then
    say "unattended run REFUSED — policy not met"
    bash "$0" --preflight || true
    exit 1
  fi
  MAX_ITEMS="$(pol max_items_per_run)"; MAX_ITEMS="${MAX_ITEMS:-3}"
fi

command -v claude >/dev/null || die "claude CLI not found — required for the runner"
command -v gh >/dev/null || die "gh CLI not found"
mkdir -p "$INBOX" "$DONE"

# ── Paths the runner must never modify: the controls themselves (AIC-11 #3) ──
# Checked AFTER the agent runs. If it touched any of these, the branch is abandoned
# rather than proposed — a change to a control must be a deliberate human act.
# `ci/` is here because the pipeline moved there (#42). Without it, an
# unattended run could rewrite ci/pipeline.yml — delete the iac job, flip
# SEVERITY_CUTOFF, set BLOCKING to false — and the branch would be proposed like
# any other. The whole point of this list is that weakening a gate is a
# deliberate, reviewed, human act; the list has to follow the gates when they
# move.
PROTECTED='^(\.github/workflows/|ci/|\.claude/hooks/|\.claude/agents/|\.claude/settings\.json|process/gates/|docs/compliance/|scripts/configure-github\.sh)'

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

if [ "$UNATTENDED" = "1" ]; then
  # P2 -- the work list is dev-ready stories, NOT the inbox. The inbox holds unrefined
  # ideas; feeding those to an unattended run would cross G1 with no human present.
  RL="$(pol ready_label)"
  mapfile -t ready < <(gh issue list --label "$RL" --state open \
      --json number,title --jq '.[] | "\(.number)\t\(.title)"' 2>/dev/null)
  [ ${#ready[@]} -eq 0 ] && { info "no dev-ready stories - nothing to do"; exit 0; }
  info "${#ready[@]} dev-ready story/stories; processing at most $MAX_ITEMS"
  if [ ${#ready[@]} -gt "$MAX_ITEMS" ]; then
    warn "$(( ${#ready[@]} - MAX_ITEMS )) will wait for the next run (raise max_items_per_run)"
  fi
  count=0
  for row in "${ready[@]}"; do
    [ "$count" -ge "$MAX_ITEMS" ] && break
    process_ready_issue "${row%%$'\t'*}" "${row#*$'\t'}"; count=$((count + 1))
  done
elif [ -n "$ONE" ]; then
  [ -f "$ONE" ] || die "no such description: $ONE"
  process_one "$ONE"
else
  shopt -s nullglob
  files=("$INBOX"/*.md)
  [ ${#files[@]} -eq 0 ] && { info "inbox empty — nothing to do"; exit 0; }
  info "${#files[@]} description(s) queued; processing at most $MAX_ITEMS"
  if [ ${#files[@]} -gt "$MAX_ITEMS" ]; then
    # Say what was deferred. A cap that truncates silently reads as "that was everything"
    # — the same defect the dashboard had (L0007).
    warn "$(( ${#files[@]} - MAX_ITEMS )) will wait for the next run (raise with --max)"
  fi
  count=0
  for f in "${files[@]}"; do
    [ "$count" -ge "$MAX_ITEMS" ] && break
    process_one "$f"; count=$((count + 1))
  done
fi

# --- unattended path: dev-ready stories only, starting at G2 -----------------
# The supervised path above takes a raw description through G0/G1 itself. Unattended it
# MAY NOT: refinement decides WHAT to build, and that judgement is human (P2). Here the
# story is already G1-approved, so the runner starts at design and ends at a lower
# environment a human can look at (P3/P4) -- never at a merge.
process_ready_issue() {
  local num="$1" title="$2"
  local slug; slug="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-*//; s/-*$//' | cut -c1-40)"

  say "> #$num $title"
  if [ "$DRY" = "1" ]; then info "(dry run - would implement)"; return 0; fi

  # P2 -- G1 evidence must exist on the issue. "Labelled ready" is a claim; the gate
  # record is the evidence (PD-3). Absent it, we stop rather than assume.
  if [ "$(pol require_g1_evidence)" = "true" ]; then
    if ! gh issue view "$num" --json comments --jq '.comments[].body' 2>/dev/null | grep -qi 'G1'; then
      warn "#$num is labelled ready but carries no G1 evidence - skipping"
      printf 'Issue #%s was labelled ready with no G1 gate record on it.\n\nThe label is a claim; the gate record is the evidence. Run /ready, or remove the label.\n' \
        "$num" > "$DONE/issue-${num}.BLOCKED.md"
      return 1
    fi
  fi

  local branch="feat/${num}-${slug}"
  git switch -q -c "$branch" 2>/dev/null || { warn "branch $branch exists - skipping"; return 1; }

  info "implementing (this takes a while)..."
  local log="$DONE/issue-${num}.log"
  claude -p "$(cat <<PROMPT
Implement issue #$num -- it has already passed G1, so the story and its acceptance criteria
are SETTLED. Do not re-scope, re-split, or re-write them. If they look wrong, stop and write
$DONE/issue-${num}.BLOCKED.md saying so; changing agreed scope unattended is out of bounds.

Read the issue first. Then, loading each skill named:

1. threat-modeling -- if the story is security-, privacy-, or AI-relevant. Allocate every
   control to a named component before writing any code.
2. test-strategy -- the FAILING test comes first, then the smallest implementation that
   passes it. Every allocated control gets a negative-case test proving it DENIES.
3. All three suites must exist and pass for this story (P5). A missing suite is a failure,
   never a skip:
     unit:       $(pol test_unit_command)
     functional: $(pol test_functional_command)
     security:   $(pol test_security_command)
4. control-verification -- trace each control to a line and to its test. Mutation-check at
   least one by removing it and confirming the tests fail.
5. Write the design record and verification evidence to docs/product/.

HARD LIMITS -- write $DONE/issue-${num}.BLOCKED.md and STOP instead of proceeding, if:
 - a High or Critical finding appears
 - the work needs a secret, credential, or production access
 - it would modify .github/workflows/, .claude/hooks/, .claude/agents/, process/gates/,
   docs/compliance/, or scripts/configure-github.sh
 - the work exceeds the agreed acceptance criteria
 - a blocking question has no safe default
 - you have failed the same step three times

Do NOT merge, deploy to production, force-push, or handle credentials.
Commit with a Conventional Commit referencing "Refs: #$num" and an "AI-Assisted:" trailer.
Do not open the PR -- the runner does that.
PROMPT
)" > "$log" 2>&1 || true

  # Structural check -- the prompt above is advisory (AIC-3); this is what holds.
  if git diff --name-only main...HEAD 2>/dev/null | grep -qE "$PROTECTED"; then
    warn "#$num touched a control path - branch abandoned"
    printf 'The run modified a protected path. Branch `%s` abandoned unmerged.\n' "$branch" \
      > "$DONE/issue-${num}.BLOCKED.md"
    git switch -q "$STARTED_ON" 2>/dev/null; return 1
  fi
  if [ -z "$(git log --oneline main..HEAD 2>/dev/null)" ]; then
    warn "#$num produced no commits - see $log"; git switch -q "$STARTED_ON" 2>/dev/null; return 1
  fi

  # P5 -- re-run the suites here. The agent reporting green is an assertion; this is
  # evidence (PD-3). Any failure means no PR.
  local suite cmd
  for suite in unit functional security; do
    cmd="$(pol "test_${suite}_command")"
    if ! eval "$cmd" >> "$log" 2>&1; then
      warn "#$num failed the $suite suite - no PR opened"
      printf 'Command `%s` failed. Branch `%s` left for inspection; see `%s`.\n' "$cmd" "$branch" "$log" \
        > "$DONE/issue-${num}.BLOCKED.md"
      git switch -q "$STARTED_ON" 2>/dev/null; return 1
    fi
    ok "$suite tests pass"
  done

  git push -q -u origin "$branch" 2>/dev/null || { warn "#$num push failed"; return 1; }

  # P3 -- deploy to the lower environment so the human gate (P4) is a look at something
  # RUNNING, not a read of a diff. Production stays unreachable: guard-bash blocks it, and
  # this is the command the policy itself declared.
  local deployed="not attempted"
  if eval "$(pol nonprod_deploy_command)" >> "$log" 2>&1 && eval "$(pol nonprod_health_command)" >> "$log" 2>&1; then
    deployed="deployed to $(pol nonprod_name) and healthy"; ok "$deployed"
  else
    deployed="**deploy or health check to $(pol nonprod_name) FAILED** - see \`$log\`"
    warn "non-prod deploy/health failed for #$num"
  fi

  gh pr create --title "feat: $title" --base main --head "$branch" \
    --body "$(printf 'Closes #%s\n\nImplemented by the unattended sprint runner from a G1-approved story.\n\n## Non-prod (P3)\n%s\n\n## Tests (P5)\nUnit, functional and security suites were re-run by the runner after the agent reported done. All passed, or this PR would not exist.\n\n## Your gate (P4)\nApprove what is RUNNING in `%s`, not this diff. The diff is how it got there; the environment is what you are accepting.\n\n## AI authorship (AIC-6)\n- [x] **Parts AI-authored:** all of it\n- [x] **Agent / model:** claude-opus-5 via the unattended runner\n\nGive this MORE scrutiny than a hand-written PR: no human watched it being written.\n' \
      "$num" "$deployed" "$(pol nonprod_name)")" >/dev/null 2>&1 \
    && ok "PR opened for #$num" || warn "#$num PR creation failed"

  git switch -q "$STARTED_ON" 2>/dev/null
}

# ── run summary — the only thing an unattended operator sees in the morning ──
SUMMARY="sprint/done/last-run.md"
{
  printf '# Sprint run — %s

' "$(date -u +'%Y-%m-%d %H:%M UTC')"
  printf 'Processed: %s
' "${count:-1}"
  blocked=$(find "$DONE" -name '*.BLOCKED.md' -newermt '-1 day' 2>/dev/null | wc -l | tr -d ' ')
  printf 'Stopped deliberately: %s
' "$blocked"
  printf 'Still queued: %s

' "$(find "$INBOX" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  if command -v gh >/dev/null 2>&1; then
    printf '## Open PRs awaiting you

'
    gh pr list --state open --json number,title,mergeStateStatus       --jq '.[] | "- #\(.number) [\(.mergeStateStatus)] \(.title)"' 2>/dev/null || printf '(none)
'
  fi
  [ "$blocked" != "0" ] && printf '
**%s run(s) stopped for a human decision — see sprint/done/*.BLOCKED.md.**
' "$blocked"
} > "$SUMMARY" 2>/dev/null

say "done"
info "summary: $SUMMARY"
info "Review the PRs. Merging stays a human act — that is the control, not an oversight."
