#!/usr/bin/env bash
# PreToolUse hook for Write|Edit|MultiEdit|NotebookEdit — protects evidence integrity and flags secrets.
# Controls: AU-9 (protection of audit information), AIC-5, IA-5, AIC-8
#
# NOTE (verified 2026-08-07): the PreToolUse payload carries cwd, session_id, tool_name,
# tool_input, permission_mode, prompt_id, tool_use_id, and transcript_path — but NO field
# identifying the acting subagent. Per-agent path scoping therefore CANNOT be enforced here.
# The "may write source" boundaries in docs/compliance/ai-inventory.md are prompt-enforced,
# with the monthly CI audit as detection. See docs/11-ai-agent-controls.md § AIC-3, POAM-001.

set -uo pipefail

# TheHub #61844: FAIL CLOSED, as guard-bash.sh does since TheHub #61794. This hook
# had the same three defects (test/hook-write-fail-closed.test.py holds each):
#
# 1. `printf ... | grep -q` under pipefail: grep -q exits at its first match, the writer
#    dies of SIGPIPE, the pipeline returns 141, and the `if` read a MATCH as "no match".
#    A credential followed by ~400 KB of content was ALLOWED, with jq and without.
#    The grep wrapper drops -q and discards its output, so grep drains its input, and
#    141 from a writer counts as success.
# 2. A helper (grep, cat, jq, python) that errored or was killed left a capture empty or
#    a test false, and the hook reached `exit 0`. Helpers run through wrappers that record
#    a real error in a fault file; the EXIT trap turns an allow into a block when it holds one.
# 3. Claude Code blocks only on exit 2. The EXIT trap makes every other code but 0 a block,
#    and the fault file starts with a sentinel line, so emptying or removing it is a fault.
#
# The wrappers and the trap are guard-bash.sh's, copied so each hook stands alone.
guard_sentinel="guard-write.sh fault file $$"
guard_faults="$(command mktemp 2>/dev/null)" \
  && printf '%s\n' "$guard_sentinel" > "$guard_faults" 2>/dev/null || {
  echo "BLOCKED by .claude/hooks/guard-write.sh — internal error: cannot create its fault file, so it cannot tell whether its own checks ran. Retry the call." >&2
  exit 2
}
export guard_faults
# shellcheck disable=SC2317  # the wrappers are called indirectly, by name, from every rule below
guard_fault() { printf '%s exited %s\n' "$1" "$2" >> "$guard_faults" 2>/dev/null; }
guard_run() { # $1: tool, $2: highest exit status that is not an error; the rest: its args
  local t=$1 ok=$2 rc; shift 2
  command "$t" "$@"; rc=$?
  # TheHub #61973: 141 (SIGPIPE) is a fault too. The grep wrapper drains its input, so no
  # wrapped helper is a writer whose reader stopped early, and an extractor killed by
  # SIGPIPE left an empty capture that read as an allow.
  [ "$rc" -gt "$ok" ] && guard_fault "$t" "$rc"
  return "$rc"
}
grep() { # -q (and --quiet/--silent) dropped, output discarded: grep reads all its input
  local a args=() quiet=0 opts=1
  for a in "$@"; do
    if [ "$opts" -eq 1 ]; then
      case "$a" in
        --) opts=0 ;;
        --quiet|--silent) quiet=1; continue ;;
        --*) ;;
        -*q*) quiet=1; a="${a//q/}"; [ "$a" = "-" ] && continue ;;
        -*) ;;
        *) opts=0 ;;
      esac
    fi
    args+=("$a")
  done
  if [ "$quiet" -eq 1 ]; then guard_run grep 1 "${args[@]}" >/dev/null; else guard_run grep 1 "${args[@]}"; fi
}
# shellcheck disable=SC2120  # called with no arguments here (payload="$(cat)"); kept general like guard-bash.sh's
cat()     { guard_run cat 0 "$@"; }
jq()      { guard_run jq 0 "$@"; }
python3() { guard_run python3 0 "$@"; }
python()  { guard_run python 0 "$@"; }
# shellcheck disable=SC2317  # run by the EXIT trap
guard_exit() { # builtins only: a broken helper must not be able to hide its own fault
  local rc=$? why="" lines=()
  [ -f "$guard_faults" ] && mapfile -t lines < "$guard_faults" 2>/dev/null
  if [ "$rc" -ne 2 ]; then
    if [ "${#lines[@]}" -eq 0 ] || [ "${lines[0]}" != "$guard_sentinel" ]; then
      why="its fault file was emptied or removed while it ran"
    elif [ "${#lines[@]}" -gt 1 ]; then
      why="a helper it reads the write with failed (${lines[*]:1:3})"
    elif [ "$rc" -ne 0 ]; then
      why="it stopped with exit $rc before reaching a verdict"
    elif [ "$guard_verdict" != 1 ]; then
      # TheHub #62264: bash reads a script as it runs it. A hook file rewritten in place while a run
      # starts (a branch switch, a platform sync) can end early, and bash then exits 0 at the cut:
      # an allow nobody decided. An allow now comes only from guard_allow, which the rules end in.
      why="it reached the end of what it read without a verdict (its file may have been rewritten while it ran)"
    fi
  fi
  command rm -f "$guard_faults" 2>/dev/null
  if [ -n "$why" ]; then
    {
      echo "BLOCKED by .claude/hooks/guard-write.sh — internal error: $why, so it cannot tell whether the write is allowed."
      echo ""
      echo "This is the guard failing closed (TheHub #61844), not a rule. Retry the call; if it"
      echo "keeps happening, the host is short of a tool or of resources."
    } >&2
    exit 2
  fi
  # The settings entry allows only when this line is the hook's whole stdout (TheHub #62264).
  [ "$rc" -eq 0 ] && printf '%s\n' "guard-verdict: allow"
  exit "$rc"
}
# TheHub #62264: guard_allow is the only allow. It is called where a verdict is reached (the last
# line of this file, and an empty command or path), so a run whose file was cut short ends without
# one, and guard_exit turns that into a block. The verdict starts empty here: nothing inherited
# from the environment may stand in for it.
guard_verdict=""
guard_allow() { guard_verdict=1; exit 0; }
trap guard_exit EXIT
# TheHub #61973: a catchable signal ends the shell with 128+N, which Claude Code reads as
# an allow. Each one is recorded as a fault and turned into a block by the EXIT trap.
for guard_sig in HUP INT TERM PIPE ALRM USR1 USR2; do
  # shellcheck disable=SC2064  # the signal name is fixed when the trap is set
  trap "guard_fault signal $guard_sig; exit 1" "$guard_sig"
done

payload="$(cat)"

# ── Payload extraction ───────────────────────────────────────────────────────
# DEFECT FIXED 2026-08-07 (found by dogfooding): the previous fallback set
# content="$payload" when jq was absent, which included old_string. The hook therefore
# scanned the text being REMOVED and blocked any edit that took a secret OUT of a file —
# exactly the operation you most need to perform. Only NEW content is ever scanned now.
# Python is used as the fallback because the previous sed extraction was also unreliable
# on multi-line content.
# `type -P`, not `command -v`: jq() and python3() are wrapper functions now, and
# `command -v` would report them even where no binary exists (TheHub #61794).
# TheHub #61391: every write tool. NotebookEdit names its file notebook_path and its text
# new_source; MultiEdit carries its new text in edits[].new_string. Read as Write and Edit
# alone, both gave an empty path, and the hook allowed the write without reading it. All new
# text the call carries is scanned, joined by newlines; old_string never is.
if type -P jq >/dev/null 2>&1; then
  path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
  pcwd="$(printf '%s' "$payload" | jq -r '.cwd // empty')"
  content="$(printf '%s' "$payload" | jq -r '[.tool_input.content, .tool_input.new_string, .tool_input.new_source, (.tool_input.edits // [] | .[]? | .new_string?)] | map(select(type == "string")) | join("\n")')"
elif type -P python3 >/dev/null 2>&1 || type -P python >/dev/null 2>&1; then
  # The wrapper's name, not a path, so a failing interpreter is recorded as a fault.
  PY=python3; type -P python3 >/dev/null 2>&1 || PY=python
  path="$(printf '%s' "$payload" | "$PY" -c 'import sys,json;t=json.load(sys.stdin).get("tool_input",{});print(t.get("file_path") or t.get("notebook_path") or "")' 2>/dev/null)"
  pcwd="$(printf '%s' "$payload" | "$PY" -c 'import sys,json;print(json.load(sys.stdin).get("cwd") or "")' 2>/dev/null)"
  content="$(printf '%s' "$payload" | "$PY" -c 'import sys,json;t=json.load(sys.stdin).get("tool_input",{});e=[x.get("new_string") for x in (t.get("edits") or []) if isinstance(x,dict)];print("\n".join(s for s in [t.get("content"),t.get("new_string"),t.get("new_source")]+e if isinstance(s,str)))' 2>/dev/null)"
else
  # No reliable parser. Fail OPEN on content scanning rather than blocking all edits,
  # and say so — CI secret scanning is authoritative and will catch it server-side.
  echo "guard-write.sh: no jq or python; content scanning skipped (CI scan is authoritative)" >&2
  guard_allow
fi

[ -z "$path" ] && guard_allow

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
# TheHub #62022: judge the path the way the file system will resolve it. On Windows a path
# takes backslashes and its case is ignored, so evidence\142\x.sarif and Evidence/x.sarif
# are the same file as evidence/x.sarif, and the rule (forward slashes, lower case) let them
# through on every write tool. The review of #197 found more spellings of the same file:
# a drive-relative C:evidence\..., an NTFS stream suffix on a segment (evidence::$INDEX_
# ALLOCATION/...), and a trailing dot or space on a segment (evidence./...). A relative
# path is also resolved against the payload's cwd: 142/x.sarif from inside evidence/ is
# evidence. So the path is rebuilt segment by segment, with builtins only:
#   backslashes as slashes; a relative path joined to the payload's cwd; a drive-relative
#   "C:" prefix dropped; per segment, "." and ".." judged as written (".." resolved), an
#   exact unnamed stream type (::$DATA) dropped, trailing dots and spaces trimmed. A segment
#   that only trims to "", "." or "..", a line break, and inside evidence/ any ":" (a named
#   stream) or a trailing dot or space on the file name, are refused (review rounds 2 and 3).
# Case is ignored by the matches below (nocasematch), not by rewriting the path: no
# external tool, so nothing planted on PATH can change the answer.
guard_slash() { local s=${1//\\//}; printf '%s' "$s"; }
guard_unread() { # the path cannot be judged: refuse it (review of #197, rounds 2 and 3)
  local shown=${1//[$'\001'-$'\037'$'\177']/?}           # control characters are not echoed raw
  echo "BLOCKED by .claude/hooks/guard-write.sh — the write's path ($shown) cannot be judged safely: $2. Name the file plainly." >&2
  echo "" >&2
  echo "Control: AU-9, CA-2. See docs/11-ai-agent-controls.md." >&2
  exit 2
}
# A line feed or carriage return in the path or the cwd would split it below; no real file
# name an agent writes has one.
case "$path${pcwd:-}" in *$'\n'*|*$'\r'*) guard_unread "with a line break" "it contains a line feed or carriage return" ;; esac
npath=$(guard_slash "$path")
pcwd=$(guard_slash "${pcwd:-}")
case "$npath" in
  /*|[A-Za-z]:/*) ;;                                     # absolute
  [A-Za-z]:*) npath=${npath:2}; [ -n "$pcwd" ] && npath="$pcwd/$npath" ;;  # drive-relative
  *) [ -n "$pcwd" ] && npath="$pcwd/$npath" ;;           # relative to the cwd
esac
# guard_cut and guard_dots move in step with guard_segs: a ".." pops all three, so the cut
# reading and the trailing-dot flag describe the segments that are KEPT (TheHub #62037).
guard_segs=() guard_lead="" guard_colon=0 guard_lastdot=0 guard_cut=() guard_dots=()
case "$npath" in /*) guard_lead="/" ;; esac
IFS='/' read -r -a guard_parts <<< "$npath"
guard_n() { printf '%s' "${#guard_segs[@]}"; }
for guard_seg in ${guard_parts[@]+"${guard_parts[@]}"}; do
  if [ "$(guard_n)" -eq 0 ] && [ -z "$guard_lead" ] && case "$guard_seg" in [A-Za-z]:) true ;; *) false ;; esac; then
    guard_segs+=("$guard_seg"); guard_cut+=("$guard_seg"); guard_dots+=(0); continue  # a drive, C:
  fi
  # "." and ".." are judged on the segment as written, before any trimming: Windows turns
  # "..." or ".. " into something else, and a segment that only BECOMES "." or ".." (or
  # nothing) after trimming is refused rather than guessed at.
  case "$guard_seg" in
    ""|.) continue ;;
    ..) if [ "$(guard_n)" -gt 0 ] && [ "${guard_segs[$(( $(guard_n) - 1 ))]}" != ".." ]; then
          guard_i=$(( $(guard_n) - 1 ))
          unset "guard_segs[$guard_i]" "guard_cut[$guard_i]" "guard_dots[$guard_i]"
          guard_segs=(${guard_segs[@]+"${guard_segs[@]}"})
          guard_cut=(${guard_cut[@]+"${guard_cut[@]}"})
          guard_dots=(${guard_dots[@]+"${guard_dots[@]}"})
        else guard_segs+=(".."); guard_cut+=(".."); guard_dots+=(0); fi
        continue ;;
  esac
  # Round 3: any ":" in a segment (other than a drive, C:) is noted, and refused inside
  # evidence/ below: a named stream (a.md:x.sarif, a.md:x.sarif:$DATA) is not the .md in
  # front of it. Only an exact, unnamed stream TYPE (::$DATA, ::$INDEX_ALLOCATION,
  # :$I30:$INDEX_ALLOCATION) is dropped here, so the directory it names is still recognised.
  case "$guard_seg" in [A-Za-z]:) ;; *:*) guard_colon=1 ;; esac
  case "$guard_seg" in
    *'::$'[A-Za-z_]*) [ -z "${guard_seg#*::\$}" ] || case "${guard_seg#*::\$}" in *[!A-Za-z_]*) ;; *) guard_seg=${guard_seg%%::\$*} ;; esac ;;
    *':$I30:$INDEX_ALLOCATION') guard_seg=${guard_seg%:\$I30:\$INDEX_ALLOCATION} ;;
  esac
  guard_raw=$guard_seg
  guard_dot=0
  case "$guard_seg" in *[.\ ]) guard_dot=1 ;; esac
  while case "$guard_seg" in *[.\ ]) true ;; *) false ;; esac; do
    guard_seg=${guard_seg%?}                               # trailing dots and spaces
  done
  case "$guard_seg" in
    ""|.|..) guard_unread "$path" "the segment \"$guard_raw\" means something different on Windows" ;;
  esac
  guard_segs+=("$guard_seg")
  guard_cut+=("${guard_seg%%:*}")                          # the same, cut at any ':' (for recognising evidence/)
  guard_dots+=("$guard_dot")
done
# The trailing-dot flag of the last segment KEPT, not the last one read: b.md./x/.. keeps
# b.md. (Node on Windows writes a file literally named so).
[ "$(guard_n)" -gt 0 ] && guard_lastdot=${guard_dots[$(( $(guard_n) - 1 ))]}
npath="$guard_lead$(IFS=/; printf '%s' "${guard_segs[*]-}")"
cpath="$guard_lead$(IFS=/; printf '%s' "${guard_cut[*]-}")"
shopt -s nocasematch

# Round 3: a segment with a ':' is judged both as written and cut at the ':' (evidence:foo is
# evidence/ to the second reading); either reading under evidence/ with a ':' is refused.
case "$cpath" in
  */evidence/*|evidence/*) [ "$guard_colon" -eq 1 ] && guard_unread "$path" "a ':' in a path under evidence/ (an NTFS stream)" ;;
esac
case "$npath" in
  */evidence/*|evidence/*)
    [ "$guard_colon" -eq 1 ] && guard_unread "$path" "a ':' in a path under evidence/ (an NTFS stream)"
    [ "$guard_lastdot" -eq 1 ] && guard_unread "$path" "a trailing dot or space on the file name under evidence/ (on Windows it names another file)"
    case "$npath" in
      # Narrative artifacts an agent legitimately authors during a gate.
      *.md) : ;;
      *) guard_shown=${path//[$'\001'-$'\037'$'\177']/?}  # no raw control characters (#62037)
         block "hand-editing generated evidence ($guard_shown). Regenerate it instead." "AU-9, CA-2" ;;
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
case "$npath" in
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
shopt -u nocasematch

# The verdict, and the last line of this file: a read cut anywhere before or inside it ends
# with no verdict, or with a command that does not exist, and blocks (TheHub #62264).
guard_allow
