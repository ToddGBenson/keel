#!/usr/bin/env bash
# Configure the GitHub-side controls. This is SETUP.md, automated.
#
#   bash scripts/configure-github.sh              # interactive
#   bash scripts/configure-github.sh --yes        # no prompts
#   bash scripts/configure-github.sh --dry-run    # show what would change
#
# ── WHY THIS SCRIPT EXISTS ───────────────────────────────────────────────────
# Everything in the repo is files. The controls that actually ENFORCE separation of duties
# and release authorization live in GitHub settings, and a repository cannot configure its
# own branch protection. Until this runs, G3 and G5 are documentation.
#
# That gap — a clean-looking governance repo with no enforcement behind it — is the most
# common way one of these programmes produces assurance that is not real.
#
# Requires: gh CLI, authenticated, with admin on the repo.

set -euo pipefail
cd "$(dirname "$0")/.."

DRY=0; YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --yes|-y)  YES=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

say()  { printf '\n\033[1m%s\033[0m\n' "$1"; }
info() { printf '  %s\n' "$1"; }
warn() { printf '  [warn] %s\n' "$1"; }
died=0
bad()  { printf '  [FAIL] %s\n' "$1"; died=1; }

command -v gh >/dev/null || { echo "gh CLI not found." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh not authenticated. Run: gh auth login" >&2; exit 1; }

REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || {
  echo "No GitHub remote. Create one first:" >&2
  echo "  gh repo create <name> --private --source=. --push" >&2
  exit 1
}
BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo main)"
say "Repository: $REPO   default branch: $BRANCH"

run() { # description, gh args...
  local desc="$1"; shift
  if [ "$DRY" = "1" ]; then info "would: $desc"; return 0; fi
  if "$@" >/dev/null 2>&1; then info "$desc"; else bad "$desc"; fi
}

confirm() {
  [ "$YES" = "1" ] && return 0
  read -r -p "  Proceed? [y/N] " r || true
  case "$r" in y|Y|yes) return 0 ;; *) echo "  aborted"; exit 1 ;; esac
}

# ── 1. Repository security features ──────────────────────────────────────────
say "1. Repository security features"
info "Enabling: secret scanning, PUSH PROTECTION, dependency graph, Dependabot"
confirm
run "secret scanning + push protection + Dependabot" \
  gh api -X PATCH "repos/$REPO" \
    -f security_and_analysis[secret_scanning][status]=enabled \
    -f security_and_analysis[secret_scanning_push_protection][status]=enabled \
    -f security_and_analysis[dependabot_security_updates][status]=enabled
run "vulnerability alerts" gh api -X PUT "repos/$REPO/vulnerability-alerts"
run "automated security fixes" gh api -X PUT "repos/$REPO/automated-security-fixes"

# Push protection is the cheapest control here and stops the failure that is most
# expensive to unwind: a credential in history requires rotation, not deletion.

# ── 2. Actions permissions (AC-6, AC-5) ──────────────────────────────────────
say "2. Actions permissions"
run "workflows default to read-only (elevate per job)" \
  gh api -X PUT "repos/$REPO/actions/permissions/workflow" \
    -f default_workflow_permissions=read \
    -F can_approve_pull_request_reviews=false
info "can_approve_pull_request_reviews=false — an Actions-approved PR would defeat AC-5"

# ── 3. Environments — this IS gate G5 ────────────────────────────────────────
say "3. Environments (G5 human authorization)"
REVIEWER_ID="$(gh api user --jq .id 2>/dev/null || echo '')"
if [ "$DRY" = "1" ]; then
  info "would create 'staging' (no reviewers) and 'production' (required reviewer: you)"
else
  gh api -X PUT "repos/$REPO/environments/staging" >/dev/null 2>&1 \
    && info "staging environment created" || bad "staging environment"

  if [ -n "$REVIEWER_ID" ]; then
    # The deploy job physically cannot start until a human approves in the GitHub UI.
    # That approval record — identity and timestamp — IS the CM-3 evidence.
    if gh api -X PUT "repos/$REPO/environments/production" \
         -F "reviewers[][type]=User" -F "reviewers[][id]=$REVIEWER_ID" \
         -F "deployment_branch_policy[protected_branches]=true" \
         -F "deployment_branch_policy[custom_branch_policies]=false" >/dev/null 2>&1; then
      info "production environment created with YOU as required reviewer"
    else
      bad "production environment (required reviewers may need a paid plan on private repos)"
      warn "Without required reviewers, G5 is NOT enforced. Verify in Settings > Environments."
    fi
  else
    bad "could not resolve your user id; create the production environment manually"
  fi
fi

# ── 4. Branch protection (AC-5, CM-5, SI-7) ──────────────────────────────────
say "4. Branch protection on '$BRANCH'"
info "Required review from a CODEOWNER, stale dismissal, signed commits,"
info "linear history, no force-push, NO ADMIN BYPASS."
info ""
info "Status checks are added in step 5, after they have run at least once."
confirm

PROT_JSON=$(cat <<'JSON'
{
  "required_status_checks": null,
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 1,
    "require_last_push_approval": true
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true,
  "block_creations": false,
  "lock_branch": false,
  "allow_fork_syncing": false
}
JSON
)

if [ "$DRY" = "1" ]; then
  info "would apply branch protection (enforce_admins=true)"
else
  if printf '%s' "$PROT_JSON" | gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" \
       -H "Accept: application/vnd.github+json" --input - >/dev/null 2>&1; then
    info "branch protection applied"
  else
    bad "branch protection"
    warn "Private repos on the Free plan cannot use branch protection."
    warn "Either make the repo public, upgrade, or use a ruleset. Until then AC-5/CM-5"
    warn "are NOT enforced — record that honestly in the SSP rather than assuming."
  fi
fi

run "signed commits required (SI-7, CM-14)" \
  gh api -X POST "repos/$REPO/branches/$BRANCH/protection/required_signatures"

# ── 5. Required status checks ────────────────────────────────────────────────
say "5. Required status checks"
CHECKS=(
  "Process compliance"
  "Platform integrity (AIC-3, AIC-8, AU-9)"
  "Dependency review (SR-3, SR-4, AIC-7)"
  "Build" "Lint & static typing" "Test & coverage"
  "SAST — CodeQL (SA-11(1))"
  "Secret scanning (IA-5)"
  "SCA — dependency vulnerabilities (RA-5, SR-3)"
  "IaC & configuration (CM-6, CM-7)"
  "Suppression audit"
)
if [ "$DRY" = "1" ]; then
  info "would require ${#CHECKS[@]} status checks"
else
  ctx=$(printf '"%s",' "${CHECKS[@]}"); ctx="[${ctx%,}]"
  if gh api -X PATCH "repos/$REPO/branches/$BRANCH/protection/required_status_checks" \
       -H "Accept: application/vnd.github+json" \
       --input - <<< "{\"strict\":true,\"contexts\":$ctx}" >/dev/null 2>&1; then
    info "${#CHECKS[@]} required status checks configured"
  else
    warn "could not set status checks — they must run at least once first."
    warn "Open a PR, let CI run, then re-run this script."
  fi
fi

# ── 6. Verify (CA-2: test beats examine) ─────────────────────────────────────
say "6. Verification"
info "A control you have not seen block anything is a control you are assuming."
P="$(gh api "repos/$REPO/branches/$BRANCH/protection" 2>/dev/null || echo '{}')"
chk() { # jq path, expected, label
  local got; got="$(printf '%s' "$P" | gh api --method GET /dev/null 2>/dev/null || true)"
  got="$(printf '%s' "$P" | python -c "import sys,json;d=json.load(sys.stdin);print(json.dumps(eval('d$1',{'d':d}) if True else None))" 2>/dev/null || echo null)"
  if [ "$got" = "$2" ]; then info "[ok]   $3"; else bad "$3 (got: $got)"; fi
}
chk "['enforce_admins']['enabled']"                                   "true"  "no admin bypass"
chk "['required_pull_request_reviews']['require_code_owner_reviews']" "true"  "CODEOWNER review required"
chk "['required_pull_request_reviews']['dismiss_stale_reviews']"      "true"  "stale approvals dismissed"
chk "['allow_force_pushes']['enabled']"                               "false" "force push blocked"
chk "['required_linear_history']['enabled']"                          "true"  "linear history"

say "Summary"
if [ "$died" = "0" ]; then
  cat <<'EOF'
  All GitHub-side controls configured and verified.

  Manual residue (the API cannot do these):
    - Confirm 'production' shows required reviewers in Settings > Environments
    - Add teams to .github/CODEOWNERS if you use them
    - Enable CodeQL default setup if you are not using the advanced workflow

  Then prove it end to end — open a PR with no linked issue and confirm
  'Process compliance' fails. That is your first control assessment.
EOF
else
  cat <<'EOF'
  Some controls did NOT apply. Do not treat them as configured.

  The usual cause is plan limits: branch protection and environment reviewers
  require a paid plan on private repositories.

  Record what is not enforced in docs/compliance/ssp-outline.md and open a
  POA&M entry. A documented weak control is defensible; an assumed one is not.
EOF
  exit 1
fi
