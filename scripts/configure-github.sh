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

DRY=0; YES=0; MODE="team"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --yes|-y)  YES=1; shift ;;
    --solo)    MODE="solo"; shift ;;
    --team)    MODE="team"; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

# Required approving reviews. GitHub forbids approving your own PR, so with 1 required a
# solo operator can never merge anything. Solo mode drops the COUNT and nothing else —
# see docs/13-solo-operation.md and POAM-008.
if [ "$MODE" = "solo" ]; then REVIEW_COUNT=0; else REVIEW_COUNT=1; fi

say()  { printf '\n\033[1m%s\033[0m\n' "$1"; }
info() { printf '  %s\n' "$1"; }
warn() { printf '  [warn] %s\n' "$1"; }
died=0
bad()  { printf '  [FAIL] %s\n' "$1"; died=1; }

command -v gh >/dev/null || { echo "gh CLI not found." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh not authenticated. Run: gh auth login" >&2; exit 1; }

PYBIN="$(command -v python3 || command -v python || echo python)"

REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || {
  echo "No GitHub remote. Create one first:" >&2
  echo "  gh repo create <name> --private --source=. --push" >&2
  exit 1
}
# DEFECT FIXED 2026-08-07: this used `git symbolic-ref --short HEAD`, i.e. whatever branch
# you happen to be standing on. Run from a feature branch, it protected the FEATURE branch
# and silently left the default branch alone — the exact inverse of the intent, reported as
# success. Always ask the API for the repository's default branch.
BRANCH="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || echo main)"
CURRENT="$(git symbolic-ref --short HEAD 2>/dev/null || echo '')"
if [ -n "$CURRENT" ] && [ "$CURRENT" != "$BRANCH" ]; then
  printf '  (on branch %s; configuring the default branch %s)\n' "$CURRENT" "$BRANCH"
fi
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
say "4. Branch protection on '$BRANCH'  [mode: $MODE]"
info "CODEOWNER routing, stale dismissal, signed commits, linear history,"
info "no force-push, NO ADMIN BYPASS."
if [ "$MODE" = "solo" ]; then
  info ""
  info "SOLO MODE: required_approving_review_count = 0"
  info "           require_code_owner_reviews      = false"
  info "           require_last_push_approval      = false"
  info ""
  info "  Three SETTINGS, one CONTROL: independent human approval. GitHub forbids"
  info "  approving your own PR, and code-owner review is required regardless of the"
  info "  count — so with a single owner all three are structurally impossible, not"
  info "  merely inconvenient. Leaving any of them on means nothing can ever merge."
  info ""
  info "  CODEOWNERS still routes and auto-requests review; it is no longer blocking."
  info "  enforce_admins stays TRUE — letting the admin bypass would remove every"
  info "  protection at once, not just this one."
  info ""
  info "  Compensating controls (docs/13-solo-operation.md, POAM-008):"
  info "    - /self-review artifact REQUIRED by pr-governance.yml"
  info "    - cooling-off: do not merge the session you opened it"
  info "    - all status checks required"
  info "    - quarterly external review of a random sample"
fi
info ""
info "Status checks are added in step 5, after they have run at least once."
confirm

# DEFECT FIXED 2026-08-08: this always sent `required_status_checks: null`, so every re-run
# of the script WIPED the registered checks — the branch went from 10 required checks to 0
# while reporting success. A setup script that silently destroys its own controls on a second
# run is worse than one that fails loudly. Caught by the dashboard reading the live API,
# not by the script's own verification, which never checked this field.
#
# Preserve whatever is already configured; step 5 then adds any missing contexts.
EXISTING_CHECKS="$(gh api "repos/$REPO/branches/$BRANCH/protection" \
  --jq 'if .required_status_checks then {strict: .required_status_checks.strict, contexts: .required_status_checks.contexts} else null end' \
  2>/dev/null || echo null)"
[ -z "$EXISTING_CHECKS" ] && EXISTING_CHECKS=null

PROT_JSON=$(cat <<JSON
{
  "required_status_checks": $EXISTING_CHECKS,
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": $([ "$MODE" = solo ] && echo false || echo true),
    "required_approving_review_count": $REVIEW_COUNT,
    "require_last_push_approval": $([ "$MODE" = solo ] && echo false || echo true)
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

# ── Signed commits: verify the CAPABILITY before enabling the CONTROL ────────
# DEFECT FIXED 2026-08-08 (L0010): this enabled required_signatures unconditionally. If the
# operator has no signing key configured — the default — every subsequent commit is unsigned
# and every PR is permanently unmergeable, with a `BLOCKED` status that names no reason.
# It cost a long diagnosis on the very first PR.
#
# Never enable a control the operator cannot yet satisfy. Check first, and if the capability
# is missing, say exactly how to get it rather than enabling a trap.
say "4b. Signed commits (SI-7, CM-14)"
SIGN_FMT="$(git config --get gpg.format || echo gpg)"
SIGN_KEY="$(git config --get user.signingkey || echo '')"
SIGN_ON="$(git config --get commit.gpgsign || echo false)"
CAN_SIGN=0

if [ -n "$SIGN_KEY" ] && [ "$SIGN_ON" = "true" ]; then
  # Prove it: sign a throwaway object rather than trusting the config.
  if git commit-tree -S -m probe "$(git rev-parse HEAD^{tree})" >/dev/null 2>&1; then
    # DEFECT FIXED 2026-08-08: this asked `gh api user/ssh_signing_keys` — i.e. "can I LIST
    # signing keys", which needs the admin:ssh_signing_key scope. A correctly registered key
    # therefore reported as MISSING whenever that scope was absent, conflating "I lack a
    # read scope" with "the control is unsatisfiable". Same false-negative family as L0007.
    #
    # The authoritative test is the one that matters end to end: does GitHub actually mark
    # a real signed commit as verified? That needs only `repo`, and it tests the capability
    # rather than a proxy for it.
    VERIFIED=""
    for ref in "$(git rev-parse HEAD)" "$BRANCH"; do
      [ -n "$ref" ] || continue
      VERIFIED="$(gh api "repos/$REPO/commits/$ref" --jq '.commit.verification.verified' 2>/dev/null || echo '')"
      [ "$VERIFIED" = "true" ] && break
    done

    if [ "$VERIFIED" = "true" ]; then
      CAN_SIGN=1
      info "signing works locally AND GitHub verifies a real commit (end-to-end)"
    elif gh api "user/$([ "$SIGN_FMT" = "ssh" ] && echo ssh_signing_keys || echo gpg_keys)" >/dev/null 2>&1; then
      # Fallback when the scope IS present but no signed commit exists yet to check.
      CAN_SIGN=1
      info "signing works locally and the registered key list is readable"
    else
      warn "signing works locally, but no commit is verified by GitHub yet."
      warn "  Either the key is not registered, or no signed commit has been pushed."
      warn "  Register the PUBLIC key (no CLI scope needed): https://github.com/settings/ssh/new"
      warn "    -> set 'Key type' to Signing Key, paste ${SIGN_KEY}"
      warn "  Then push one signed commit and re-run this script."
    fi
  else
    warn "user.signingkey is set but signing FAILED. Not enabling required signatures."
  fi
else
  warn "No commit signing configured. NOT enabling required_signatures —"
  warn "doing so would make every PR permanently unmergeable (L0010)."
  warn ""
  warn "  To enable it (SSH signing, no GPG needed):"
  warn "    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_signing -N \"\""
  warn "    gh auth refresh -h github.com -s admin:ssh_signing_key"
  warn "    gh ssh-key add ~/.ssh/id_ed25519_signing.pub --type signing --title 'git signing'"
  warn "    git config gpg.format ssh"
  warn "    git config user.signingkey ~/.ssh/id_ed25519_signing.pub"
  warn "    git config commit.gpgsign true"
  warn "  Then re-run this script. Until then SI-7/CM-14 are NOT satisfied — POA&M it."
fi

if [ "$CAN_SIGN" = "1" ]; then
  run "signed commits required (SI-7, CM-14)" \
    gh api -X POST "repos/$REPO/branches/$BRANCH/protection/required_signatures"
else
  # Actively REMOVE it if a previous run turned it on without the capability.
  gh api -X DELETE "repos/$REPO/branches/$BRANCH/protection/required_signatures" >/dev/null 2>&1 \
    && warn "required_signatures disabled — capability missing (record as a finding)"
fi

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
  # NOTE: matrix jobs report with the matrix value appended. A required context that omits
  # it can NEVER be satisfied and blocks every PR forever (L0010). Keep this in sync with
  # the language matrix in security.yml — and if you change the matrix, change this.
  "SAST — CodeQL (SA-11(1)) (javascript-typescript)"
)
if [ "$DRY" = "1" ]; then
  info "would require ${#CHECKS[@]} status checks"
else
  ctx=$(printf '"%s",' "${CHECKS[@]}"); ctx="[${ctx%,}]"
  # PATCH on the sub-resource 404s when required_status_checks has never been set — the
  # parent object does not exist yet, which is the normal state on a fresh repo. Try the
  # PATCH, then fall back to a full protection PUT that includes the checks.
  if gh api -X PATCH "repos/$REPO/branches/$BRANCH/protection/required_status_checks" \
       -H "Accept: application/vnd.github+json" \
       --input - <<< "{\"strict\":true,\"contexts\":$ctx}" >/dev/null 2>&1; then
    info "${#CHECKS[@]} required status checks configured"
  elif printf '%s' "$PROT_JSON" \
       | sed "s|\"required_status_checks\": null|\"required_status_checks\": {\"strict\":true,\"contexts\":$ctx}|" \
       | gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" \
           -H "Accept: application/vnd.github+json" --input - >/dev/null 2>&1; then
    info "${#CHECKS[@]} required status checks configured (via full protection PUT)"
  else
    warn "could not set status checks — a check must have reported at least once."
    warn "Open a PR, let CI run, then re-run this script. CIS 1.1.7 is NOT satisfied."
  fi
fi

# ── 6. Verify (CA-2: test beats examine) ─────────────────────────────────────
#
# DEFECT FIXED 2026-08-07 (L0007, third recurrence): the previous implementation had a
# leftover no-op `gh api /dev/null` call and an eval-based JSON walk that returned null
# for every field. It reported FIVE FALSE FAILURES against controls that were correctly
# applied — which is worse than not verifying at all, because the operator's rational
# response is to distrust the verifier and then ignore it.
#
# Now: one API call, jq paths, no eval.
say "6. Verification"
info "A control you have not seen block anything is a control you are assuming."

P="$(gh api "repos/$REPO/branches/$BRANCH/protection" 2>/dev/null || echo '{}')"
if [ "$P" = "{}" ] || printf '%s' "$P" | grep -q '"message"'; then
  bad "branch protection is not readable — treat every item below as NOT configured"
else
  chk() { # jq-path expected label
    local got
    got="$(printf '%s' "$P" | jq -r "$1 // \"absent\"" 2>/dev/null \
        || printf '%s' "$P" | python -c "
import sys,json
d=json.load(sys.stdin)
cur=d
for k in '''$1'''.strip('.').split('.'):
    cur = (cur or {}).get(k)
print(str(cur).lower() if cur is not None else 'absent')" 2>/dev/null)"
    got="$(printf '%s' "$got" | tr '[:upper:]' '[:lower:]')"
    if [ "$got" = "$2" ]; then info "[ok]   $3"; else bad "$3 (got: $got)"; fi
  }
  chk '.enforce_admins.enabled'                                     true  "no admin bypass"
  chk '.required_pull_request_reviews.required_approving_review_count' "$REVIEW_COUNT" "approving reviews = $REVIEW_COUNT ($MODE mode)"
  if [ "$MODE" = "team" ]; then
    chk '.required_pull_request_reviews.require_code_owner_reviews' true  "CODEOWNER review required"
  else
    chk '.required_pull_request_reviews.require_code_owner_reviews' false "CODEOWNER review advisory (solo — routes, does not block)"
  fi
  chk '.required_pull_request_reviews.dismiss_stale_reviews'        true  "stale approvals dismissed"
  chk '.allow_force_pushes.enabled'                                 false "force push blocked"
  chk '.allow_deletions.enabled'                                    false "branch deletion blocked"
  chk '.required_linear_history.enabled'                            true  "linear history"
  chk '.required_conversation_resolution.enabled'                   true  "conversations resolved"
  # Verify the field this script previously wiped on every re-run. A verification step that
  # does not check what the script writes is not verification.
  #
  # jq is NOT assumed — it is absent on stock Git-for-Windows, and the first version of this
  # line used it unconditionally and reported a FALSE FAILURE against 11 healthy checks.
  # Third recurrence of L0007 in this script. Same python fallback the guards use.
  N_NOW="$(printf '%s' "$P" | { jq -r '(.required_status_checks.contexts // []) | length' 2>/dev/null \
        || "$PYBIN" -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(len((d.get('required_status_checks') or {}).get('contexts') or []))
except Exception:
    print(0)" 2>/dev/null; })"
  if [ "${N_NOW:-0}" -gt 0 ]; then
    info "[ok]   ${N_NOW} required status checks"
  else
    bad "NO required status checks — CIS 1.1.7 unsatisfied; merges are not gated on CI"
  fi
  # Conditional on the capability probe in step 4b. Reporting FAIL here when signing was
  # deliberately not enabled — because the operator has no key — is a false failure, and a
  # verifier that cries wolf gets ignored (L0007). Report the honest state instead.
  if [ "$CAN_SIGN" = "1" ]; then
    chk '.required_signatures.enabled'                              true  "signed commits (SI-7, CM-14)"
  else
    chk '.required_signatures.enabled'                              false "signed commits NOT required — no signing capability (SI-7 unsatisfied, see POA&M)"
  fi
fi

# Plan-dependent features. Report their absence as a FINDING, not a failure of this run —
# they are a licensing constraint, and the honest response is a POA&M entry, not a retry.
SEC="$(gh api "repos/$REPO" --jq '.security_and_analysis // "null"' 2>/dev/null || echo null)"
if [ "$SEC" = "null" ]; then
  warn "Secret scanning / push protection unavailable on this plan+visibility."
  warn "  -> pre-commit + CI gitleaks still run. Record the gap: POA&M, control IA-5."
fi

# ── 7. CIS Software Supply Chain checks ─────────────────────────────────────
# Settings CIS names explicitly that are not covered by branch protection.
# Mapped in docs/compliance/cis-supply-chain-map.md.
say "7. CIS Software Supply Chain v1.0"

# 1.2.5 / 1.2.6 — security policy, description, discoverability
[ -f SECURITY.md ]  && info "[ok]   1.2.5 SECURITY.md present"  || bad "1.2.5 SECURITY.md missing"
[ -f LICENSE ]      && info "[ok]   ---   LICENSE present"      || bad "LICENSE missing (a public repo without one is all-rights-reserved)"
[ -f CONTRIBUTING.md ] && info "[ok]   ---   CONTRIBUTING.md present" || warn "CONTRIBUTING.md missing"

DESC="$(gh repo view --json description --jq '.description // ""')"
[ -n "$DESC" ] && info "[ok]   1.2.6 repository description set" || bad "1.2.6 no repository description"

# 1.3.2 — MFA. Account-level; report, cannot enforce from a repo.
MFA="$(gh api user --jq '.two_factor_authentication // "unknown"' 2>/dev/null || echo unknown)"
case "$MFA" in
  true)  info "[ok]   1.3.2 MFA enabled on the account" ;;
  false) bad  "1.3.2 MFA is NOT enabled — enable it; it protects every control here" ;;
  *)     warn "1.3.2 MFA status not readable with the current token scope" ;;
esac

# 1.4.2 — every action pinned to a full commit SHA, and the SHA must RESOLVE.
# A tag is mutable; a compromised action tag compromises every workflow using it. A
# plausible-but-nonexistent SHA is worse — three were found in this repo (AIC-7).
say "   1.4.2 Action pinning"
unpinned=0; unresolved=0
while read -r line; do
  [ -z "$line" ] && continue
  spec="$(printf '%s' "$line" | sed -E 's/.*uses:[[:space:]]*([^[:space:]#]+).*/\1/')"
  ver="$(printf '%s' "$line" | sed -nE 's/.*#[[:space:]]*([^[:space:]]+).*/\1/p')"
  repo="${spec%@*}"; sha="${spec#*@}"
  case "$spec" in ./*) continue ;; esac
  if ! printf '%s' "$sha" | grep -qE '^[0-9a-f]{40}$'; then
    bad "1.4.2 not SHA-pinned: $spec"; unpinned=$((unpinned+1)); continue
  fi
  if [ -n "$ver" ]; then
    base="$(printf '%s' "$repo" | cut -d/ -f1,2)"
    real="$(gh api "repos/$base/commits/$ver" --jq .sha 2>/dev/null || echo '')"
    if [ -n "$real" ] && [ "$real" != "$sha" ]; then
      bad "1.4.2 SHA does not match tag $ver for $repo (have ${sha:0:12}, actual ${real:0:12})"
      unresolved=$((unresolved+1))
    fi
  fi
done < <(grep -rhE '^\s*[-]?\s*uses:' .github/workflows/ 2>/dev/null | grep -v '^\s*#')
[ "$unpinned" = "0" ] && [ "$unresolved" = "0" ] && info "[ok]   1.4.2 all actions SHA-pinned and resolvable"

# 2.2.2 — build worker least privilege
noperm=0
for f in .github/workflows/*.yml; do
  grep -qE '^permissions:' "$f" || { bad "2.2.2 no top-level permissions in $(basename "$f")"; noperm=1; }
done
[ "$noperm" = "0" ] && info "[ok]   2.2.2 all workflows declare least-privilege permissions"

# 1.5.1 — secret scanning + push protection (free on public repos)
if [ "$SEC" = "null" ]; then
  bad "1.5.1 GitHub secret scanning / push protection NOT enabled"
else
  info "[ok]   1.5.1 secret scanning + push protection enabled"
fi

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
