#!/usr/bin/env bash
# Prove .gitleaks.toml still detects real secrets.
# Controls: RA-5, IA-5, SI-7 · Method: .claude/skills/scanner-triage/SKILL.md
#
# ── WHY THIS EXISTS ──────────────────────────────────────────────────────────
# A gitleaks allowlist can fail in two directions, and only one of them is visible.
#
#   Too narrow  -> the fixture keeps alarming.        You notice immediately.
#   Too broad   -> real secrets stop being reported.  The scan turns GREEN.
#
# The second is the dangerous one, and it is not hypothetical here: the first version of
# this repo's allowlist matched the bare value `abcdefghij0123456789`, which occurs as a
# substring inside plausible real tokens. It suppressed a planted `ghp_` token. It looked
# narrow, it passed review by eye, and it had quietly blinded the scanner.
#
# Reading a config cannot catch that. Only planting a secret and demanding it be found can
# (L0005 — a test beats an examination).
#
# Usage:  bash scripts/test-gitleaks-allowlist.sh

set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

GL_IMAGE="zricethezav/gitleaks:v8.18.4"
fail=0
ok()   { printf '  [ok]   %s\n' "$1"; }
bad()  { printf '  [FAIL] %s\n' "$1"; fail=1; }
skip() { printf '  [skip] %s\n' "$1"; }

echo "Gitleaks allowlist regression test"

# A scanner test with no way to run must SAY so rather than pass silently (L0009).
# Skipping is an honest outcome; reporting success without running is not.
if command -v gitleaks >/dev/null 2>&1; then
  run_gl() { gitleaks detect --source "$1" --no-banner --report-format json --report-path "$2" >/dev/null 2>&1; }
elif command -v docker >/dev/null 2>&1 && docker version >/dev/null 2>&1; then
  run_gl() {
    local src; src="$(cd "$1" && (pwd -W 2>/dev/null || pwd))"
    MSYS_NO_PATHCONV=1 docker run --rm -v "$src":/repo -v "$(cd "$(dirname "$2")" && (pwd -W 2>/dev/null || pwd))":/out \
      "$GL_IMAGE" detect --source /repo --no-banner --report-format json \
      --report-path "/out/$(basename "$2")" >/dev/null 2>&1
  }
else
  skip "neither gitleaks nor docker available — allowlist NOT verified this run"
  echo "  Install gitleaks, or run this in CI, before trusting a green secret scan."
  exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CANARY="$TMP/canary"; mkdir -p "$CANARY"

# Planted secrets. Both are published, non-functional example values -- AWS's own
# documentation key, and a token built from a fixed digit/letter run. Neither authenticates
# to anything. The second deliberately CONTAINS the fixture's alphabet run, because that is
# the exact shape that defeated the first allowlist.
cp .gitleaks.toml "$CANARY/"
{
  printf 'AWS_KEY = "AKIA%s"\n' "IOSFODNN7EXAMPLE"
  printf 'TOKEN = "ghp_%s"\n'   "0123456789abcdefghij0123456789abcdef"
} > "$CANARY/planted.py"
git -C "$CANARY" init -q .
git -C "$CANARY" add -A
git -C "$CANARY" -c user.email=t@t -c user.name=t commit -qm canary >/dev/null 2>&1

count_findings() {
  [ -s "$1" ] || { echo 0; return; }
  python - "$1" 2>/dev/null <<'PY' || echo 0
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    print(len(d) if isinstance(d,list) else 0)
except Exception:
    print(0)
PY
}

# 1. Real secrets must still be found, WITH this repo's allowlist loaded.
run_gl "$CANARY" "$TMP/canary.json"
n="$(count_findings "$TMP/canary.json")"
if [ "$n" -ge 2 ]; then
  ok "planted secrets still detected ($n/2) — allowlist has not blinded the scanner"
else
  bad "only $n/2 planted secrets detected — THE ALLOWLIST IS TOO BROAD"
  echo "         A green secret scan is currently meaningless. Fix .gitleaks.toml before merging."
fi

# 2. The self-test fixture must NOT be reported.
run_gl "." "$TMP/self.json"
m="$(count_findings "$TMP/self.json")"
if [ "$m" -eq 0 ]; then
  ok "repository clean — the selftest.sh fixture is correctly allowlisted"
else
  bad "$m finding(s) in this repository — triage them (scanner-triage), do not widen the allowlist"
fi

echo ""
[ "$fail" -eq 0 ] && echo "  allowlist verified in BOTH directions" || echo "  allowlist FAILED verification"
exit "$fail"
