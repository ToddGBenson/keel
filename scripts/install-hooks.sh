#!/usr/bin/env bash
# Install local git pre-commit hooks.
# Controls: IA-5 (secrets), SA-15 (standards), CM-3 (traceability), AU-9 (evidence)
#
# These catch the embarrassing class of problem before it is public and permanent.
# CI re-runs every check server-side, so a local bypass is DETECTED rather than trusted —
# the local hook is a convenience, not the control.
#
# Usage:  bash scripts/install-hooks.sh

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Not a git repository. Run 'git init' first." >&2; exit 1
}
HOOK_DIR="$REPO_ROOT/.git/hooks"
mkdir -p "$HOOK_DIR"

# ── pre-commit ───────────────────────────────────────────────────────────────
cat > "$HOOK_DIR/pre-commit" <<'HOOK'
#!/usr/bin/env bash
set -uo pipefail
fail=0
say() { printf '  %s\n' "$1"; }
bad() { printf '  [FAIL] %s\n' "$1"; fail=1; }
ok()  { printf '  [ok]   %s\n' "$1"; }

staged="$(git diff --cached --name-only --diff-filter=ACM)"
[ -z "$staged" ] && exit 0

echo "pre-commit checks:"

# 1. Secrets — blocking. IA-5.
#
# Patterns are VALUE-SHAPED and SELF-NON-MATCHING. Both properties were learned the hard
# way (see .claude/hooks/guard-write.sh): a bare keyword matches secret-detection code and
# blocks all security tooling work, and a pattern that matches itself blocks its own repair.
# The [x] character classes below match identically but cannot self-trigger. Preserve them.
if command -v gitleaks >/dev/null 2>&1; then
  if gitleaks protect --staged --no-banner --redact >/dev/null 2>&1; then
    ok "no secrets detected"
  else
    bad "gitleaks found a potential secret"
    say "  ROTATE the credential first. Removing the commit is not mitigation."
  fi
else
  added="$(git diff --cached -U0 | grep '^+' || true)"
  if printf '%s' "$added" | grep -qEi \
     '(aws_secret_access_[k]ey|api[_-]?ke[y]|client[_-]?secre[t]|passwor[d])["'"'"' ]*[=:][ "'"'"']*[A-Za-z0-9/+_-]{16,}' \
     || printf '%s' "$added" | grep -qE \
     '(-----BEGIN [A-Z ]*PRIVATE KE[Y]-----|xox[baprs]-[0-9A-Za-z]{10,}-[0-9A-Za-z]{10,}|gh[pousr]_[0-9A-Za-z]{36}|sk-ant-api[0-9]{2}-[0-9A-Za-z_-]{24,}|AKI[A][0-9A-Z]{16})'; then
    bad "apparent credential material in staged changes"
    say "  ROTATE it. A deleted commit is not a rotated credential."
  else
    ok "no obvious secrets (install gitleaks for real coverage)"
  fi
fi

# 2. Large files — blocking.
while IFS= read -r f; do
  [ -f "$f" ] || continue
  size=$(wc -c < "$f" 2>/dev/null || echo 0)
  if [ "$size" -gt 5242880 ]; then
    bad "$f is $((size/1048576))MB — use artifact storage, not git"
  fi
done <<< "$staged"

# 3. Generated evidence must not be hand-edited — AU-9.
if printf '%s' "$staged" | grep -qE '^evidence/.*[.](sarif|xml|json)$'; then
  bad "staged generated evidence (.sarif/.xml/.json under evidence/)"
  say "  Regenerate it instead. A hand-edited scan report is a fabrication."
fi

# 4. Merge conflict markers — blocking.
if git diff --cached -U0 | grep -qE '^[+](<<<<<<<|>>>>>>>|=======$)'; then
  bad "merge conflict markers in staged changes"
fi

# 5. ADAPT placeholders in workflows — warn only.
if printf '%s' "$staged" | grep -q '^[.]github/workflows/'; then
  if git diff --cached -U0 -- .github/workflows/ | grep -q '^[+].*ADAPT:'; then
    say "  [warn] workflow still contains ADAPT: placeholders"
  fi
fi

# ── ADAPT: add your toolchain ──
# Lint / format / static typing on changed files, plus unit tests for changed packages.
# Keep this under ~10 seconds. A slow hook is a hook people start bypassing, and a
# bypassed control is worse than an absent one because it still shows green.
#   e.g.  npx eslint $(printf '%s' "$staged" | grep -E '[.](ts|tsx|js)$') || fail=1
#   e.g.  ruff check $(printf '%s' "$staged" | grep '[.]py$')             || fail=1

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "Commit blocked. These are controls, not suggestions."
  echo "Bypassing the hook is prohibited (AIC-3), and CI re-runs these checks anyway."
  exit 1
fi
exit 0
HOOK

# ── commit-msg ───────────────────────────────────────────────────────────────
cat > "$HOOK_DIR/commit-msg" <<'HOOK'
#!/usr/bin/env bash
set -uo pipefail
msg="$(cat "$1")"
subject="$(printf '%s' "$msg" | head -1)"
fail=0

case "$subject" in Merge*|Revert*|fixup!*|squash!*) exit 0 ;; esac

# Conventional Commits — SA-15.
if ! printf '%s' "$subject" | grep -qE '^(feat|fix|chore|docs|refactor|test|sec|perf|build|ci|revert)([(][a-z0-9._-]+[)])?!?: .+'; then
  echo "[FAIL] Subject is not a Conventional Commit."
  echo "       Expected: <type>(<scope>): <summary>"
  echo "       Types: feat fix chore docs refactor test sec perf build ci revert"
  fail=1
fi

# Issue reference — CM-3/CM-5: work with no issue is unauthorized change.
if ! printf '%s' "$msg" | grep -qiE '(refs?|closes|fixes|resolves)[: ]+#[0-9]+|#[0-9]+'; then
  echo "[FAIL] No issue reference. Add 'Refs: #<n>'."
  echo "       Every change traces to a work item (CM-3, CM-5)."
  fail=1
fi

# AI authorship trailer — AIC-6. Warn, not block: we cannot tell from here whether this
# commit was agent-assisted. The PR-level check in pr-governance.yml is the real gate.
if ! printf '%s' "$msg" | grep -qi '^AI-Assisted:'; then
  echo "[warn] No 'AI-Assisted:' trailer. If any part was agent-authored, declare it (AIC-6)."
fi

[ "$fail" -ne 0 ] && { echo ""; echo "Commit message rejected."; exit 1; }
exit 0
HOOK

chmod +x "$HOOK_DIR/pre-commit" "$HOOK_DIR/commit-msg"
chmod +x "$REPO_ROOT/.claude/hooks/"*.sh 2>/dev/null || true

cat <<'DONE'

Installed:
  .git/hooks/pre-commit   secrets, large files, evidence integrity, conflict markers
  .git/hooks/commit-msg   conventional commits, issue reference, AI-authorship trailer

Also made .claude/hooks/*.sh executable (the agent guardrails).

Next:
  1. Install gitleaks for real secret coverage: https://github.com/gitleaks/gitleaks
  2. Add your linter and unit tests to the ADAPT block in .git/hooks/pre-commit
  3. Verify the agent guardrails still block what they should:
       bash .claude/hooks/selftest.sh
  4. Complete SETUP.md — branch protection and the production Environment are where the
     separation-of-duties and release-authorization controls actually live. Until then
     they are documentation, not controls.

Note: git hooks are per-clone and are not version-controlled. Every contributor runs this.
CI re-runs all of it server-side, so a local bypass is detected rather than trusted.
DONE
