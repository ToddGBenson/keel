#!/usr/bin/env bash
# PreToolUse hook for Write|Edit — protects evidence integrity and flags secrets.
# Controls: AU-9 (protection of audit information), AIC-5, IA-5, AIC-8
#
# NOTE (verified 2026-08-07): the PreToolUse payload carries cwd, session_id, tool_name,
# tool_input, permission_mode, prompt_id, tool_use_id, and transcript_path — but NO field
# identifying the acting subagent. Per-agent path scoping therefore CANNOT be enforced here.
# The "may write source" boundaries in docs/compliance/ai-inventory.md are prompt-enforced,
# with the monthly CI audit as detection. See docs/11-ai-agent-controls.md § AIC-3, POAM-001.

set -uo pipefail

payload="$(cat)"

# ── Payload extraction ───────────────────────────────────────────────────────
# DEFECT FIXED 2026-08-07 (found by dogfooding): the previous fallback set
# content="$payload" when jq was absent, which included old_string. The hook therefore
# scanned the text being REMOVED and blocked any edit that took a secret OUT of a file —
# exactly the operation you most need to perform. Only NEW content is ever scanned now.
# Python is used as the fallback because the previous sed extraction was also unreliable
# on multi-line content.
if command -v jq >/dev/null 2>&1; then
  path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')"
  content="$(printf '%s' "$payload" | jq -r '(.tool_input.content // .tool_input.new_string // "")')"
elif command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
  PY="$(command -v python3 || command -v python)"
  path="$(printf '%s' "$payload" | "$PY" -c 'import sys,json;d=json.load(sys.stdin);print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null)"
  content="$(printf '%s' "$payload" | "$PY" -c 'import sys,json;d=json.load(sys.stdin);t=d.get("tool_input",{});print(t.get("content") or t.get("new_string") or "")' 2>/dev/null)"
else
  # No reliable parser. Fail OPEN on content scanning rather than blocking all edits,
  # and say so — CI secret scanning is authoritative and will catch it server-side.
  echo "guard-write.sh: no jq or python; content scanning skipped (CI scan is authoritative)" >&2
  exit 0
fi

[ -z "$path" ] && exit 0

block() {
  echo "BLOCKED by .claude/hooks/guard-write.sh — $1" >&2
  echo "" >&2
  echo "Control: $2. See docs/11-ai-agent-controls.md." >&2
  exit 2
}

warn() { echo "WARNING  $1" >&2; }

# ── Evidence is generated, never hand-authored (AU-9) ───────────────────────
# A hand-edited scan report or test result is a fabrication regardless of intent, and it is
# the failure mode that makes an entire compliance posture worthless. If evidence is wrong,
# regenerate it and record why.
case "$path" in
  */evidence/*|evidence/*)
    case "$path" in
      # Narrative artifacts an agent legitimately authors during a gate.
      *.md) : ;;
      *) block "hand-editing generated evidence ($path). Regenerate it instead." "AU-9, CA-2" ;;
    esac
    ;;
esac

# ── Secrets never enter source (AIC-5, IA-5) ────────────────────────────────
# Coarse on purpose — the CI secret scan is authoritative. This catches the obvious case
# before it reaches history, where removal is no longer sufficient and rotation is required.
#
# TWO RULES LEARNED BY DOGFOODING (2026-08-07), both real defects this hook had:
#
#  1. Match VALUE shape, not bare keywords. A keyword alone appears legitimately in
#     secret-DETECTION code — this file, scripts/install-hooks.sh, security.yml, and the
#     scanner-triage skill all contain such patterns. Keyword matching blocked all of it.
#
#  2. A DETECTION PATTERN MUST NOT MATCH ITSELF. Writing the keyword literally here made
#     the hook block every edit to the hook, including its own repair. The [x] character
#     classes below match identically but cannot self-trigger. PRESERVE THEM when editing.
#
# Named credentials require an assignment and a plausible value. Opaque token formats are
# already value-shaped and match on their own.
if printf '%s' "$content" | grep -qEi \
   '(aws_secret_access_[k]ey|api[_-]?ke[y]|client[_-]?secre[t]|passwor[d])["'"'"' ]*[=:][ "'"'"']*[A-Za-z0-9/+_-]{16,}'; then
  block "apparent credential assignment in the content. Rotate it; do not commit it." "IA-5, AIC-5, SC-28"
fi
if printf '%s' "$content" | grep -qE \
   '(-----BEGIN [A-Z ]*PRIVATE KE[Y]-----|xox[baprs]-[0-9A-Za-z]{10,}-[0-9A-Za-z]{10,}|gh[pousr]_[0-9A-Za-z]{36}|sk-ant-api[0-9]{2}-[0-9A-Za-z_-]{24,}|AKI[A][0-9A-Z]{16})'; then
  block "apparent credential material in the content. Rotate it; do not commit it." "IA-5, AIC-5, SC-28"
fi

# ── Notices on high-consequence paths ───────────────────────────────────────
case "$path" in
  */.github/workflows/*|*/ci/pipeline.yml|*/ci/tasks/*|*/ci/scripts/*)
    warn "Editing a workflow. The pipeline gates every other control here — this change requires security review (CM-5), and relaxing a check is a visible process change, not a quiet diff." ;;
  */.claude/agents/*|*/.claude/commands/*|*/.claude/skills/*)
    warn "Editing an agent, command, or skill definition. These are configuration items under change control (AIC-8). A change that RELAXES a control needs the same approval as relaxing a pipeline gate — flag it explicitly in the PR." ;;
  */.claude/hooks/*)
    warn "Editing a guard hook. These ARE the enforcement layer for AIC-3/AIC-5. Verify the change still blocks what it should: bash .claude/hooks/selftest.sh" ;;
  */process/gates/*)
    warn "Editing a gate checklist. This is the contract the whole process rests on. Human approval required." ;;
  */docs/compliance/*)
    warn "Editing compliance material. Control claims must be backed by evidence that actually supports them — never mark a control satisfied to unblock work (PD-7)." ;;
esac

exit 0
