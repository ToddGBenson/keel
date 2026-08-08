#!/usr/bin/env bash
# PreToolUse hook for Bash — enforces the agent constraints that must not depend on a
# model choosing to comply. (AIC-3 least agency, AIC-5 secrets, AIC-11 bounded autonomy)
#
# Per docs/11-ai-agent-controls.md § Enforcement summary: prompt-only controls are
# advisory — a sufficiently confused model ignores them. The controls that hold under
# adversarial conditions are the ones implemented here, in the tool grant, and in branch
# protection. The design question is never "what should the agent be told" but
# "what makes the unwanted action impossible."
#
# Contract: reads the hook payload on stdin; exit 2 blocks the call and returns stderr
# to the model as feedback. Exit 0 allows.

set -uo pipefail

payload="$(cat)"

# Extract the command. Prefer jq; fall back to a tolerant sed for environments without it.
if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')"
else
  cmd="$(printf '%s' "$payload" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p')"
fi

[ -z "$cmd" ] && exit 0

block() {
  echo "BLOCKED by .claude/hooks/guard-bash.sh — $1" >&2
  echo "" >&2
  echo "This is a process control ($2), not a suggestion. Do not work around it." >&2
  echo "If the control is genuinely wrong, that is a process change: open an issue" >&2
  echo "labelled 'process' and use /learn. See CLAUDE.md § When the process is wrong." >&2
  exit 2
}

# ── Hook bypass ─────────────────────────────────────────────────────────────
# If a hook blocks you, the hook is working correctly. Bypassing it defeats the
# pre-commit secret scan, which is the last cheap chance to stop a credential leak.
#
# GP-2 APPLIED 2026-08-08 (L0008, second recurrence in this file). The previous globs were:
#     *--no-verify*|*" -n "*"commit"*|*"commit -n"*
# The middle one matched ANY command containing " -n " anywhere followed by "commit"
# anywhere — so `bash -n script.sh && git commit ...` (a syntax check!) was blocked as a
# hook bypass. I fixed the credential glob for exactly this reason and did not check the
# siblings in the same file, which is the definition of L0008.
#
# Now anchored: the flag must belong to a git commit/push invocation.
if printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]])git[[:space:]]+[^|;&]*(commit|push|merge)[^|;&]*[[:space:]]--no-verify\b' \
   || printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]])git[[:space:]]+(commit|push)[[:space:]]+[^|;&]*[[:space:]]-[a-zA-Z]*n([[:space:]]|$)'; then
  block "hook bypass (--no-verify / -n on a git commit). Fix the cause the hook found." "AIC-3, IA-5"
fi

# ── Destructive git ─────────────────────────────────────────────────────────
case "$cmd" in
  *"push --force"*|*"push -f "*|*"push --force-with-lease"*)
    block "force push. Published history is immutable — it is the AU-12 audit trail." "AIC-3, AU-12, SI-7" ;;
  *"reset --hard"*)
    block "git reset --hard. Discards work irrecoverably; use git revert or a branch." "AIC-3" ;;
  *"filter-branch"*|*"filter-repo"*)
    block "history rewrite. Destroys the attributable, signed commit record." "AU-12, SI-7" ;;
  *"push"*"origin"*"main"*|*"push origin HEAD:main"*)
    block "direct push to main. All change goes through a reviewed PR." "AC-5, CM-5" ;;
esac

# ── Self-approval and self-merge (the control that makes every gate meaningful) ──
case "$cmd" in
  *"pr review"*"--approve"*)
    block "approving a PR. Agents recommend; a human or a separate reviewing identity approves." "AC-5, AIC-2" ;;
  *"pr merge"*)
    block "merging a PR. Merge happens after independent review, via GitHub." "AC-5, CM-5, AIC-2" ;;
  *"release create"*|*"release edit"*)
    block "creating a release. G5 requires human authorization via the production Environment." "CM-3, AIC-1" ;;
esac

# ── Weakening a security control ────────────────────────────────────────────
case "$cmd" in
  *"continue-on-error: true"*)
    block "setting continue-on-error on a check. If a gate must be relaxed, that is a visible process change." "CM-5, AIC-3" ;;
  *"branch-protection"*"--delete"*|*"api"*"branch_protection"*"-X DELETE"*)
    block "removing branch protection. This is the control enforcing separation of duties." "AC-5, CM-5" ;;
esac

# ── Secrets (AIC-5) ─────────────────────────────────────────────────────────
# Reading credential material into a context is disclosure. If it happens, the correct
# response is to ROTATE first, then remediate the path — deleting a message is not a
# mitigation.
#
# GP-2 APPLIED 2026-08-07 (defect L0008). These were bare substring globs:
#   *"cat "*"credentials"*
# which matched any command mentioning the word ANYWHERE — including heredoc content and
# documentation about secret handling. It blocked writing the lesson file that describes
# this very failure mode. Identical keyword-vs-value-shape defect to L0002 in
# guard-write.sh; fixed there and not propagated here, which is its own lesson.
#
# The patterns now anchor on the FILE ARGUMENT of a reader command, not on vocabulary.
if printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]])(cat|less|more|head|tail|bat|type)[[:space:]]+[^|;&]*([.]env([.][A-Za-z0-9_-]+)?|[.]pem|[.]p12|[.]pfx|[.]key|/[.]ssh/|/[.]aws/|id_rsa|id_ed25519)([[:space:]]|$|"|'"'"')'; then
  block "reading credential material into the context. Rotate rather than inspect." "AIC-5, IA-5, SC-28"
fi
case "$cmd" in
  *"gh secret"*|*"aws configure"*|*"gcloud auth"*)
    block "handling credentials. Agents never touch secrets; escalate to a human." "AIC-5, IA-5" ;;
esac

# ── Production access (AIC-3) ───────────────────────────────────────────────
# Agents operate on source, CI configuration, and non-production environments. Production
# change happens through the G5-authorized pipeline, executed by the pipeline identity.
case "$cmd" in
  *"kubectl"*"prod"*|*"--context"*"prod"*|*"--profile"*"prod"*|*"terraform apply"*)
    block "production or infrastructure mutation. The pipeline deploys, never an agent." "AIC-3, CM-5, AC-6" ;;
esac

exit 0
