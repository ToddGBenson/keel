#!/usr/bin/env bash
# Self-test for the agent guard hooks.
# Controls: CA-2 (control assessment), AIC-3, AIC-5, AU-9
#
# Per the control-assessment skill: TEST beats EXAMINE. A control that reads correctly and
# fails when exercised is the finding that matters. This exercises each guard by attempting
# the thing it should block and confirming it blocks — and, just as importantly, confirming
# it does NOT block legitimate work.
#
# Run after ANY edit to a guard hook, and during quarterly assessment. Record the output to
# evidence/assessments/<quarter>/.
#
# Usage:  bash .claude/hooks/selftest.sh

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

pass=0; fail=0

# Credential-shaped fixtures are SPLIT so the matching literal never appears contiguously in
# this file — otherwise this file could not be written past its own secret guard. The split
# is inside the token (api""_key), not merely at a quote boundary; splitting at the boundary
# leaves the text contiguous and still trips the pattern. Learned by doing exactly that.
AKIA_FAKE="AKI""A""ABCDEFGHIJKLMNOP"
ASSIGN_FAKE="api""_key = abcdefghij0123456789"

payload() { printf '{"tool_input":{"command":"%s"}}' "$1"; }
wpayload() {
  # $1 = path, $2 = content. Escape the JSON-significant characters we use.
  esc=$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"tool_input":{"file_path":"%s","content":"%s"}}' "$1" "$esc"
}

check() { # name, expected(block|allow), payload, hook
  local name="$1" expect="$2" pl="$3" hook="$4" rc got
  printf '%s' "$pl" | bash ".claude/hooks/$hook" >/dev/null 2>&1
  rc=$?
  got="allow"; [ "$rc" -eq 2 ] && got="block"
  if [ "$got" = "$expect" ]; then
    printf '  [ok]   %-52s %s\n' "$name" "$got"; pass=$((pass+1))
  else
    printf '  [FAIL] %-52s expected %s, got %s\n' "$name" "$expect" "$got"; fail=$((fail+1))
  fi
}

echo ""
echo "guard-bash.sh — must BLOCK (AIC-2, AIC-3)"
check "hook bypass"               block "$(payload 'git commit --no-verify -m x')"        guard-bash.sh
check "force push"                block "$(payload 'git push --force origin main')"       guard-bash.sh
check "history rewrite"           block "$(payload 'git filter-branch --all')"            guard-bash.sh
check "self-approve a PR"         block "$(payload 'gh pr review 42 --approve')"          guard-bash.sh
check "self-merge a PR"           block "$(payload 'gh pr merge 42')"                     guard-bash.sh
check "create a release"          block "$(payload 'gh release create v1.0.0')"           guard-bash.sh
check "credential handling"       block "$(payload 'gh secret set TOKEN')"                guard-bash.sh
check "production mutation"       block "$(payload 'terraform apply -auto-approve')"      guard-bash.sh

echo ""
echo "guard-bash.sh — credential file reads must BLOCK (AIC-5)"
check "cat a .env file"           block "$(payload 'cat .env')"                           guard-bash.sh
check "cat a private key"         block "$(payload 'cat ~/.ssh/id_rsa')"                  guard-bash.sh
check "head a .pem"               block "$(payload 'head -5 server.pem')"                 guard-bash.sh

echo ""
echo "guard-bash.sh — must ALLOW (no false positives)"
check "git status"                allow "$(payload 'git status')"                         guard-bash.sh
check "git diff"                  allow "$(payload 'git diff --cached')"                  guard-bash.sh
check "read an issue"             allow "$(payload 'gh issue view 42')"                   guard-bash.sh
check "run tests"                 allow "$(payload 'npm test')"                           guard-bash.sh
# DEFECT L0008 — bare keyword globs matched the WORD anywhere in the command, blocking
# heredocs and documentation that merely discuss secret handling.
check "writing docs about secrets" allow "$(payload 'cat > lesson.md <<EOF
named credentials require a value
EOF')"                                                                                    guard-bash.sh
check "grepping for the word"     allow "$(payload 'grep -r credentials docs/')"          guard-bash.sh
# L0008 second recurrence — the bypass glob matched ANY ' -n ' followed by 'commit'
# anywhere, so a shell syntax check chained before a commit was refused as a bypass.
check "bash -n then commit"       allow "$(payload 'bash -n script.sh && git commit -m x')" guard-bash.sh
check "sort -n in a pipeline"     allow "$(payload 'sort -n f.txt && git commit -m x')"   guard-bash.sh
check "real --no-verify"          block "$(payload 'git commit --no-verify -m x')"        guard-bash.sh
check "real push --no-verify"     block "$(payload 'git push --no-verify')"               guard-bash.sh

echo ""
echo "guard-write.sh — must BLOCK (AU-9, AIC-5)"
check "hand-edit generated SARIF" block "$(wpayload 'evidence/142/g4/scan.sarif' 'x')"    guard-write.sh
check "hand-edit generated XML"   block "$(wpayload 'evidence/142/g4/results.xml' 'x')"   guard-write.sh
check "credential assignment"     block "$(wpayload 'src/config.py' "$ASSIGN_FAKE")"      guard-write.sh
check "cloud key literal"         block "$(wpayload 'src/config.py' "$AKIA_FAKE")"        guard-write.sh

echo ""
echo "guard-write.sh — must ALLOW (regression tests for real defects, 2026-08-07)"
check "narrative evidence (.md)"  allow "$(wpayload 'evidence/142/g4/security/verify.md' 'Verified AC-3.')" guard-write.sh
check "ordinary source file"      allow "$(wpayload 'src/drafts.py' 'def save(): pass')"  guard-write.sh
# DEFECT 1 — keyword-shaped matching blocked all secret-detection tooling.
check "secret-DETECTION code"     allow "$(wpayload 'scripts/scan.sh' 'grep -E aws_secret_access_key .')" guard-write.sh
# DEFECT 2 — the guard matched its own patterns and blocked its own repair.
check "editing the guard itself"  allow "$(wpayload '.claude/hooks/guard-write.sh' 'grep -qEi api_key_pattern')" guard-write.sh

echo ""
echo "──────────────────────────────────────────────────────────────"
printf '  %d passed, %d failed\n' "$pass" "$fail"
if [ "$fail" -ne 0 ]; then
  echo ""
  echo "  A guard is not behaving as documented. This is a CONTROL FAILURE —"
  echo "  file it as a finding; do not work around it."
  echo "  Enforcement claims live in docs/11-ai-agent-controls.md § Enforcement summary."
  exit 1
fi
echo "  All guards behave as documented."
echo ""
exit 0
