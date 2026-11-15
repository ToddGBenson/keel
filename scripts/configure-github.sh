#!/usr/bin/env bash
# Configure the GitHub-side controls. This is SETUP.md, automated.
#
#   bash scripts/configure-github.sh              # interactive
#   bash scripts/configure-github.sh --yes        # no prompts
#   bash scripts/configure-github.sh --dry-run    # show what would change
#   bash scripts/configure-github.sh --review-app-id <id|none>   # another App, or no gate
#   bash scripts/configure-github.sh --checks-only  # the merge gate only; nothing else changes
#
# ── THE MERGE GATE (TheHub #60978) ───────────────────────────────────────────
# The required check is `independent-review`, posted on each pull request head by the
# MyKronos GitHub App, and PINNED to that App's id. MyKronos opens the approval request
# for a PR head itself, but only on a repository whose default branch already requires
# the check, so declaring it here is what switches it on. The App id is the documented
# MyKronos App (REVIEW_APP_ID_DEFAULT below), or --review-app-id / KEEL_REVIEW_APP_ID.
# `none` (a fork with no MyKronos) requires nothing and the script says so. The check is
# required only once that App has been seen posting a check run on this repository: an
# App that cannot post here would block every pull request (L0010).
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

DRY=0; YES=0; MODE="team"; CHECKS_ONLY=0
# The MyKronos GitHub App (`mykronos-platform`): the app.id on every check run it posts
# here, e.g. library-allowlist. Documented in ci/README.md and SETUP.md section 2.
REVIEW_APP_ID_DEFAULT=4551328
REVIEW_APP_ID="${KEEL_REVIEW_APP_ID:-$REVIEW_APP_ID_DEFAULT}"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --yes|-y)  YES=1; shift ;;
    --solo)    MODE="solo"; shift ;;
    --team)    MODE="team"; shift ;;
    --checks-only) CHECKS_ONLY=1; shift ;;
    --review-app-id) [ $# -ge 2 ] || { echo "--review-app-id needs a value" >&2; exit 1; }
               REVIEW_APP_ID="$2"; shift 2 ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

[ "$REVIEW_APP_ID" = "none" ] && REVIEW_APP_ID=""
case "$REVIEW_APP_ID" in
  ''|*[!0-9]*) [ -z "$REVIEW_APP_ID" ] || { echo "--review-app-id must be a number or none: $REVIEW_APP_ID" >&2; exit 1; } ;;
esac

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

# ── Required-check helpers (TheHub #60978) ──────────────────────────────────
# python, not jq: jq is absent on stock Git-for-Windows (step 6, L0007).

# The current required checks as {"strict", "checks": [{context, app_id}]}, or null.
# Only a successful read counts: `gh api` prints the error body on a 404, and an
# error body pasted into the PUT payload is not "no checks".
existing_checks() {
  local raw
  raw="$(gh api "repos/$REPO/branches/$BRANCH/protection" 2>/dev/null)" || { echo null; return 0; }
  printf '%s' "$raw" | "$PYBIN" -c '
import json, sys
try:
    r = json.load(sys.stdin).get("required_status_checks")
except Exception:
    r = None
if not r:
    print("null")
    sys.exit(0)
checks = r.get("checks")
if checks is None:
    checks = [{"context": c} for c in r.get("contexts") or []]
out = []
for c in checks:
    item = {"context": c["context"]}
    if c.get("app_id") not in (None, -1):
        item["app_id"] = c["app_id"]
    out.append(item)
print(json.dumps({"strict": bool(r.get("strict")), "checks": out}))' 2>/dev/null || echo null
}

# Existing checks (stdin) plus REVIEW_CHECK pinned to $1. Every other check is kept;
# an existing REVIEW_CHECK, pinned elsewhere or to no app, is replaced, not duplicated.
# strict is OFF: "branch must be up to date" moves a PR head every time main moves, and
# an approval pins the head sha, so every merge would orphan every other approval.
with_review_check() {
  "$PYBIN" -c '
import json, sys
name, app = sys.argv[1], int(sys.argv[2])
try:
    cur = json.loads(sys.stdin.read() or "null") or {}
except Exception:
    cur = {}
checks = [c for c in cur.get("checks") or [] if c.get("context") != name]
checks.append({"context": name, "app_id": app})
print(json.dumps({"strict": False, "checks": checks}))' "$REVIEW_CHECK" "$1"
}

# The slug of App $1 if it has posted a check run on this repository: on the default
# branch head, or on the head of one of the newest open pull requests. Empty if not.
# Posting here proves the App is installed and MyKronos can reach the repository.
review_app_slug() {
  local runs heads h
  runs="$(gh api "repos/$REPO/commits/$BRANCH/check-runs?per_page=100" 2>/dev/null || true)"
  heads="$(gh api "repos/$REPO/pulls?state=open&per_page=5" 2>/dev/null | "$PYBIN" -c '
import json, sys
try:
    for p in json.load(sys.stdin):
        print(p["head"]["sha"])
except Exception:
    pass' 2>/dev/null || true)"
  for h in $heads; do
    runs="$runs
$(gh api "repos/$REPO/commits/$h/check-runs?per_page=100" 2>/dev/null || true)"
  done
  printf '%s' "$runs" | "$PYBIN" -c '
import json, sys
app, text = int(sys.argv[1]), sys.stdin.read()
dec, i = json.JSONDecoder(), 0
while i < len(text):
    if text[i].isspace():
        i += 1
        continue
    try:
        doc, i = dec.raw_decode(text, i)
    except ValueError:
        break
    for run in (doc.get("check_runs") if isinstance(doc, dict) else None) or []:
        a = run.get("app") or {}
        if a.get("id") == app:
            print(a.get("slug") or "app-%d" % app)
            sys.exit(0)' "$1" 2>/dev/null || true
}

# Name of the required check, and the GitHub Actions app it must never be pinned to:
# any workflow job can post a check run with any name, so a gate satisfiable by
# github-actions is satisfiable by the author's own workflow.
REVIEW_CHECK="independent-review"
ACTIONS_APP_ID=15368

# The protection read back from the API, re-shaped as a PUT payload with the required
# checks replaced by $1. GET returns `{"enabled": bool}` objects and user/team/app
# objects; PUT takes bools and logins/slugs. Every setting is carried over unchanged, so
# the PUT moves the required checks and nothing else.
put_from_current() {
  local raw
  raw="$(gh api "repos/$REPO/branches/$BRANCH/protection" 2>/dev/null)" || return 1
  printf '%s' "$raw" | "$PYBIN" -c '
import json, sys
g = json.load(sys.stdin)
if not isinstance(g, dict) or "message" in g:
    sys.exit(1)
def on(k):
    v = g.get(k)
    return bool(v.get("enabled")) if isinstance(v, dict) else bool(v)
def who(d):
    if not d:
        return None
    return {"users": [u["login"] for u in d.get("users") or []],
            "teams": [t["slug"] for t in d.get("teams") or []],
            "apps": [a["slug"] for a in d.get("apps") or []]}
out = {"required_status_checks": json.loads(sys.argv[1]),
       "enforce_admins": on("enforce_admins"),
       "restrictions": who(g.get("restrictions"))}
r = g.get("required_pull_request_reviews")
if r:
    rr = {k: r[k] for k in ("dismiss_stale_reviews", "require_code_owner_reviews",
                            "required_approving_review_count", "require_last_push_approval")
          if k in r}
    for k in ("dismissal_restrictions", "bypass_pull_request_allowances"):
        if r.get(k):
            rr[k] = who(r[k])
    out["required_pull_request_reviews"] = rr
else:
    out["required_pull_request_reviews"] = None
for k in ("required_linear_history", "allow_force_pushes", "allow_deletions",
          "required_conversation_resolution", "block_creations", "lock_branch",
          "allow_fork_syncing"):
    if k in g:
        out[k] = on(k)
print(json.dumps(out))' "$1"
}

# PROT_JSON is built in step 4; --checks-only never builds it (and never PUTs it).
PROT_JSON=""

# The gate plan, decided once, before anything is written, so that step 4's payload
# (and a dry run's printout of it) already carries the gate. GATE_PLAN is one of:
#   none     no App id (`--review-app-id none`)
#   actions  the App is github-actions: refused
#   unseen   the App has not posted a check run here: refused (L0010)
#   ok       require $REVIEW_CHECK pinned to $REVIEW_APP_ID
SLUG=""
if [ -z "$REVIEW_APP_ID" ]; then
  GATE_PLAN="none"
elif [ "$REVIEW_APP_ID" = "$ACTIONS_APP_ID" ]; then
  GATE_PLAN="actions"
else
  SLUG="$(review_app_slug "$REVIEW_APP_ID")"
  if [ "$SLUG" = "github-actions" ]; then GATE_PLAN="actions"
  elif [ -z "$SLUG" ]; then GATE_PLAN="unseen"
  else GATE_PLAN="ok"; fi
fi

# --checks-only skips steps 1 to 4b and 7: it changes the merge gate and nothing else.
if [ "$CHECKS_ONLY" = "0" ]; then

# ── 1. Repository security features ──────────────────────────────────────────
say "1. Repository security features"
info "Enabling: secret scanning, PUSH PROTECTION, dependency graph, Dependabot"
confirm
run "secret scanning + push protection + Dependabot" \
  gh api -X PATCH "repos/$REPO" \
    -f 'security_and_analysis[secret_scanning][status]=enabled' \
    -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled' \
    -f 'security_and_analysis[dependabot_security_updates][status]=enabled'
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
  info "would create 'staging' (no reviewers) and 'production' (required reviewer: you; deploys from main and v* tags)"
else
  if gh api -X PUT "repos/$REPO/environments/staging" >/dev/null 2>&1; then
    info "staging environment created"
  else
    bad "staging environment"
  fi

  if [ -n "$REVIEWER_ID" ]; then
    # The deploy job physically cannot start until a human approves in the GitHub UI.
    # That approval record — identity and timestamp — IS the CM-3 evidence.
    #
    # CUSTOM policy, not `protected_branches` (TheHub #60935). release.yml runs
    # against the TAG being released, and an environment limited to protected
    # branches refuses every tag ref -- so with the old setting no release could
    # ever reach this gate. Allowed: `main` and tags matching `v*`. Nothing else.
    if gh api -X PUT "repos/$REPO/environments/production" \
         -F "reviewers[][type]=User" -F "reviewers[][id]=$REVIEWER_ID" \
         -F "deployment_branch_policy[protected_branches]=false" \
         -F "deployment_branch_policy[custom_branch_policies]=true" >/dev/null 2>&1; then
      info "production environment created with YOU as required reviewer"
      # POST is not idempotent: an existing identical policy answers 303/422.
      # So read first, and add only what is missing.
      have="$(gh api "repos/$REPO/environments/production/deployment-branch-policies" \
                --jq '.branch_policies[] | "\(.type):\(.name)"' 2>/dev/null || true)"
      for want in "branch:main" "tag:v*"; do
        if printf '%s\n' "$have" | grep -qxF "$want"; then
          info "production deploy policy present: $want"
        elif gh api -X POST "repos/$REPO/environments/production/deployment-branch-policies" \
               -f "name=${want#*:}" -f "type=${want%%:*}" >/dev/null 2>&1; then
          info "production deploy policy added: $want"
        else
          bad "production deploy policy $want -- release.yml cannot reach G5 without it"
        fi
      done
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
info "Required checks: the existing ones are kept, and $REVIEW_CHECK is added (step 5"
info "says why, if it is not)."
confirm

# DEFECT FIXED 2026-08-08: this always sent `required_status_checks: null`, so every re-run
# of the script WIPED the registered checks — the branch went from 10 required checks to 0
# while reporting success. A setup script that silently destroys its own controls on a second
# run is worse than one that fails loudly. Caught by the dashboard reading the live API,
# not by the script's own verification, which never checked this field.
#
# Preserve whatever is already configured; step 5 then adds any missing check.
#
# DEFECT FIXED 2026-11-04 (TheHub #60978), the same defect in a newer field: this kept
# `.contexts` only. A required check pinned to an App lives in `.checks[].app_id`, and a
# PUT of bare contexts requires the name from ANY app. So every re-run silently unpinned
# independent-review, and a workflow job named independent-review would then satisfy it.
# Keep `checks`, app ids included. Read with python: jq is not assumed (see step 6).
EXISTING_CHECKS="$(existing_checks)"
if [ "$GATE_PLAN" = "ok" ]; then
  EXISTING_CHECKS="$(printf '%s' "$EXISTING_CHECKS" | with_review_check "$REVIEW_APP_ID")"
fi

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
  info "would apply branch protection (enforce_admins=true), PUT with this payload:"
  printf '%s\n' "--- protection payload ---"
  printf '%s' "$PROT_JSON" | "$PYBIN" -c 'import json, sys; print(json.dumps(json.load(sys.stdin), indent=2))' 2>/dev/null \
    || printf '%s\n' "$PROT_JSON"
  printf '%s\n' "--- end payload ---"
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
  if git commit-tree -S -m probe "$(git rev-parse "HEAD^{tree}")" >/dev/null 2>&1; then
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
elif [ "$DRY" = "1" ]; then
  # DEFECT FIXED 2026-11-04 (TheHub #60978): this DELETE ran under --dry-run too, so a
  # "show what would change" run removed required signatures. Found by the test that
  # asserts a dry run writes nothing.
  info "would remove required_signatures if set (capability missing)"
else
  # Actively REMOVE it if a previous run turned it on without the capability.
  gh api -X DELETE "repos/$REPO/branches/$BRANCH/protection/required_signatures" >/dev/null 2>&1 \
    && warn "required_signatures disabled — capability missing (record as a finding)"
fi

fi  # end of: [ "$CHECKS_ONLY" = "0" ] (steps 1 to 4b)

# ── 5. Required status checks: the merge gate (TheHub #60978) ───────────────
#
# ONE required check: `independent-review`, pinned to the MyKronos App (decision
# TheHub #60849 option C, carried out by #60978). MyKronos posts it on each pull request
# head and opens the approval request itself, but only where the default branch already
# requires it, so this step is what switches the gate on.
#
# DEFECT FIXED 2026-11-04 (TheHub #60978): this step required twelve Actions job names
# ("Process compliance", "Build", "SAST — CodeQL (SA-11(1))", ...). Every one comes from a
# workflow reduced to `workflow_dispatch` (pr-governance.yml, ci.yml, security.yml), so
# none ever arrives on a pull request. Run as written, the script blocked every merge;
# not run, nothing gated a merge at all, which is what keel had from 2026-08-13.
# `Concourse / keel` is not required either: it posts on main commits only
# (ci/pipeline.yml), so a pull request never carries it.
say "5. Required status checks (the merge gate)"
RSC_PATH="repos/$REPO/branches/$BRANCH/protection/required_status_checks"
case "$GATE_PLAN" in
  none)
    if [ "$CHECKS_ONLY" = "1" ]; then
      bad "--checks-only with --review-app-id none: there is no merge gate to apply."
    else
      warn "--review-app-id none: $REVIEW_CHECK is not required."
    fi
    warn "  Nothing automated gates a merge. With MyKronos, pass its GitHub App id; the"
    warn "  app.id of any check run it posted here (e.g. library-allowlist) is that id."
    warn "  Existing required checks are left as they are." ;;
  actions)
    bad "App $REVIEW_APP_ID is github-actions: any workflow can post a check named $REVIEW_CHECK. Not required." ;;
  unseen)
    # L0010: never enable a control nothing can satisfy. A required check from an App
    # that cannot post here never arrives, and every pull request blocks.
    bad "App $REVIEW_APP_ID has not posted a check run on $BRANCH or an open PR head here. $REVIEW_CHECK NOT required."
    warn "  Install the App on this repository and onboard it in MyKronos, wait for one of"
    warn "  its checks on a PR, then re-run. Until then nothing automated gates a merge."
    warn "  A fork without MyKronos: --review-app-id none." ;;
  ok)
    if [ "$DRY" = "1" ]; then
      info "would require $REVIEW_CHECK pinned to App $REVIEW_APP_ID ($SLUG), strict off"
    else
      WANT="$(existing_checks | with_review_check "$REVIEW_APP_ID")"
      # PATCH on the sub-resource 404s when required_status_checks has never been set:
      # the parent object does not exist yet (keel's main on 2026-11-04). Then the whole
      # protection is PUT: step 4's payload on a full run, or, under --checks-only, the
      # protection read back from the API with only the required checks replaced.
      if [ -n "$PROT_JSON" ]; then
        FULL="$(printf '%s' "$PROT_JSON" | "$PYBIN" -c '
import json, sys
d = json.load(sys.stdin)
d["required_status_checks"] = json.loads(sys.argv[1])
print(json.dumps(d))' "$WANT" 2>/dev/null || true)"
      else
        FULL="$(put_from_current "$WANT" 2>/dev/null || true)"
      fi
      if printf '%s' "$WANT" | gh api -X PATCH "$RSC_PATH" \
           -H "Accept: application/vnd.github+json" --input - >/dev/null 2>&1; then
        info "$REVIEW_CHECK required, pinned to App $REVIEW_APP_ID ($SLUG)"
      elif [ -n "$FULL" ] && printf '%s' "$FULL" \
           | gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" \
               -H "Accept: application/vnd.github+json" --input - >/dev/null 2>&1; then
        info "$REVIEW_CHECK required, pinned to App $REVIEW_APP_ID ($SLUG) (via full protection PUT)"
      elif [ -z "$FULL" ]; then
        bad "could not read the protection on $BRANCH to add $REVIEW_CHECK to it."
        warn "  An unprotected branch needs the full run: drop --checks-only."
      else
        bad "could not require $REVIEW_CHECK. CIS 1.1.7 is NOT satisfied."
      fi
    fi ;;
esac

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
  # --checks-only changed nothing in steps 1 to 4b, so it verifies none of them.
  if [ "$CHECKS_ONLY" = "0" ]; then
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
  fi
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
  # The merge gate itself (TheHub #60978). Required is not enough: an independent-review
  # that any app may post is satisfied by a workflow job of that name, which the author
  # of the pull request writes. So the verifier checks the PIN, not just the name.
  GATE="$(printf '%s' "$P" | "$PYBIN" -c '
import json, sys
name, want = sys.argv[1], sys.argv[2]
try:
    r = json.load(sys.stdin).get("required_status_checks") or {}
except Exception:
    r = {}
checks = r.get("checks")
if checks is None:
    checks = [{"context": c} for c in r.get("contexts") or []]
apps = [c.get("app_id") for c in checks if c.get("context") == name]
pinned = [a for a in apps if a not in (None, -1)]
if not apps:
    print("absent")
elif want and int(want) in pinned:
    print("ok " + want)
elif want and pinned:
    print("other " + " ".join(str(a) for a in pinned))
elif pinned and len(pinned) == len(apps):
    print("ok " + str(pinned[0]))
else:
    print("unpinned")' "$REVIEW_CHECK" "$REVIEW_APP_ID" 2>/dev/null || echo unreadable)"
  case "$GATE" in
    ok\ *)    info "[ok]   $REVIEW_CHECK required, pinned to App ${GATE#ok }" ;;
    other\ *) bad "$REVIEW_CHECK is pinned to App ${GATE#other }, not $REVIEW_APP_ID" ;;
    unpinned) bad "$REVIEW_CHECK is required from ANY app: a workflow job of that name satisfies it" ;;
    absent)   if [ -n "$REVIEW_APP_ID" ] || [ "$CHECKS_ONLY" = "1" ]; then
                bad "$REVIEW_CHECK is not required: nothing automated gates a merge"
              else
                warn "$REVIEW_CHECK is not required (no --review-app-id): nothing automated gates a merge"
              fi ;;
    *)        bad "could not read the required checks to verify $REVIEW_CHECK" ;;
  esac
  # Conditional on the capability probe in step 4b. Reporting FAIL here when signing was
  # deliberately not enabled — because the operator has no key — is a false failure, and a
  # verifier that cries wolf gets ignored (L0007). Report the honest state instead.
  if [ "$CHECKS_ONLY" = "1" ]; then
    :
  elif [ "$CAN_SIGN" = "1" ]; then
    chk '.required_signatures.enabled'                              true  "signed commits (SI-7, CM-14)"
  else
    chk '.required_signatures.enabled'                              false "signed commits NOT required — no signing capability (SI-7 unsatisfied, see POA&M)"
  fi
fi

if [ "$CHECKS_ONLY" = "1" ]; then
  say "Summary (--checks-only)"
  if [ "$died" = "0" ]; then
    info "The merge gate is configured and verified. Nothing else was changed or checked."
    exit 0
  fi
  info "The merge gate is NOT configured. Do not treat it as one. See the [FAIL] lines."
  exit 1
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
if [ -f SECURITY.md ]; then info "[ok]   1.2.5 SECURITY.md present"; else bad "1.2.5 SECURITY.md missing"; fi
if [ -f LICENSE ]; then info "[ok]   ---   LICENSE present"; else bad "LICENSE missing (a public repo without one is all-rights-reserved)"; fi
if [ -f CONTRIBUTING.md ]; then info "[ok]   ---   CONTRIBUTING.md present"; else warn "CONTRIBUTING.md missing"; fi

DESC="$(gh repo view --json description --jq '.description // ""')"
if [ -n "$DESC" ]; then info "[ok]   1.2.6 repository description set"; else bad "1.2.6 no repository description"; fi

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
