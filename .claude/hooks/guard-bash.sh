#!/usr/bin/env bash
# PreToolUse hook for Bash and PowerShell (TheHub #61064) — enforces the agent constraints that must not depend on a
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

# TheHub #61843: PIN PATH. Every rule reads the command through grep, sed, awk, tr, cat
# and jq, looked up on PATH. A directory earlier on PATH that an agent can write to
# (~/bin, ~/.local/bin, a venv's bin) could hold a grep that always answers "no match" or
# a jq that prints nothing, and the hook would allow anything. A planted helper that exits
# 0 or 1 is not a fault, so #61794's wrappers cannot see it. So the hook finds its helpers
# only in the system's own directories:
#
#   Linux, macOS: /usr/bin:/bin:/usr/sbin:/sbin. Not /usr/local/bin: Homebrew on Intel
#                 Macs makes it user-writable. A jq installed only there is not found,
#                 and the hook reads the command with its sed fallback instead.
#   Git Bash:     /usr/bin:/bin:/mingw64/bin, Git for Windows' own tools. A jq from winget
#                 or scoop lives outside them, so the sed fallback runs there too.
#
# A helper missing from these directories exits 127, which the wrappers record as a fault,
# so the hook blocks rather than allows.
#
# The test seam: the hook tests run a COPY of this file with the one marked line below
# rewritten to name their shim directory. The live hook takes no override (no variable,
# flag or file), so nothing an agent sends or sets can widen its PATH.
case "${OSTYPE:-}" in
  msys*|cygwin*) guard_path="/usr/bin:/bin:/mingw64/bin" ;;
  *)             guard_path="/usr/bin:/bin:/usr/sbin:/sbin" ;;
esac
PATH="$guard_path"; export PATH  # guard-path-pin: the hook tests rewrite this line, and only it
hash -r
# TheHub #61973: A DEADLINE. Claude Code gives a hook 60 s and, when it runs out, lets
# the call PROCEED, so a hook that is merely slow fails open, whatever made it slow. Some
# command shapes still cost this hook seconds per kilobyte (one process start per helper,
# per segment, per view), and on a host where process starts are slow (Git Bash) a short
# command can reach the limit.
#
# So the hook runs as two processes. This one, the supervisor, reads nothing and decides
# nothing: it starts the guard (this same file, with --guard-worker) as a background job
# in a process group of its own, and starts a timer. When the guard finishes first, its
# verdict is passed on. When the timer fires first, the whole group (the guard and every
# helper it started) is killed and the call is BLOCKED. The guard's stdout is discarded and
# its stderr goes to a file that is printed at the end, so a helper that outlives the
# guard cannot hold Claude Code's pipes open past the deadline.
#
# A signal to the supervisor, or a guard that dies of one, is a block too (an exit of
# 128+N would be an allow). 40 s leaves room under the 60 s default for the supervisor
# itself; settings.json sets no shorter timeout. Commands over 1 MiB are refused without
# being read: nothing legitimate an agent runs is that long.
#
# The test seam: the hook tests rewrite the marked line in their copies to a short
# deadline. The live hook takes no override.
guard_deadline=40  # guard-deadline: the hook tests rewrite this line, and only it
guard_max_bytes=1048576
if [ "${1:-}" != "--guard-worker" ]; then
  # The supervisor's own stderr is fd 3; fd 2 is muted, so bash's job notices ("Killed")
  # never reach Claude Code.
  exec 3>&2 2>/dev/null
  guard_block() { # $1: why
    {
      echo "BLOCKED by .claude/hooks/guard-bash.sh — internal error: $1, so it cannot tell whether the command is allowed."
      echo ""
      echo "This is the guard failing closed (TheHub #61973), not a rule. Retry the call; if it"
      echo "keeps happening, split the command or report it: the host is short of time or resources."
    } >&3
  }
  guard_err="$(command mktemp 2>/dev/null)" || { guard_block "it cannot create its output file"; exit 2; }
  set -m
  # TheHub #62264: the guard proves it reached its verdict by writing this line, which no command
  # can predict, as the last line of its stderr; an exit 0 without it is a block.
  guard_nonce="guard-bash.sh verdict: allow $$.$RANDOM.$RANDOM"
  guard_nonce=$guard_nonce "$BASH" "${BASH_SOURCE[0]}" --guard-worker <&0 >/dev/null 2>"$guard_err" &
  guard_wpid=$!
  # The timer: USR1 at the deadline, USR2 at once if it cannot sleep (no timer, no verdict).
  ( if command sleep "$guard_deadline"; then kill -USR1 "$$"; else kill -USR2 "$$"; fi ) </dev/null >/dev/null 2>&1 &
  guard_tpid=$!
  set +m
  guard_stop() { kill -KILL -- "-$1" 2>/dev/null || kill -KILL "$1" 2>/dev/null; return 0; }
  guard_done() { # $1: exit status; $2: why it is a block, or empty to pass the guard's verdict on
    trap '' USR1 HUP INT TERM PIPE ALRM USR2
    guard_stop "$guard_tpid"
    [ -n "${2:-}" ] && guard_stop "$guard_wpid"
    # Builtins only: a broken cat must not hide the guard's own message.
    local guard_seen=0
    while IFS= read -r guard_line || [ -n "$guard_line" ]; do
      [ "$guard_line" = "$guard_nonce" ] && { guard_seen=1; continue; }
      printf '%s\n' "$guard_line" >&3
    done < "$guard_err"
    command rm -f "$guard_err" 2>/dev/null
    if [ -n "${2:-}" ]; then guard_block "$2"; exit 2; fi
    if [ "$1" -eq 0 ]; then
      [ "$guard_seen" -eq 1 ] || { guard_block "the guard ended without reaching its verdict (its file may have been rewritten while it started, TheHub #62264)"; exit 2; }
      # The settings entry allows only when this line is the hook's whole stdout (TheHub #62264), so a
      # run of this file that bash cut short, before this point, is a block too.
      printf '%s\n' "guard-verdict: allow"
    fi
    exit "$1"
  }
  trap 'guard_done 2 "it ran past its own deadline of ${guard_deadline} s"' USR1
  trap 'guard_done 2 "it cannot start its deadline timer (no sleep)"' USR2
  trap 'guard_done 2 "it was sent a signal"' HUP INT TERM PIPE ALRM
  wait "$guard_wpid"; guard_rc=$?
  case "$guard_rc" in
    0|2) guard_done "$guard_rc" ;;
    *)   guard_done 2 "the guard stopped with exit $guard_rc (a signal, or a crash) before its verdict" ;;
  esac
fi

# TheHub #61794: FAIL CLOSED. Every rule below reads the command through text tools
# inside $(...) captures and `printf ... | grep -q` tests, and nothing checked that
# they worked: a helper that errored or was killed left a capture empty, no rule
# matched, and the hook reached `exit 0`. On keel #176's Actions run that let KB-177
# (curl -T ... environments/production) through once; a failing `tr` alone is enough.
#
# Three things close it (test/hook-fail-closed.test.py holds each):
#
# 1. Helpers run through wrappers that record a real error in a fault file, and the
#    EXIT trap turns an allow into a block when the file holds one. Wrappers are
#    functions, so they reach every subshell, pipeline and capture. grep's 1 (no
#    match) is not a fault; neither is 141 (SIGPIPE), which also returns 0 so that
#    a writer whose reader stopped early never flips a pipeline's status.
#
# 2. No early exits. `grep -q` stops at its first match; under pipefail the writer
#    feeding it then dies of SIGPIPE and the pipeline reports 141, so a MATCH read
#    as "no match": a command padded past the pipe buffer (~64 KB) was ALLOWED
#    (review of #179). The grep wrapper drops -q and discards its output instead, and
#    head drains what it does not print, so every reader consumes all its input.
#
# 3. The hook allows only by exiting 0 and blocks only by exiting 2. Claude Code
#    treats any other code as a non-blocking error and runs the call, so the EXIT
#    trap makes every other code (an unbound variable, a failed fork, a crash) a
#    block. The fault file starts with a sentinel line, so one emptied or removed
#    behind the hook's back reads as a fault, not as "no faults".
guard_sentinel="guard-bash.sh fault file $$"
guard_faults="$(command mktemp 2>/dev/null)" \
  && printf '%s\n' "$guard_sentinel" > "$guard_faults" 2>/dev/null || {
  echo "BLOCKED by .claude/hooks/guard-bash.sh — internal error: cannot create its fault file, so it cannot tell whether its own checks ran. Retry the call." >&2
  exit 2
}
export guard_faults
# shellcheck disable=SC2317  # the wrappers are called indirectly, by name, from every rule below
guard_fault() { printf '%s exited %s\n' "$1" "$2" >> "$guard_faults" 2>/dev/null; }
guard_run() { # $1: tool, $2: highest exit status that is not an error; the rest: its args
  local t=$1 ok=$2 rc; shift 2
  command "$t" "$@"; rc=$?
  # TheHub #61973: 141 (SIGPIPE) is a fault too. Every wrapped helper drains its input
  # (grep and head above), so none is ever a writer whose reader stopped early, and an
  # extractor killed by SIGPIPE left an empty capture that read as "no match".
  [ "$rc" -gt "$ok" ] && guard_fault "$t" "$rc"
  return "$rc"
}
grep() { # -q (and --quiet/--silent) dropped, output discarded: grep reads all its input
  local a args=() quiet=0 opts=1
  guard_grep_ran=1   # grep_in reads this: grep ran (TheHub #62258)
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
head() { guard_run head 0 "$@"; command cat >/dev/null 2>&1; return 0; }
sed()     { guard_run sed 0 "$@"; }
awk()     { guard_run awk 0 "$@"; }
tr()      { guard_run tr 0 "$@"; }
cat()     { guard_run cat 0 "$@"; }
# shellcheck disable=SC2317  # wrapped for when a rule calls it
cut()     { guard_run cut 0 "$@"; }
jq()      { guard_run jq 0 "$@"; }
# shellcheck disable=SC2317  # wrapped for when a rule calls it (TheHub #62031)
git()     { guard_run git 0 "$@"; }
# shellcheck disable=SC2317  # wrapped for when a rule calls it
python3() { guard_run python3 0 "$@"; }
# shellcheck disable=SC2317  # wrapped for when a rule calls it
python()  { guard_run python 0 "$@"; }
# TheHub #62258: grep_nl TEXT ARGS... is `printf '%s\n' "$TEXT" | grep ARGS...`, and grep_in
# TEXT ARGS... is `printf '%s' "$TEXT" | grep ARGS...`, each with the same verdict and output
# and one process instead of three. A pipeline forks a subshell for each side before grep
# starts, and most rules below are one such pipeline per view, so on a host where a fork is
# slow (Git Bash) the pipelines were most of this hook's time.
#
# The text goes to grep as a here-string: exactly the text and one newline, which is what
# printf '%s\n' writes. grep reads input that does not end in a newline as if it did, so for
# printf '%s' the here-string gives grep the same lines whenever the text is not empty and
# does not already end in one. Text that is empty, or ends in a newline, would gain an empty
# line there (a -v or -c would see it), so grep_in takes the pipeline for it, as before.
# A here-string bash cannot set up never runs grep and would read as "no match", so it is
# recorded as a fault.
grep_nl() { # $1: the text; the rest: grep's arguments
  local guard_t=$1 guard_rc; shift
  guard_grep_ran=0
  grep "$@" <<<"$guard_t"; guard_rc=$?
  [ "$guard_grep_ran" -eq 1 ] || guard_fault "here-string" "$guard_rc"
  return "$guard_rc"
}
grep_in() { # $1: the text; the rest: grep's arguments
  case "$1" in
    ''|*$'\n') local guard_t=$1; shift; printf '%s' "$guard_t" | grep "$@"; return ;;
  esac
  grep_nl "$@"
}
# TheHub #62258: g_lit LITERAL ERE is g ERE (below) for an ERE that can only match text
# holding LITERAL, a word every match must contain (git, /pulls/, --approve). A command
# without that word cannot match, so the test is answered in the shell, with no grep: most
# rules name a word most commands never hold. Name only a word the ERE cannot match
# without: not one inside an optional group or one side of an alternation, and never for a
# case-insensitive (-i) rule.
g_lit() { # $1: the literal; $2: the extended regex, read against $cmd
  [[ $cmd == *"$1"* ]] || return 1
  grep_in "$cmd" -qE "$2"
}
# shellcheck disable=SC2317  # run by the EXIT trap
guard_exit() { # builtins only: a broken helper must not be able to hide its own fault
  local rc=$? why="" lines=()
  [ -f "$guard_faults" ] && mapfile -t lines < "$guard_faults" 2>/dev/null
  if [ "$rc" -ne 2 ]; then
    if [ "${#lines[@]}" -eq 0 ] || [ "${lines[0]}" != "$guard_sentinel" ]; then
      why="its fault file was emptied or removed while it ran"
    elif [ "${#lines[@]}" -gt 1 ]; then
      why="a helper it reads the command with failed (${lines[*]:1:3})"
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
      echo "BLOCKED by .claude/hooks/guard-bash.sh — internal error: $why, so it cannot tell whether the command is allowed."
      echo ""
      echo "This is the guard failing closed (TheHub #61794), not a rule. Retry the call; if it"
      echo "keeps happening, the host is short of a tool or of resources."
    } >&2
    exit 2
  fi
  [ "$rc" -eq 0 ] && [ -n "${guard_nonce:-}" ] && printf '%s\n' "$guard_nonce" >&2
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
if [ "${#payload}" -gt "$guard_max_bytes" ]; then
  echo "BLOCKED by .claude/hooks/guard-bash.sh — the command is over $guard_max_bytes bytes, which this guard does not read (TheHub #61973). Write long content to a file with the Write tool and run a short command on it." >&2
  exit 2
fi

# Decode a JSON string body (the sed fallback below hands over the raw escapes).
# TheHub #61978: \uXXXX is decoded too, to UTF-8 (a surrogate pair to one character), as
# jq decodes it. Left as it was, `gh\u0020pr\u0020merge` reached the rules as text that no
# rule reads, while jq saw `gh pr merge`. U+0000 becomes a space; a malformed escape stays.
read -r -d '' json_unescape_awk <<'AWK'
function guard_hex(h,  k, v, x) {
  v = 0
  for (k = 1; k <= 4; k++) {
    x = index("0123456789abcdef", tolower(substr(h, k, 1)))
    if (x == 0) return -1
    v = v * 16 + x - 1
  }
  return v
}
function guard_utf8(v) {
  if (v == 0) return " "
  if (v < 128) return sprintf("%c", v)
  if (v < 2048) return sprintf("%c%c", 192 + int(v / 64), 128 + v % 64)
  if (v < 65536) return sprintf("%c%c%c", 224 + int(v / 4096), 128 + int(v / 64) % 64, 128 + v % 64)
  return sprintf("%c%c%c%c", 240 + int(v / 262144), 128 + int(v / 4096) % 64, 128 + int(v / 64) % 64, 128 + v % 64)
}
function guard_join(lo, hi,  m) { if (lo == hi) return guard_line[lo]; m = int((lo + hi) / 2); return guard_join(lo, m) "\n" guard_join(m + 1, hi) }
{ guard_line[NR] = $0 }
END {
  s = (NR > 0) ? guard_join(1, NR) : ""
  n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\\" && i < n) {
      d = substr(s, ++i, 1)
      if (d == "n") c = "\n"; else if (d == "t") c = "\t"; else if (d == "r") c = "\r"
      else if (d == "u") {
        v = (i + 4 <= n) ? guard_hex(substr(s, i + 1, 4)) : -1
        if (v < 0) c = "\\u"
        else {
          i += 4
          if (v >= 55296 && v < 56320 && substr(s, i + 1, 2) == "\\u" && (w = guard_hex(substr(s, i + 3, 4))) >= 56320 && w < 57344) {
            v = 65536 + (v - 55296) * 1024 + (w - 56320); i += 6
          }
          if (v == 0) guard_nul = 1   # a real \u0000 escape (review of #196, round 2)
          c = guard_utf8(v)
        }
      }
      else if (d == "b" || d == "f") c = " "; else c = d
    }
    printf "%s", c
  }
  exit guard_nul ? 3 : 0
}
AWK

# TheHub #62258 review (B1): the state the reads below fill in on first use starts empty here.
# Inherited from the environment, guard_cwd_read=1 with a payload_cwd of the caller's choosing
# skipped the payload's own cwd, so a push of the current branch from a checkout on main read
# as a push from a feature branch. Nothing the hook reads lazily may come from outside it.
guard_cwd_read=""; payload_cwd=""; tool_name=""; guard_grep_ran=0

# Extract the command. Prefer jq; fall back to a tolerant sed for environments without it.
# `type -P`, not `command -v`: jq() is a wrapper function now (#61794), and `command -v`
# would report it even where no jq binary exists.
if type -P jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')"
  # TheHub #62258: the tool name and the cwd are read when the hook first needs them, not
  # here: a command a rule blocks first never pays for them, and where jq is a python shim
  # each call is an interpreter start. The same input gives the same parse, so a payload jq
  # cannot read still faults at the command, above.
  guard_read_tool_name() { tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)" || tool_name=""; }
  guard_read_cwd() { payload_cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty')"; }
else
  # TheHub #61038 review: take the JSON string itself (not everything up to the
  # payload's last quote, which swallowed the "description" field) and decode it, so
  # this mode sees the command jq would. Undecoded, \" is not a quote and \n is not a
  # newline, and the quote-aware view below could not tell what is quoted.
  # TheHub #61978: in the C locale, so a byte that is not valid in the host's locale still
  # matches [^"\\] instead of ending the match.
  # Review of #196 (round 1), each refused rather than read differently from jq:
  #   - a payload over 256 KB: the fallback cannot judge it inside the budget on a slow host
  #     (a 1 MB command ran past 10 minutes on Git Bash, which is past the hook timeout, which
  #     allows), so with no jq it is refused as too large to judge;
  #   - whitespace between the key, the colon and the value may include a newline: a newline
  #     outside a string is JSON whitespace, so the payload is read as one line;
  #   - more than one "command" key anywhere (a sibling or nested object, or a key that ends
  #     in an escaped quote and command): sed and jq would pick different ones;
  #   - \u0000 in the value: the command jq passes on cannot be rebuilt here.
  guard_nojq_refuse() {
    echo "BLOCKED by .claude/hooks/guard-bash.sh — internal error: $1 with no jq here, so this hook cannot tell whether the command is allowed. Installing jq gives this hook a full JSON parser (TheHub #61978)." >&2
    exit 2
  }
  guard_len="$(LC_ALL=C; printf '%s' "${#payload}")"   # bytes, not characters (round 2)
  [ "$guard_len" -gt 262144 ] && guard_nojq_refuse "the hook payload is over 256 KB, too large to judge"
  payload_flat="$(printf '%s' "$payload" | LC_ALL=C tr '\n\r' '  ')"
  # A key is a quoted "command" whose closing quote is not escaped and is followed by a colon;
  # the opening quote may be escaped (the end of a key like "x\"command"). Text in a value
  # (\"command\") is neither.
  # Round 2: each letter in either spelling (c or \u0063, ...), so a \u-escaped key is counted
  # too, and any key not spelled plainly is refused. An escaped backslash before the u is a
  # different key and does not match.
  guard_kp='\\?"(c|\\u0063)(o|\\u006[fF])(m|\\u006[dD])(m|\\u006[dD])(a|\\u0061)(n|\\u006[eE])(d|\\u0064)"[[:space:]]*:'
  guard_keys="$(printf '%s' "$payload_flat" | LC_ALL=C grep -oE "$guard_kp" | LC_ALL=C grep -c .)"
  [ "${guard_keys:-0}" -gt 1 ] && guard_nojq_refuse "the hook payload names more than one \"command\" key"
  printf '%s' "$payload_flat" | LC_ALL=C grep -oE "$guard_kp" | LC_ALL=C grep -qvE '^"command"[[:space:]]*:' \
    && guard_nojq_refuse "the hook payload spells its \"command\" key with escapes"
  LC_ALL=C grep_in "$payload_flat" -qE '\\"command"[[:space:]]*:' \
    && guard_nojq_refuse "the hook payload has a key ending in an escaped quote and \"command\""
  cmd="$(printf '%s' "$payload_flat" | LC_ALL=C sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p')"
  # TheHub #62258: the cwd and the tool name are read on first use, as in the jq branch.
  guard_read_cwd() { payload_cwd="$(printf '%s' "$payload" | sed -nE 's/.*"cwd"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | sed 's/\\\\/\\/g')"; }
  cmd_json="$cmd"
  cmd="$(printf '%s' "$cmd_json" | LC_ALL=C awk "$json_unescape_awk" 2>/dev/null)"; guard_rc=$?
  # Round 2: the decoder itself says whether the value held a real \u0000 escape. A text match
  # refused a command holding the literal text (an escaped backslash, then u0000).
  [ "$guard_rc" -eq 3 ] && guard_nojq_refuse "the command holds a \\u0000 escape"
  [ "$guard_rc" -eq 0 ] || cmd="$cmd_json"
  guard_read_tool_name() { tool_name="$(printf '%s' "$payload" | sed -nE 's/.*"tool_name"[[:space:]]*:[[:space:]]*"([A-Za-z]+)".*/\1/p')"; }
  # TheHub #61978 / #62016: jq refuses a payload it cannot parse, and the wrapper makes that a
  # block. This fallback read the same payload as "no command" and allowed it. So, with
  # nothing extracted: a payload that names a non-empty command, or that does not end in a
  # closing brace (truncated), is refused here too.
  if [ -z "$cmd" ]; then
    guard_tail="${payload%"${payload##*[![:space:]]}"}"
    if LC_ALL=C grep_in "$payload_flat" -qE '"command"[[:space:]]*:[[:space:]]*"[^"]' || [ "${guard_tail: -1}" != "}" ]; then
      echo "BLOCKED by .claude/hooks/guard-bash.sh — internal error: it cannot parse the hook payload (no jq here, and the fallback parser could not read the command), so it cannot tell whether the command is allowed. Retry the call; installing jq gives this hook a full JSON parser (TheHub #61978)." >&2
      exit 2
    fi
  fi
fi

[ -z "$cmd" ] && guard_allow

# TheHub #61038 review: a backslash-newline continues the command, for every command.
# This was done for curl only, so `gh api --method POST \<newline> .../pending_deployments`
# put the endpoint on a line of its own, which no gh api rule read.
tag_src=$cmd   # the release-tag guard splits words itself; bash deletes a backslash-newline (round 2)
cmd=${cmd//$'\\\n'/ }

# TheHub #61038 review: the same binary under another name. curl.exe is the natural
# spelling on Windows; /usr/bin/curl, \curl (which skips an alias) and
# "C:\Program Files\GitHub CLI\gh.exe" are the others. Each rule names gh, git or curl
# after the $B boundary, so write those back to the bare name first. A path that
# merely ends in /gh becomes "gh" too, which only matters if the rest of the line is
# a blocked call.
#
# Second review: the name is matched in any case. Windows file names are not
# case-sensitive, so GH, Gh.exe and CURL run gh and curl. And a gh alias body is a
# gh command: `gh alias set ok 'api -X POST .../pending_deployments ...'` makes a plain
# `gh ok` approve, so the body is rewritten to start with "gh" and every gh rule reads
# it (`gh alias set m 'pr merge'` too). A --shell body that already starts with gh
# becomes "gh gh ...", which the rules read the same way.
norm=()
# TheHub #61385 review: docker too (docker.exe, /usr/bin/docker, docker-compose.exe).
for pair in 'gh:[Gg][Hh]' 'git:[Gg][Ii][Tt]' 'curl:[Cc][Uu][Rr][Ll]' 'docker:[Dd][Oo][Cc][Kk][Ee][Rr]' \
            'docker-compose:[Dd][Oo][Cc][Kk][Ee][Rr]-[Cc][Oo][Mm][Pp][Oo][Ss][Ee]'; do
  name=${pair%%:*}; pat=${pair#*:}
  # TheHub #61987: the bare name is ADDED after the word, never put in its place. Replacing
  # it ate any argument whose last path segment is one of these names: an endpoint such as
  # repos/O/R/contents/bin/gh became "gh", and the contents rule never saw /contents/.
  # Rewriting only in command position instead would miss a binary path after any wrapper
  # not on a fixed list (timeout 5 /usr/bin/gh ...). So the word stays and the name follows
  # it, which every rule reads; a bare, lower-case name is left alone.
  norm+=(-e 's#"([^"]*[/\\])?'"$pat"'(\.[Ee][Xx][Ee])?"#& '"$name"'#g'
         -e "s#'([^']*[/\\\\])?$pat(\\.[Ee][Xx][Ee])?'#& $name#g"
         -e 's#(^|[|;&[:space:](`"'"'"'])(\\?([^[:space:]|;&()`"'"'"'<>]*[/\\])?'"$pat"'(\.[Ee][Xx][Ee])?)([[:space:])`"'"'"'|;&]|$)#\1\2 '"$name"'\5#g'
         -e 's#(^|[|;&[:space:](`"'"'"'])'"$name $name"'([[:space:])`"'"'"'|;&]|$)#\1'"$name"'\2#g')
done
# Review of #198 (B2): the alias name may itself be a binary's name (gh alias set Git ...),
# and the loop above appended the bare name after it; skip that word, so the BODY is what
# gets "gh " in front of it.
norm+=(-e 's#(gh[[:space:]]+alias[[:space:]]+set([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^[:space:]-][^[:space:]]*[[:space:]]+((gh|git|curl|docker|docker-compose)[[:space:]]+)?)(["'"'"']?)#\1\5gh #g')
normalize() { sed -E "${norm[@]}"; }
cmd="$(printf '%s' "$cmd" | normalize)"

# TheHub #61038 review: a | ; & or newline inside quotes is text, not a separator. The
# rules cut a command into invocations on those characters ([^|;&]* and tr '|;&'), so
# `gh api -X POST -f 'comment=a;b' .../pending_deployments` was two invocations, one
# with the method and one with the endpoint, and neither matched.
#
# This prints the command with every such character that bash would NOT treat as a
# separator -- quoted ('...', "...", $'...'), escaped, in a comment -- turned into a
# space. Quoting inside $(...) and backticks is followed, including inside double
# quotes, and heredoc bodies are copied unchanged.
#
# Quoted text can also BE a command (sh -c '...; ...'), and there the quoted separators
# are real. So every rule runs twice, on the command as written and on a second view
# built from this one (dequote_awk, below), and either can block. A deny rule is
# allowed to be judged on both readings.
read -r -d '' mask_awk <<'AWK'
function guard_join(lo, hi,  m) { if (lo == hi) return guard_line[lo]; m = int((lo + hi) / 2); return guard_join(lo, m) "\n" guard_join(m + 1, hi) }
# The position of the first newline at or after i, or n + 1 when there is none. i only
# moves forward, so a cursor over the newline positions makes every call O(1) amortized.
# index(substr(s, i), "\n") copied the rest of the command at every comment line and
# here-document line: quadratic (TheHub #61939).
function guard_nextnl(i) { while (guard_nc <= NR && guard_nl[guard_nc] < i) guard_nc++; return guard_nl[guard_nc] }
{ guard_line[NR] = $0 }
END {
  s = (NR > 0) ? guard_join(1, NR) : ""
  guard_p = 0; guard_nc = 1
  for (k = 1; k <= NR; k++) { guard_p += length(guard_line[k]) + 1; guard_nl[k] = guard_p }
  guard_nl[NR + 1] = length(s) + 1
  n = length(s); q = ""; nh = 0; ws = 1; dp = 0; i = 1
  while (i <= n) {
    c = substr(s, i, 1)
    if (q == "" || q == "\"") {
      if (c == "$" && substr(s, i + 1, 1) == "(") {
        sv[++dp] = q; ft[dp] = "("; pc[dp] = 1; q = ""
        printf "%s", "$("; i += 2; ws = 1; continue
      }
      if (c == "`") {
        if (q == "" && dp > 0 && ft[dp] == "`") q = sv[dp--]
        else { sv[++dp] = q; ft[dp] = "`"; q = "" }
        printf "%s", c; i++; ws = 1; continue
      }
    }
    if (q == "") {
      if (c == "\\") {
        d = substr(s, i + 1, 1)
        printf "%s", ((d == "\n" || d == "|" || d == ";" || d == "&") ? "  " : c d)
        i += 2; ws = 0; continue
      }
      if (c == "#" && ws) {
        j = guard_nextnl(i) - i + 1
        t = substr(s, i, j - 1); gsub(/[|;&]/, " ", t)
        printf "%s", t; i += j - 1; continue
      }
      if (dp > 0 && ft[dp] == "(" && c == "(") pc[dp]++
      if (dp > 0 && ft[dp] == "(" && c == ")" && --pc[dp] == 0) {
        q = sv[dp--]; printf "%s", c; i++; ws = 0; continue
      }
      if (c == "'") q = (i > 1 && substr(s, i - 1, 1) == "$") ? "$" : "'"
      else if (c == "\"") q = "\""
      else if (c == "<" && substr(s, i, 3) ~ /^<<[^<]/) {
        r = substr(s, i + 2, guard_nextnl(i) - i - 2); hdash = (substr(r, 1, 1) == "-")
        if (hdash) r = substr(r, 2)
        sub(/^[ \t]*/, "", r)
        if (match(r, /^["'\\]?[A-Za-z0-9_.-]+["']?/)) {
          w = substr(r, 1, RLENGTH); gsub(/["'\\]/, "", w)
          hw[++nh] = w; hd[nh] = hdash
        }
      }
      else if (c == "\n" && nh > 0) {
        printf "%s", c; i++
        for (k = 1; k <= nh && i <= n; k++) {
          while (i <= n) {
            j = guard_nextnl(i); line = substr(s, i, j - i); j = (j <= n)
            printf "%s", line; i += length(line)
            if (j > 0) { printf "%s", "\n"; i++ }
            t = line; if (hd[k]) sub(/^\t+/, "", t)
            if (t == hw[k]) break
          }
        }
        nh = 0; ws = 1; continue
      }
      ws = (c == " " || c == "\t" || c == "\n" || c == ";" || c == "&" || c == "|" || c == "(")
      printf "%s", c; i++; continue
    }
    if (c == "\\" && q != "'") {
      d = substr(s, i + 1, 1)
      printf "%s", c ((d == "\n" || d == "|" || d == ";" || d == "&") ? " " : d)
      i += 2; continue
    }
    if ((q == "\"" && c == "\"") || (q != "\"" && c == "'")) q = ""
    else if (c == "|" || c == ";" || c == "&" || c == "\n") c = " "
    printf "%s", c; i++
  }
}
AWK
masked_cmd="$(printf '%s' "$cmd" | LC_ALL=C awk "$mask_awk" 2>/dev/null)" || masked_cmd="$cmd"

# TheHub #61038 second review: bash also removes quotes and backslashes INSIDE a word
# before the program sees it. -X P""OST, -X PO\ST and -X $'POST' are POST;
# pending"_"deployments and 'repos/.../'pending_deployments are the endpoint; g''h and
# c\url are gh and curl. The rules matched the text as written and missed all of them,
# in every rule (P""UT .../merge, --for''ce).
#
# So the second view is the masked one with the quoting removed: $'...' read as '...',
# quote characters deleted, and \x read as x outside single quotes. It is the words
# as bash passes them, joined by spaces, with only real separators left between them.
# It keeps everything the masked view caught (a quote was only ever a boundary, and a
# space is one too), so the rules run on the command as written and on this view.
read -r -d '' dequote_awk <<'AWK'
function guard_join(lo, hi,  m) { if (lo == hi) return guard_line[lo]; m = int((lo + hi) / 2); return guard_join(lo, m) "\n" guard_join(m + 1, hi) }
{ guard_line[NR] = $0 }
END {
  s = (NR > 0) ? guard_join(1, NR) : ""
  n = length(s); q = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q == "'") { if (c == "'") q = ""; else printf "%s", c; continue }
    if (c == "\\" && i < n) { printf "%s", substr(s, ++i, 1); continue }
    if (q == "$") { if (c == "'") q = ""; else printf "%s", c; continue }
    if (q == "" && c == "$" && substr(s, i + 1, 1) == "'") { q = "$"; i++; continue }
    if (q == "" && c == "'") { q = "'"; continue }
    if (c == "\"") { q = (q == "\"") ? "" : "\""; continue }
    printf "%s", c
  }
}
AWK
word_cmd="$(printf '%s' "$masked_cmd" | LC_ALL=C awk "$dequote_awk" 2>/dev/null | normalize)" || word_cmd="$masked_cmd"
raw_cmd="$cmd"

# TheHub #61064: the PowerShell tool. Claude Code sends a PowerShell command to this
# hook as tool_input.command, just as it sends a Bash one, and settings.json binds this
# hook to both tools. PowerShell reads the same text differently, so a third view is
# built from the command the way PowerShell passes its words:
#   - the escape character is the backtick, not the backslash: g`h is gh, --f`orce is
#     --force, and a backtick at the end of a line continues the command;
#   - '' inside '...' and "" (or `") inside "..." are a literal quote, and a | ; & or
#     newline inside either is text, as the masked view treats them;
#   - { and } (a script block, &{gh pr merge 1}) and , (an argument list,
#     'pr','merge') separate words;
#   - Start-Process gh -ArgumentList ... runs gh with those arguments, so the cmdlet and
#     its -FilePath / -ArgumentList names are dropped and what is left is the gh call.
# keel#166 review: PowerShell's own escaping, read the way PowerShell reads it.
#   - a quote is not a word boundary: PowerShell joins adjacent bare and quoted
#     fragments into one argument, so `m"erge" and m"er"`ge are both merge. A quote
#     emits nothing here (the raw view still reads a quote as a boundary);
#   - 'a' + "b", two literals joined by +, is one string: ('.../12/' + 'merge');
#   - inside "...", `t `n `r `f `v are whitespace and `u{hex} is that character, so
#     iex "gh pr`tmerge 12" and iex "gh pr `u{6d}erge 12" are gh pr merge 12;
#   - --% (stop parsing) hands the rest of the line to the native command verbatim,
#     so the token is dropped: gh --% pr merge 12 is gh pr merge 12;
#   - (Get-Command gh), (gcm gh) and (gcm gh).Source name gh, as gh.exe does.
# The view only ever adds a reading: a rule that blocks on any view blocks the call,
# whichever tool sent it.
read -r -d '' ps_awk <<'AWK'
function guard_join(lo, hi,  m) { if (lo == hi) return guard_line[lo]; m = int((lo + hi) / 2); return guard_join(lo, m) "\n" guard_join(m + 1, hi) }
{ guard_line[NR] = $0 }
END {
  s = (NR > 0) ? guard_join(1, NR) : ""
  n = length(s); q = ""; dp = 0; i = 1
  while (i <= n) {
    c = substr(s, i, 1)
    if (q != "'" && c == "`") {
      d = substr(s, i + 1, 1)
      if (d == "\r" && substr(s, i + 2, 1) == "\n") { printf "%s", " "; i += 3; continue }
      if (q == "\"" && (d == "t" || d == "n" || d == "r" || d == "f" || d == "v")) { printf "%s", " "; i += 2; continue }
      if (q == "\"" && d == "u" && substr(s, i + 2, 1) == "{") {
        j = i + 3; v = 0
        while (j <= n && (h = index("0123456789abcdef", tolower(substr(s, j, 1)))) > 0) { v = v * 16 + h - 1; j++ }
        if (j > i + 3 && substr(s, j, 1) == "}") {
          printf "%s", ((v > 32 && v < 127) ? sprintf("%c", v) : " "); i = j + 1; continue
        }
      }
      printf "%s", ((d == "\n" || d == "|" || d == ";" || d == "&") ? " " : d)
      i += 2; continue
    }
    if ((q == "" || q == "\"") && c == "$" && substr(s, i + 1, 1) == "(") {
      sv[++dp] = q; pc[dp] = 1; q = ""; printf "%s", "$("; i += 2; continue
    }
    if (q == "") {
      if (dp > 0 && c == "(") pc[dp]++
      if (dp > 0 && c == ")" && --pc[dp] == 0) { q = sv[dp--]; printf "%s", c; i++; continue }
      if (c == "'" || c == "\"") { q = c; i++; continue }
      if (c == "-" && substr(s, i, 3) == "--%" && (i == 1 || index(" \t\n", substr(s, i - 1, 1)) > 0) \
          && (i + 3 > n || index(" \t\r\n", substr(s, i + 3, 1)) > 0)) { printf "%s", " "; i += 3; continue }
      if (c == "{" || c == "}" || c == ",") c = " "
      printf "%s", c; i++; continue
    }
    if (c == q) {
      if (substr(s, i + 1, 1) == q) { printf "%s", q; i += 2; continue }
      j = i + 1
      while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
      if (substr(s, j, 1) == "+") {
        j++
        while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
        k = substr(s, j, 1)
        if (k == "'" || k == "\"") { q = k; i = j + 1; continue }
      }
      q = ""; i++; continue
    }
    if (c == "|" || c == ";" || c == "&" || c == "\n") c = " "
    printf "%s", c; i++
  }
}
AWK
ps_sed=(-e 's#(^|[[:space:](])([Ss][Tt][Aa][Rr][Tt]-[Pp][Rr][Oo][Cc][Ee][Ss][Ss]|[Ss][Aa][Pp][Ss]|[Ss][Tt][Aa][Rr][Tt])([[:space:]]+-[Ff][A-Za-z]*)?[[:space:]]+#\1#g'
        -e 's#[[:space:]]-[Aa][Rr][Gg][A-Za-z]*([[:space:]]|$)# #g'
        -e 's#\(([Gg][Ee][Tt]-[Cc][Oo][Mm][Mm][Aa][Nn][Dd]|[Gg][Cc][Mm])([[:space:]]+-[A-Za-z]+)*[[:space:]]+([^()[:space:]]+)([[:space:]]+(gh|git|curl|docker|docker-compose))*[[:space:]]*\)(\.[A-Za-z]+)?# \3 \5 #g')
# TheHub #62258: ps_sed and norm are s commands only, each applied to one line at a time, so
# one sed running both lists in turn writes what `sed ps_sed | normalize` wrote, in one process.
ps_cmd="$(printf '%s' "$raw_cmd" | LC_ALL=C awk "$ps_awk" 2>/dev/null | sed -E "${ps_sed[@]}" "${norm[@]}")" || ps_cmd="$raw_cmd"

block() {
  echo "BLOCKED by .claude/hooks/guard-bash.sh — $1" >&2
  echo "" >&2
  echo "This is a process control ($2), not a suggestion. Do not work around it." >&2
  echo "If the control is genuinely wrong, that is a process change: open an issue" >&2
  echo "labelled 'process' and use /learn. See CLAUDE.md § When the process is wrong." >&2
  exit 2
}

# What may stand immediately before a command name for a rule to count it as invoked.
# Every rule below starts with "$B"; change the boundary here, never per rule.
#
# #117: this was (^|[|;&[:space:]]), written out in every rule. A command inside
# $(...), <(...) or backticks is preceded by ( or a backtick, and one inside
# bash -c "..." or sh -c '...' by a quote. None of those was in the set, so the
# same call that was blocked bare -- x=$(gh api --method PUT .../merge) -- matched
# no rule at all, git and credential-read rules included. A quote counts as a
# boundary for the same reason, at the cost of also matching a quoted mention
# that starts with the command name ("gh pr merge ..."); an unquoted mention
# was already matched, so that adds no new kind of false positive.
B='(^|[|;&[:space:](`"'"'"'])'
# And what may END an argument a rule anchors on (a branch name, a flag, a path):
# the same substitution and quote wrappers close with ), a backtick or a quote, so
# `x=$(git push origin main)` ends in "main)" and is still a push to main.
E='([[:space:])`"'"'"']|$)'

# Every rule below reads $cmd. guard() runs them all once per view of the command (see
# word_cmd above); the body is left at the top level's indentation so its history
# stays readable.
guard() {

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
if g_lit --no-verify "$B"'git[[:space:]]+[^|;&]*(commit|push|merge)[^|;&]*[[:space:]]--no-verify\b' \
   || g_lit git "$B"'git[[:space:]]+(commit|push)[[:space:]]+[^|;&]*[[:space:]]-[a-zA-Z]*n([[:space:])`"'"'"';|&<>]|$)' \
   || grep_in "$cmd" -qiE "$B"'git[[:space:]]+([^|;&]*[[:space:]])?-c[[:space:]]*core[.]hookspath='; then
  block "hook bypass (--no-verify / -n on a git commit). Fix the cause the hook found." "AIC-3, IA-5"
fi

# ── SYSTEMATIC PASS 2026-08-08 (L0008, third recurrence) ────────────────────
# Every rule below was a loose `case` glob and every one over-matched. The last was:
#     *"push"*"origin"*"main"*
# which blocked `echo "...force-push..." && git ls-remote origin main` — a READ-ONLY
# command — because the three substrings happened to appear in that order anywhere.
#
# Point-fixing them one at a time produced three separate false positives across two days.
# All rules are now anchored to an actual command invocation via a shared matcher.
# When adding a rule here: anchor it, and add BOTH a must-block and a must-allow case to
# selftest.sh. GP-5.
g() { # g <extended-regex> -> true if the command actually invokes this
  grep_in "$cmd" -qE "$1"
}

# TheHub #61038 second review: `gh alias import FILE` defines aliases from a YAML file,
# one `name: body` per line. Each body is a gh command (or `!gh ...` for a shell
# alias), so it is read and judged with the rest; a file this hook cannot read (stdin,
# a missing file) is refused. `gh alias set` is handled in normalize() above.
if g_lit import "$B"'gh[[:space:]]+alias[[:space:]]+import\b'; then
  af=$(printf '%s' "$cmd" | grep -oE "$B"'gh[[:space:]]+alias[[:space:]]+import([[:space:]]+--?[a-z-]+)*[[:space:]]+[^[:space:]|;&)`"'"'"'-][^[:space:]|;&)`"'"'"']*|'"$B"'gh[[:space:]]+alias[[:space:]]+import([[:space:]]+--?[a-z-]+)*[[:space:]]+-'"$E" \
    | head -n1 | sed -E 's/[[:space:])`"'"'"']+$//; s/.*[[:space:]]//')
  if [ -z "$af" ] || [ "$af" = "-" ] || [ ! -r "$af" ]; then
    block "importing gh aliases this hook cannot read (${af:-no file}). An alias body is a gh command; define it with gh alias set, where it can be read." "AC-5, AIC-2"
  fi
  cmd="$cmd
$(sed -E 's/^[[:space:]]*[^:#[:space:]]+:[[:space:]]*["'"'"']?!?/gh /' -- "$af" | normalize)"
fi

# Destructive git
# #120: the flag may come straight after push. `push([[:space:]]|$)` used to eat the one
# space in front of it, so `git push --force origin feat` passed.
g_lit push "$B"'git[[:space:]]+([^|;&]*[[:space:]])?push[[:space:]]([^|;&]*[[:space:]])?--?(force|f)(-with-lease)?\b' \
  && block "force push. Published history is immutable — it is the AU-12 audit trail." "AIC-3, AU-12, SI-7"
g_lit --hard "$B"'git[[:space:]]+([^|;&]*[[:space:]])?reset([[:space:]]|$)[^|;&]*--hard\b' \
  && block "git reset --hard. Discards work irrecoverably; use git revert or a branch." "AIC-3"
g_lit filter- "$B"'git[[:space:]]+(filter-branch|filter-repo)\b' \
  && block "history rewrite. Destroys the attributable, signed commit record." "AU-12, SI-7"
# TheHub #62031: an argument here ends at a separator or a redirect too (; & | < >), so
# `git push origin main;echo` is a push to main. The refspec, +, every-branch, ':',
# -c push.* and send-pack rules are read as shell words in push_judge below (review round 2:
# a regex over the line lost them behind a quoted global option such as -C "my dir").
EP='([[:space:])`"'"'"';|&<>]|$)'
g_lit push "$B"'git[[:space:]]+([^|;&]*[[:space:]])?push([[:space:]]+[^|;&]*)?[[:space:]](origin[[:space:]]+)?(HEAD:)?(main|master)'"$EP" \
  && block "direct push to main. All change goes through a reviewed PR." "AC-5, CM-5"
g_lit commit "$B"'git[[:space:]]+([^|;&]*[[:space:]])?commit[[:space:]]([^|;&]*[[:space:]])?-[aeiopqsvzn]*n[a-zA-Z]*'"$EP" \
  && block "hook bypass (-n on a git commit, alone or in a cluster of flags). Fix the cause the hook found." "AIC-3, IA-5"

# Self-approval and self-merge — the control that makes every gate meaningful
g_lit --approve "$B"'gh[[:space:]]+pr[[:space:]]+review\b[^|;&]*--approve\b' \
  && block "approving a PR. Agents recommend; a human or a separate identity approves." "AC-5, AIC-2"
g_lit merge "$B"'gh[[:space:]]+pr[[:space:]]+merge\b' \
  && block "merging a PR. Merge happens after independent review, via GitHub." "AC-5, CM-5, AIC-2"
g_lit release "$B"'gh[[:space:]]+release[[:space:]]+(create|edit|delete)\b' \
  && block "creating a release. G5 requires human authorization via the Environment." "CM-3, AIC-1"

# Weakening a security control
g_lit continue-on-error: 'continue-on-error:[[:space:]]*true' \
  && block "setting continue-on-error on a check. Relaxing a gate is a visible process change." "CM-5, AIC-3"
# -- gh api reaches every endpoint the named subcommands do -------------------
# The rules above block `gh pr merge`, `gh pr review --approve` and
# `gh release create` by name. `gh api` reaches the same REST endpoints and is
# on the permission ALLOW-list, so those controls were enforced against one
# spelling of an action rather than against the action.
#
# This file already knew that -- it defended exactly one endpoint, branch
# protection. That makes the rest an oversight of scope rather than of
# awareness, and it means the pattern to follow was already here. Two things
# had to change together:
#
#   1. The method was matched as `-X DELETE` only, so `--method DELETE` (the
#      documented long form) and `-XDELETE` (ordinary short-flag packing) both
#      walked past the one control protecting separation of duties.
#   2. Merge, self-approve, release and secrets had no REST-side rule at all.
#
# Matched on endpoint and effect, never on flag spelling. GP-5: every rule
# below has a must-block AND a must-allow case in selftest.sh.
#
# GET is deliberately untouched, and a blanket deny on write methods would be
# wrong in both directions. It would block filing an issue -- work an agent is
# supposed to do -- and it would block `gh api graphql`, where an ordinary READ
# is a POST. Denying by endpoint keeps the read path whole and still closes the
# four actions a human is meant to perform.
#
# #115: gh api needs no method flag to write. Any body -- -f/--raw-field,
# -F/--field, --input -- makes it a POST unless a method is given, and an
# explicit GET turns the fields into query parameters. So an invocation with a
# body flag and no method is a write. Judged per invocation, not per command
# line: a `-X GET` earlier in a && chain must not exempt a later POST.
# TheHub #61038 -- operator decision 2026-10-26: agents never approve an environment
# deployment. The agent's gh CLI is authenticated as the same account that is the
# production environment's required reviewer, so to GitHub an agent's approval IS
# the human's. Two REST endpoints review a waiting run: pending_deployments (the
# environment's required reviewers) and deployment_protection_rule (custom gates).
# A GET of pending_deployments lists what is waiting and stays allowed. gh 2.86 has
# no `gh run` subcommand that approves (cancel, delete, download, list, rerun, view,
# watch), so there is no named subcommand to block -- only these routes, and curl.
DEPLOY_REVIEW='/actions/runs/[^|;&/]+/(pending_deployments|deployment_protection_rule)([^A-Za-z0-9_-]|$)'

# TheHub #61038 review: gh upper-cases the method before sending it, so `-X post` is a
# POST, and pflag reads -X 'PUT', --method "delete" and -X=PUT as well. The method was
# matched upper-case and unquoted only, for every rule below, not just this one.
# Second review: pflag also unpacks -X from a group (-iXPOST), and gh sends the LAST
# method given, so `-X GET -iXPOST` is a POST. Any write method anywhere counts.
GH_M='(-[a-zA-Z]*X[[:space:]]*=?|--method[[:space:]]*=?)[[:space:]]*["'"'"']?'
GH_WRITE='([Pp][Oo][Ss][Tt]|[Pp][Uu][Tt]|[Pp][Aa][Tt][Cc][Hh]|[Dd][Ee][Ll][Ee][Tt][Ee])\b'

gh_api_write() { # true if this is a gh api call carrying a write method
  g_lit api "$B"'gh[[:space:]]+api\b' || return 1
  grep_in "$cmd" -qE "$GH_M$GH_WRITE" && return 0
  printf '%s' "$cmd" | tr '|;&' '\n' \
    | grep -E "$B"'gh[[:space:]]+api\b' \
    | grep -E '[[:space:]](-i*[fF]|--(raw-)?field([=[:space:]]|$)|--input([=[:space:]]|$))' \
    | grep -qvE "$GH_M"'[A-Za-z]'
}

# Second review: a body flag supplied by $(...), backticks or an array expansion
# (gh api .../pending_deployments $(printf -- '-f state=approved')) cannot be seen, so
# a call to these endpoints that carries one and is not an explicit GET is refused.
if g_lit api "$B"'gh[[:space:]]+api\b'; then
  # The endpoint path itself is dropped first: a run id from $(gh run list ...) in a
  # listing is still a read. TheHub #62258: only a command holding /actions/runs/ can match
  # $DEPLOY_REVIEW, so any other skips the six processes of this pipeline.
  [[ $cmd == *"/actions/runs/"* ]] \
    && printf '%s' "$cmd" | tr '|;&' '\n' | grep -E "$B"'gh[[:space:]]+api\b' | grep -E "$DEPLOY_REVIEW" \
    | sed -E 's#[^[:space:]]*/actions/runs/[^[:space:]]*/(pending_deployments|deployment_protection_rule)##' \
    | grep -E '\$\(|`|\[[@*]\]' | grep -qvE "$GH_M"'[Gg][Ee][Tt]\b' \
    && block "a gh api call to an environment deployment review whose arguments come from \$(...), backticks or an array. Its method cannot be read here; list pending deployments with a plain GET." "CM-3, AC-5, AIC-1, AIC-2"
fi

if gh_api_write; then
  g_lit /pulls/ "$B"'gh[[:space:]]+api[^|;&]*/pulls/[^|;&/]+/merge([^A-Za-z0-9_-]|$)' \
    && block "merging a PR through gh api. Merge happens after independent review, via GitHub." "AC-5, CM-5, AIC-2"
  g_lit /pulls/ "$B"'gh[[:space:]]+api[^|;&]*/pulls/[^|;&/]+/reviews([^A-Za-z0-9_-]|$)' \
    && block "reviewing a PR through gh api. Agents recommend; a human or a separate identity approves. Use gh pr comment to say something." "AC-5, AIC-2"
  g_lit /releases "$B"'gh[[:space:]]+api[^|;&]*/releases([^A-Za-z0-9_-]|$)' \
    && block "creating or changing a release through gh api. G5 requires human authorization via the Environment." "CM-3, AIC-1"
  g_lit /branches/ "$B"'gh[[:space:]]+api[^|;&]*/branches/[^|;&]*/protection' \
    && block "removing branch protection. This enforces separation of duties." "AC-5, CM-5"
  g_lit /rulesets "$B"'gh[[:space:]]+api[^|;&]*/rulesets([^A-Za-z0-9_-]|$)' \
    && block "changing a ruleset. Rulesets are branch protection under a newer name, and the same separation of duties rests on them." "AC-5, CM-5"
  g_lit /secrets "$B"'gh[[:space:]]+api[^|;&]*/(actions|codespaces|dependabot)/secrets' \
    && block "writing a secret through gh api. Agents never touch secrets; escalate to a human." "AIC-5, IA-5"
  g_lit /environments "$B"'gh[[:space:]]+api[^|;&]*/environments([^A-Za-z0-9_-]|$)' \
    && block "changing a deployment environment. Its reviewers ARE the G5 authorization gate." "CM-3, AC-5, AIC-1"
  # TheHub #61038: approving the deployment is the gate itself, not its configuration.
  g_lit /actions/runs/ "$B"'gh[[:space:]]+api[^|;&]*'"$DEPLOY_REVIEW" \
    && block "approving or rejecting an environment deployment through gh api. Only a human reviews a deployment; the environment's reviewers ARE the G5 authorization gate." "CM-3, AC-5, AIC-1, AIC-2"
  # Second review, run-time values (the cheap part of TheHub #61039): the endpoint named
  # anywhere in the command, not only in the gh api call (P=.../pending_deployments;
  # gh api -X POST $P, or piped to xargs gh api), and an action segment that is a
  # variable (.../runs/1/$E). A run id in a variable (.../runs/$ID/rerun) stays allowed.
  { g_lit /actions/runs/ "$DEPLOY_REVIEW" || g_lit /actions/runs/ "$B"'gh[[:space:]]+api[^|;&]*/actions/runs/[^|;&/[:space:]]+/\$'; } \
    && block "a gh api write in a command that names an environment deployment review, or whose action is a variable. Only a human reviews a deployment." "CM-3, AC-5, AIC-1, AIC-2"
  # #127: the push-to-main rule knew one spelling, git push. These three reach main
  # through the REST API instead.
  g_lit /git/refs/heads/ "$B"'gh[[:space:]]+api[^|;&]*/git/refs/heads/(main|master)'"$E" \
    && block "moving main through the git refs API. All change goes through a reviewed PR." "AC-5, CM-5"
  # The value a -f/-F/--field/--raw-field flag gives to field $1, if any.
  api_field() { printf '%s' "$cmd" \
    | grep -oE '(-[fF][[:space:]]*|--(raw-)?field[[:space:]=]+)'"$1"'=[^[:space:]|;&)`"'"'"']+' \
    | head -n1 | sed -E 's/^[^=]*=//'; }
  is_main() { grep_in "$1" -qE '^(refs/heads/)?(main|master)$'; }
  # A contents write is a commit. With no branch field it lands on the default branch.
  if g_lit /contents/ "$B"'gh[[:space:]]+api[^|;&]*/contents/'; then
    br=$(api_field branch)
    { [ -z "$br" ] || is_main "$br"; } \
      && block "a commit to main through the contents API (it commits to the default branch when no branch is named). All change goes through a reviewed PR; pass -f branch=<feature>." "AC-5, CM-5"
  fi
  if g_lit /merges "$B"'gh[[:space:]]+api[^|;&]*/merges'"$E"; then
    is_main "$(api_field base)" \
      && block "merging into main through the merges API. Merge happens after independent review, via GitHub." "AC-5, CM-5, AIC-2"
  fi
fi

# #118: GraphQL is one endpoint and every call is a POST, so the rules above cannot
# tell a read from a merge. Read the document instead -- inline, or from the file
# that -F query=@path or --input path names -- and block, by mutation name, the same
# actions the REST rules block. A document that cannot be read (stdin) is refused:
# its contents are unknowable here, and an inline query works just as well.
# Second review: a document substituted from a file, "$(cat q.graphql)" or "$(< q)",
# is read the same way; one produced by any other command stays open (TheHub #61039).
cat_files() { # stdin: command text -> the files that $(cat FILE) / $(< FILE) read
  grep -oE '\$\((cat[[:space:]]+(--[[:space:]]+)?|<[[:space:]]*)[^)[:space:]`"'"'"'|;&]+\)' \
    | sed -E 's/^\$\((cat[[:space:]]+(--[[:space:]]+)?|<[[:space:]]*)//; s/\)$//'
}
# TheHub #61048: the mutation checks are shared with GraphQL sent by curl (below).
# $1 is the document text, $2 says how it was sent and is added to each reason.
gql_mutations() {
  local gql="$1" via="$2"
  grep_in "$gql" -qE '(^|[^A-Za-z0-9_])mutation([^A-Za-z0-9_]|$)' || return 0
  m() { grep_in "$gql" -qE '(^|[^A-Za-z0-9_])('"$1"')([^A-Za-z0-9_]|$)'; }
  m 'mergePullRequest|enablePullRequestAutoMerge|mergeBranch' \
    && block "merging through a GraphQL mutation$via. Merge happens after independent review, via GitHub." "AC-5, CM-5, AIC-2"
  m 'addPullRequestReview|submitPullRequestReview|dismissPullRequestReview' \
    && block "reviewing a PR through a GraphQL mutation$via. Agents recommend; a human or a separate identity approves. Use gh pr comment to say something." "AC-5, AIC-2"
  m '(create|update|delete)Release' \
    && block "creating or changing a release through GraphQL$via. G5 requires human authorization via the Environment." "CM-3, AIC-1"
  m '(create|update|delete)(BranchProtectionRule|RepositoryRuleset)' \
    && block "changing branch protection or a ruleset through GraphQL$via. This enforces separation of duties." "AC-5, CM-5"
  m '(create|update|delete)Environment' \
    && block "changing a deployment environment through GraphQL$via. Its reviewers ARE the G5 authorization gate." "CM-3, AC-5, AIC-1"
  m '(approve|reject)Deployments' \
    && block "approving or rejecting an environment deployment through GraphQL$via. Only a human reviews a deployment; the environment's reviewers ARE the G5 authorization gate." "CM-3, AC-5, AIC-1, AIC-2"
  # #127: moving a ref is a push. A ref id is opaque -- it may be main -- so any
  # GraphQL ref move is refused; a commit is refused when main appears anywhere in
  # the call (inline, or as a variable: -f b=main) or its branch is named only by
  # id. Quotes may still be JSON-escaped here, so main is matched as a word, not
  # as "main". Push a feature branch with git instead.
  # TheHub #61972: createRef with a tag name is a pushed tag.
  m 'createRef' && grep_in "$gql" -qE 'refs/tags/' \
    && block "creating a tag through GraphQL$via. A v* tag is the ref a release is cut from, and cutting a release is the operator's decision. Push your branch and open a PR; after merge the operator creates the tag and dispatches release.yml." "CM-3, AIC-1, AC-5"
  m 'updateRefs?' \
    && block "moving a ref through GraphQL$via. A ref id may be main; push a feature branch with git." "AC-5, CM-5"
  if m 'createCommitOnBranch'; then
    { grep_in "$gql" -qE '(^|[^A-Za-z0-9_/.-])(refs/heads/)?(main|master)([^A-Za-z0-9_/.-]|$)' \
      || ! grep_in "$gql" -qE '(^|[^A-Za-z0-9_])branchName([^A-Za-z0-9_]|$)'; } \
      && block "a commit to main through GraphQL$via (or to a branch named only by id). All change goes through a reviewed PR." "AC-5, CM-5"
  fi
  return 0
}
if g_lit graphql "$B"'gh[[:space:]]+api[[:space:]]+([^|;&]*[[:space:]])?graphql'"$E"; then
  gql="$cmd"
  # Only -F/--field reads @path; with -f/--raw-field "@q.graphql" is a literal string.
  for f in $(printf '%s' "$cmd" | grep -oE '((-F[[:space:]]*|--field[[:space:]=]+)query=@|--input[[:space:]=]+)[^[:space:]|;&)`"'"'"']+' \
               | sed -E 's/^((-F[[:space:]]*|--field[[:space:]=]+)query=@|--input[[:space:]=]+)//'
             printf '%s' "$cmd" | cat_files); do
    if [ "$f" = "-" ] || [ ! -r "$f" ]; then
      block "a GraphQL document this hook cannot read ($f). Pass the query inline with -f query='...'." "AC-5, AIC-2"
    fi
    gql="$gql
$(cat -- "$f")"
  done
  gql_mutations "$gql" ""
fi

# TheHub #61038: curl reaches the same endpoints as gh api, with the token from
# `gh auth token`, and no rule above reads curl. Judged per invocation (backslash-
# continued lines are rejoined at the top) and on the endpoint path, not the host, so
# a full api.github.com URL and an Enterprise one are the same request. As with gh
# api, a body makes it a write unless a GET was asked for (-G/--get, or -X GET); a GET
# of pending_deployments lists what is waiting and stays allowed. A config file
# (-K/--config) can carry the method and the body, so to these endpoints it counts
# as a body.
#
# TheHub #61064: PowerShell's web cmdlets are the same request. Invoke-RestMethod,
# Invoke-WebRequest and their aliases irm and iwr are read exactly as curl is, by
# endpoint, with their own method parameter: -Method or pwsh 7's -CustomMethod, in any
# case, abbreviated to any prefix PowerShell accepts (-Me), as -Method VALUE or
# -Method:VALUE. With no method a cmdlet sends GET, body or not. A method that is a
# variable or an expression, or a splatted hashtable (@p) that can carry one, cannot be
# read here, so to these endpoints it counts as a write. (Windows PowerShell 5.1 also
# aliases curl to Invoke-WebRequest; a curl line is judged by both readings.)
#
# And curl or a cmdlet that writes to any endpoint a gh api rule above protects --
# merge, review, release, branch protection, rulesets, secrets, environments, a ref
# or contents commit or merge on main -- is refused here too. Under the Bash tool,
# settings.json's Bash(curl:*) deny rule stood in front of curl; nothing stands in front
# of the PowerShell tool, so the hook carries it. A raw HTTP client cannot name a
# branch the way -f branch= does for gh api, so its contents and merges writes are
# refused outright: use gh api, where the branch can be read.
PS_HTTP='(invoke-restmethod|invoke-webrequest|irm|iwr)'
HTTP_GH='/pulls/[^/[:space:]]+/(merge|reviews)([^A-Za-z0-9_-]|$)|/releases([^A-Za-z0-9_-]|$)|/branches/[^[:space:]]*/protection|/rulesets([^A-Za-z0-9_-]|$)|/(actions|codespaces|dependabot)/secrets|/environments([^A-Za-z0-9_-]|$)|/git/refs/heads/(main|master)([^A-Za-z0-9_/.-]|$)|/contents/|/merges([^A-Za-z0-9_-]|$)'

http_write() { # $1: one curl or web-cmdlet invocation -> true if it is a write
  local seg="$1" ms
  # Second review: curl, like gh, sends the LAST -X it is given (curl -XGET -XPOST
  # is a POST). So a call is a write if ANY method on it is not GET or HEAD, or if
  # it is curl, carries a body and gives no -X and no -G.
  local curl_m='(-[a-zA-Z]*X[[:space:]]*|--request[[:space:]=]+)[\"'"'"']*'
  local ps_m='(^|[[:space:]])-([Mm][Ee][A-Za-z]*|[Cc][Uu][A-Za-z]*)([[:space:]]*:[[:space:]]*|[[:space:]]+)[\"'"'"']*'
  grep_in "$seg" -qiE "$B$PS_HTTP"'([[:space:]]|$)' \
    && grep_in "$seg" -qE '(^|[[:space:]])@[A-Za-z_]' && return 0
  ms=$(printf '%s' "$seg" | grep -oE "$curl_m"'[$(A-Za-z][A-Za-z]*' | sed -E "s/^$curl_m//"
       printf '%s' "$seg" | grep -oE "$ps_m"'[$(A-Za-z][A-Za-z]*' | sed -E "s/^$ps_m//")
  if [ -n "$ms" ]; then
    grep_nl "$ms" -qvxE '[Gg][Ee][Tt]|[Hh][Ee][Aa][Dd]'
    return
  fi
  grep_in "$seg" -qiE "$B"'curl([[:space:]]|$)' || return 1
  grep_in "$seg" -qE '[[:space:]](-[a-zA-Z]*[dFTK]|--data|--json|--form|--upload-file|--config)' || return 1
  grep_in "$seg" -qE '[[:space:]](-[a-zA-Z]*G|--get)([[:space:]]|$)' && return 1
  return 0
}

if g_lit curl "$B"'curl([[:space:]]|$)' || grep_in "$cmd" -qiE "$B$PS_HTTP"'([[:space:]]|$)'; then
  curl_segs=$(printf '%s' "$cmd" | tr '|;&' '\n' | grep -iE "$B"'(curl|'"$PS_HTTP"')([[:space:]]|$)')
  # TheHub #61038 review: a GraphQL document sent from a file (-d @file, --data-binary
  # @file, --json @file, -T file, -K config) is read, or refused when it cannot be --
  # stdin, a missing file -- exactly as the gh api graphql rule does. TheHub #61064:
  # and a cmdlet's -InFile file, or a -Body read with (Get-Content FILE) / (gc FILE).
  curl_text="$curl_segs"
  curl_gql=$(grep_nl "$curl_segs" -E '/graphql([^A-Za-z0-9_-]|$)')
  if [ -n "$curl_gql" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ "$f" = "-" ] || [ ! -r "$f" ]; then
        block "a GraphQL document sent with curl or a PowerShell web cmdlet that this hook cannot read ($f). Pass it inline with -d '{\"query\":\"...\"}' or -Body '...'." "CM-3, AC-5, AIC-1, AIC-2"
      fi
      curl_text="$curl_text
$(cat -- "$f")"
    done < <(printf '%s\n' "$curl_gql" \
      | grep -oE '(^|[[:space:]])((-[a-zA-Z]*d[[:space:]]*|--(data|data-ascii|data-binary|json)[[:space:]]+)["'"'"']?@|(-[a-zA-Z]*[TK][[:space:]]*|--(upload-file|config)[[:space:]]+)["'"'"']?)[^[:space:]"'"'"'`)]+' \
      | sed -E 's/^[[:space:]]*(-[a-zA-Z]*[dTK][[:space:]]*|--[a-z-]+[[:space:]]+)["'"'"']?@?//'
      printf '%s\n' "$curl_gql" \
      | grep -oE '(^|[[:space:]])-[Ii][Nn][A-Za-z]*([[:space:]]*:[[:space:]]*|[[:space:]]+)["'"'"']?[^-[:space:]"'"'"'()|;&`][^[:space:]"'"'"'()|;&`]*|\(([Gg][Cc]|[Gg]et-[Cc]ontent|cat|type)([[:space:]]+-[A-Za-z]+)*[[:space:]]+["'"'"']?[^-[:space:]"'"'"'()|;&`][^[:space:]"'"'"'()|;&`]*' \
      | sed -E 's/.*[[:space:]"'"'"']//; s/^-[A-Za-z]+://'
      printf '%s\n' "$curl_gql" | cat_files)
  fi
  grep_in "$curl_text" -qE '(^|[^A-Za-z0-9_])(approve|reject)Deployments([^A-Za-z0-9_]|$)' \
    && block "approving or rejecting an environment deployment through GraphQL over curl. Only a human reviews a deployment; the environment's reviewers ARE the G5 authorization gate." "CM-3, AC-5, AIC-1, AIC-2"
  # TheHub #61048: every other mutation the gh api graphql rule blocks, read from the
  # GraphQL calls (and the documents they send) only.
  if [ -n "$curl_gql" ]; then
    gql_mutations "${curl_text#"$curl_segs"}
$curl_gql" " over curl"
  fi
  # Second review: curl rewrites the URL before sending it. It removes dot segments
  # (runs/1/x/../pending_deployments is runs/1/pending_deployments) and expands {} and
  # [] globs (pending_deployment{s}). So dot segments are removed first, and a glob
  # anywhere after a run id counts as these endpoints. (-g and --path-as-is turn the
  # rewriting off; matching as if they were absent can only add a block.)
  curl_norm=$(printf '%s\n' "$curl_segs" | sed -E ':a
s#/\./#/#g
s#/[^/[:space:]]+/\.\./#/#
ta')
  # TheHub #61064: the write test is http_write (above), which reads a PowerShell
  # cmdlet's -Method as well as curl's -X; curl's own reading of a call is
  # unchanged. And, as the gh api rule reads pending_deployments, a protected
  # endpoint named anywhere in the command counts for every write in it
  # ($u = '.../pulls/12/merge'; irm -Method Put $u, or a URL piped to
  # % { irm ... $_ }), so the command itself is judged beside each call. The
  # contents and merges checks still read the branch from the call's own body.
  # keel #165 and #166 merged with #165's loop below (curl_is_write, which reads
  # only curl's -X and body flags) and dropped both of these, leaving http_write
  # and HTTP_GH unused (shellcheck SC2034); binnacle #63 merged the same way and
  # binnacle #74 is the same fix.
  curl_ctx=""
  if g_lit /actions/runs/ "$DEPLOY_REVIEW" || g "$HTTP_GH"; then
    curl_ctx=$(printf '%s\n' "$cmd" | sed -E ':a
s#/\./#/#g
s#/[^/[:space:]]+/\.\./#/#
ta')
  fi
  # TheHub #61048: the {} and [] globs are expanded (every alternative, every
  # character of a range) so pulls/1/merg{e} and mer[g-g]e are read as merge. The
  # line itself is kept too. A glob too large to expand here is refused below.
  read -r -d '' curl_glob_awk <<'AWK'
{
  cs = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  print; n = 1; q[1] = $0; out = 0; ov = 0
  while (n > 0) {
    s = q[n--]
    if (match(s, /\{[^{}]*\}/)) {
      pre = substr(s, 1, RSTART - 1); body = substr(s, RSTART + 1, RLENGTH - 2)
      post = substr(s, RSTART + RLENGTH); k = split(body, alt, ",")
      if (k == 0) { k = 1; alt[1] = "" }
      for (j = 1; j <= k; j++) { if (n >= 512) { ov = 1; break } q[++n] = pre alt[j] post }
      continue
    }
    if (match(s, /\[[A-Za-z0-9]-[A-Za-z0-9](:[0-9]+)?\]/)) {
      pre = substr(s, 1, RSTART - 1); post = substr(s, RSTART + RLENGTH)
      ia = index(cs, substr(s, RSTART + 1, 1)); ib = index(cs, substr(s, RSTART + 3, 1))
      for (j = ia; j <= ib; j++) { if (n >= 512) { ov = 1; break } q[++n] = pre substr(cs, j, 1) post }
      continue
    }
    if (++out > 2048) { ov = 1; break }
    print s
  }
  if (ov) print "CURL_GLOB_OVERFLOW"
}
AWK
  # The value a JSON (or form) body gives to field $2 in invocation $1, if any. Quotes
  # may be gone (the dequoted view) or JSON-escaped (the sed fallback).
  curl_field() { printf '%s' "$1" \
    | grep -oE '(^|[^A-Za-z0-9_])'"$2"'[\"'"'"']*[[:space:]]*[:=][[:space:]]*[\"'"'"']*[^\"'"'"',}&[:space:]]+' \
    | head -n1 | sed -E 's/^[^:=]*[:=][[:space:]]*//; s/[\"'"'"']//g'; }
  curl_main() { grep_in "$1" -qE '^(refs/heads/)?(main|master)$'; }
  # TheHub #61048: the deployment review was the only endpoint curl was judged on.
  # Every endpoint the gh api rules guard is judged here, on the same write test:
  # an explicit write method, or a body with no -X and no -G. A GET stays a read.
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    http_write "$seg" || continue
    # Only the words that hold a / and a glob are expanded, each on its own: a JSON
    # body is full of braces and commas, and expanding it whole multiplies them.
    cu_text="$seg
$(printf '%s\n' "$seg" | grep -oE '[^[:space:]]*/[^[:space:]]*' | grep -E '[][{}]' | LC_ALL=C awk "$curl_glob_awk" 2>/dev/null)
$curl_ctx"
    # TheHub #62258: cu LITERAL ERE, the literal a word every match holds, as g_lit reads it.
    cu() { [[ $cu_text == *"$1"* ]] || return 1; grep_nl "$cu_text" -qE "$2"; }
    cu /actions/runs/ "$DEPLOY_REVIEW"'|/actions/runs/[^|;&/[:space:]]+/[^[:space:]]*[][{}]' \
      && block "approving or rejecting an environment deployment through curl. Only a human reviews a deployment; the environment's reviewers ARE the G5 authorization gate." "CM-3, AC-5, AIC-1, AIC-2"
    cu CURL_GLOB_OVERFLOW '^CURL_GLOB_OVERFLOW$' \
      && block "a curl write whose URL glob is too large to read here. Name the endpoint without {} or [] globs." "AC-5, CM-5"
    cu /pulls/ '/pulls/[^/[:space:]]+/merge([^A-Za-z0-9_-]|$)' \
      && block "merging a PR through curl. Merge happens after independent review, via GitHub." "AC-5, CM-5, AIC-2"
    cu /pulls/ '/pulls/[^/[:space:]]+/reviews([^A-Za-z0-9_-]|$)' \
      && block "reviewing a PR through curl. Agents recommend; a human or a separate identity approves. Use gh pr comment to say something." "AC-5, AIC-2"
    cu /releases '/releases([^A-Za-z0-9_-]|$)' \
      && block "creating or changing a release through curl. G5 requires human authorization via the Environment." "CM-3, AIC-1"
    cu /branches/ '/branches/[^[:space:]]*/protection' \
      && block "changing branch protection through curl. This enforces separation of duties." "AC-5, CM-5"
    cu /rulesets '/rulesets([^A-Za-z0-9_-]|$)' \
      && block "changing a ruleset through curl. Rulesets are branch protection under a newer name, and the same separation of duties rests on them." "AC-5, CM-5"
    cu /secrets '/(actions|codespaces|dependabot)/secrets' \
      && block "writing a secret through curl. Agents never touch secrets; escalate to a human." "AIC-5, IA-5"
    cu /environments '/environments([^A-Za-z0-9_-]|$)' \
      && block "changing a deployment environment through curl. Its reviewers ARE the G5 authorization gate." "CM-3, AC-5, AIC-1"
    cu /git/refs/heads/ '/git/refs/heads/(main|master)([^A-Za-z0-9_./-]|$)' \
      && block "moving main through the git refs API with curl. All change goes through a reviewed PR." "AC-5, CM-5"
    # A contents write is a commit; with no branch in the body it lands on the
    # default branch. A body this hook cannot see (a file) names no branch.
    if cu /contents/ '/contents/'; then
      br=$(curl_field "$seg" branch)
      { [ -z "$br" ] || curl_main "$br"; } \
        && block "a commit to main through the contents API with curl (it commits to the default branch when the body names no branch). All change goes through a reviewed PR; put \"branch\":\"<feature>\" in an inline body." "AC-5, CM-5"
    fi
    if cu /merges '/merges([^A-Za-z0-9_-]|$)'; then
      bs=$(curl_field "$seg" base)
      { [ -z "$bs" ] || curl_main "$bs"; } \
        && block "merging into main through the merges API with curl (or into a base this hook cannot read). Merge happens after independent review, via GitHub." "AC-5, CM-5, AIC-2"
    fi
  done <<< "$curl_norm"
fi

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
#
# EXEMPTION 2026-08-08: `.pub` files are PUBLIC by construction — that is their entire
# purpose. Blocking them stopped a legitimate task (showing the operator their own SSH
# signing key so they could register it) and taught nothing, since the private half is a
# different file and still blocked. Over-blocking a control teaches people to work around
# it (L0007), so the exemption is explicit and narrow: the path must END in .pub.
#
# #117: the path ends at "$E", so `x=$(cat .env)` is a read too.
if grep_in "$cmd" -qE "$B"'(cat|less|more|head|tail|bat|type)[[:space:]]+[^|;&]*([.]env([.][A-Za-z0-9_-]+)?|[.]pem|[.]p12|[.]pfx|[.]key|/[.]ssh/|/[.]aws/|id_rsa|id_ed25519)'"$E" \
   && ! grep_in "$cmd" -qE '[.]pub'"$E"; then
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

# ── Test suites never run inside production's containers (TheHub #61385) ───────
# `docker exec` runs INSIDE the production container, under none of the --cpus/--memory
# caps a test container gets. Uncapped test runs on the operator's host took TheHub
# production down on 2026-10-23 (TheHub #61001). A suite in thehub-backend, thehub-postgres
# or mykronos-backend competes with production for CPU and memory; `nice` lowers its CPU
# priority but not its memory. Tests run in a capped container through the shared lock.
# Read-only exec (cat /proc/..., a status query) is untouched. The runner must be in the
# same exec segment, so `docker exec ... cat x; pytest` (pytest on the host) is not caught.
#
# Review of keel #190: TheHub's compose file names the services backend and postgres
# (container_name thehub-backend and thehub-postgres), so `docker compose exec backend`
# and `docker-compose exec postgres` reach the same containers. Docker's global options
# may stand before the subcommand (docker --context x exec, docker compose -f f.yml exec).
# backend-staging and postgres-staging are other services and stay allowed.
# Not read: a runner fed on stdin or a heredoc (docker exec -i ... sh < run-tests.sh), a
# runner under another name (pytest-3, a script or Makefile target), python -m unittest,
# and a container reached by id or renamed (docs/11-ai-agent-controls.md lists them).
prod_ctr='(thehub-backend|thehub-postgres|mykronos-backend)'
prod_svc='(backend|postgres)'
test_runner='(pytest|py[.]test|tox|nox|python[0-9.]*([[:space:]]+-[A-Za-z]+)*[[:space:]]+-m[[:space:]]*pytest)'
runner_after='[[:space:])`"'"'"']([^|;&]*[[:space:]/'"'"'"])?'"$test_runner$E"
docker_exec="$B"'(docker|podman|nerdctl)([[:space:]]+[^|;&]*)?[[:space:]](container[[:space:]]+)?exec[[:space:]]+([^|;&]*[[:space:]])?'
# Review of #198, round 3 (the PO's fix): main's #61385 patterns run unchanged, as a backstop
# alongside the word judge below. A command blocks if either blocks, so nothing main blocks
# can be allowed here, by construction.
main_docker_exec="$B"'docker([[:space:]]+[^|;&]*)?[[:space:]](container[[:space:]]+)?exec[[:space:]]+([^|;&]*[[:space:]])?'
compose_exec="$B"'(docker([[:space:]]+[^|;&]*)?[[:space:]]compose|docker-compose)[[:space:]]+([^|;&]*[[:space:]])?exec[[:space:]]+([^|;&]*[[:space:]])?'
if g_lit exec "$main_docker_exec$prod_ctr$runner_after" || g_lit exec "$compose_exec$prod_svc$runner_after"; then
  block "running a test suite inside a production container with docker exec. It runs under no --cpus/--memory cap (the 2026-10-23 outage, TheHub #61001). Run it in a capped test container through the shared lock instead: bash scripts/docker-test-lock.sh run <owner> -- bash scripts/test-offline.sh ... (--cpus 2 --memory 2g)." "AIC-3, SC-6, CP-2"
fi
#
# Review of keel #198 (TheHub #61987, round 1): compose run/exec and docker run are judged
# word by word, not by a regex over the line. The review found the runner read only after
# the service (--entrypoint pytest backend), a service held in a variable, podman and
# nerdctl, caps of 0 (no limit) or above the route's 2 CPUs / 2g, cap flags after the image
# (those are the command's own arguments), a bare word "compose" anywhere skipping the rule,
# and false blocks on --memory "2g", pip install pytest and -w /opt/tox. So, per invocation:
# the engine and its global options, then the subcommand; for `run`, the options up to the
# image (caps are read only there), then the command; for `compose run|exec`, the options up
# to the service (--entrypoint kept), then the service and the command. The runner must BE
# the command: pytest, py.test, tox, nox, python -m pytest, or a shell -c body that runs one.
# Not read: `docker run -d ... sleep; docker exec <it> pytest`, and `docker create` then
# `docker start` (docs/11-ai-agent-controls.md lists them).
ctr_route="Run it in a capped test container through the shared lock: bash scripts/docker-test-lock.sh run <owner> -- bash scripts/test-offline.sh ... (--cpus 2 --memory 2g). Uncapped test runs took TheHub production down on 2026-10-23 (TheHub #61001)."
ctr_unq() { local v=$1; v=${v//\"/}; v=${v//\'/}; printf '%s' "$v"; }
# Review of #198, round 4 (timing): the same, in-process, into $_cu. A subshell per word made a
# 300-line heredoc fork thousands of times.
ctr_u() { _cu=${1//\"/}; _cu=${_cu//\'/}; }
ctr_is_runner() { # $1: the command line (entrypoint and arguments), quotes removed
  local c ws
  read -r -a ws <<< "$1"                                    # one space between words, none at the ends
  c=" ${ws[*]-} "
  grep_in "$c" -qE '^ ([A-Za-z_][A-Za-z0-9_]*=[^ ]* )*(nice( -n ?[-0-9]+)? )?([^ ]*/)?(pytest|py[.]test|tox|nox) ' && return 0
  grep_in "$c" -qE '^ ([A-Za-z_][A-Za-z0-9_]*=[^ ]* )*(nice( -n ?[-0-9]+)? )?([^ ]*/)?python[0-9.]*( -[A-Za-z]+)* -m ?pytest ' && return 0
  # Review of #198, round 2: a runner anywhere in the command, not only as its first word
  # (timeout 30 pytest, env X=1 pytest, uv run pytest, python -X dev -m pytest, sh -c 'pytest'),
  # as main's rule effectively read it. A package being installed (pip install pytest) is not
  # a run.
  # Round 3: a package being installed (pip install pytest) is not a run, but only when no
  # runner is left once every `install` and the words after it, up to a separator, are removed
  # (pip install pytest && pytest is a run).
  local R='[ /;&|(]((py[.]?test|tox|nox)|-m ?(pytest|unittest)|npm (run )?test)([ ;&|)]|$)'
  grep_in "$c" -qE "$R" || return 1
  printf '%s' "$c" | sed -E 's/(^|[ ;&|(])install( [^ ;&|()]+)*/\1/g' | grep -qE "$R"
}
ctr_cpu_ok() { # $1 --cpus value; $2 --cpu-quota; $3 --cpu-period. True when 0 < CPUs <= 2.
  guard_run awk 1 -v c="$1" -v q="$2" -v p="${3:-100000}" 'BEGIN { if (c != "") v = c + 0; else if (q != "") v = (q + 0) / (p + 0); else exit 1; exit !(v > 0 && v <= 2) }'
}
ctr_mem_ok() { # $1: a --memory value. True when 0 < bytes <= 2g.
  [ -n "$1" ] || return 1
  printf '%s' "$1" | guard_run awk 1 '{ v = $0; sub(/[bB]$/, "", v); if (v == "") exit 1; u = tolower(substr(v, length(v))); n = v + 0
    if (u == "k") n *= 1024; else if (u == "m") n *= 1048576; else if (u == "g") n *= 1073741824
    exit !(v ~ /^[0-9.]+[bkmgBKMG]?$/ && n > 0 && n <= 2147483648) }'
}
ctr_judge() { # $@: the words of one invocation
  local w=("$@") n=$# i=0 eng="" sub="" a v
  while [ "$i" -lt "$n" ]; do
    ctr_u "${w[i]}"; a=${_cu##*[/\\]}; a=${a,,}; a=${a%.exe}   # any case, either slash (hook train review)
    case "$a" in docker|podman|nerdctl|docker-compose|podman-compose) eng=$a; break ;; esac
    i=$((i + 1))
  done
  [ -z "$eng" ] && return 0
  i=$((i + 1))
  # Review of #198, round 2: /usr/bin/docker or docker.exe is followed by the bare name
  # normalize() appended; that word is the engine again, not the subcommand.
  ctr_u "${w[i]:-}"; [ "$_cu" = "$eng" ] && i=$((i + 1))
  # global options of the engine (and of compose)
  while [ "$i" -lt "$n" ]; do
    ctr_u "${w[i]}"; a=$_cu
    case "$a" in
      -H|--host|--context|-c|--config|--log-level|-l|-f|--file|--tlscacert|--tlscert|--tlskey|-p|--project-name|--profile|--env-file|--project-directory|--ansi|--progress|--namespace|-n|--address|--url|--connection|--root|--runroot) i=$((i + 2)) ;;
      -*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  ctr_u "${w[i]:-}"; sub=$_cu
  case "$eng" in *-compose) sub="compose-$sub" ;; esac
  if [ "$sub" = "compose" ]; then
    i=$((i + 1))
    while [ "$i" -lt "$n" ]; do
      ctr_u "${w[i]}"; a=$_cu
      case "$a" in -f|--file|-p|--project-name|--profile|--env-file|--project-directory|--ansi|--progress|--parallel) i=$((i + 2)) ;; -*) i=$((i + 1)) ;; *) break ;; esac
    done
    ctr_u "${w[i]:-}"; sub="compose-$_cu"
  fi
  [ "$sub" = "container" ] && { i=$((i + 1)); ctr_u "${w[i]:-}"; sub=$_cu; }
  i=$((i + 1))
  local entry="" svc="" rest="" cpus="" quota="" period="" mem=""
  case "$sub" in
    compose-run|compose-exec)
      while [ "$i" -lt "$n" ]; do
        ctr_u "${w[i]}"; a=$_cu
        case "$a" in
          --entrypoint) ctr_u "${w[i+1]:-}"; entry=$_cu; i=$((i + 2)) ;;
          --entrypoint=*) entry=${a#--entrypoint=}; i=$((i + 1)) ;;
          -e|--env|-l|--label|--name|-p|--publish|-u|--user|-v|--volume|-w|--workdir|--pull|--cap-add|--cap-drop|--env-file|--env-from-file|--index) i=$((i + 2)) ;;
          -*) i=$((i + 1)) ;;
          *) break ;;
        esac
      done
      ctr_u "${w[i]:-}"; svc=$_cu; i=$((i + 1))
      ctr_u "$entry ${w[*]:i}"; rest=$_cu
      ctr_is_runner "$rest" || return 0
      # Round 2 backstop: a production service named anywhere among the words after
      # run|exec, with a runner, is refused even when an option this parser does not know
      # took the service's place.
      for a in "${w[@]:i-1}"; do ctr_u "$a"; [[ $_cu =~ ^${prod_svc}$ ]] && svc=$_cu; done
      case "$svc" in *'$'*|*'`'*) block "a test suite in a compose service named by a variable ($svc); it may be a production service. Name the service. $ctr_route" "AIC-3, SC-6, CP-2" ;; esac
      grep_in "$svc" -qxE "$prod_svc" \
        && block "running a test suite in a production compose service with $eng ${sub#compose-} ($svc: thehub-backend, thehub-postgres, mykronos-backend). It runs under none of a test container's caps. $ctr_route" "AIC-3, SC-6, CP-2"
      return 0 ;;
    run)
      while [ "$i" -lt "$n" ]; do
        ctr_u "${w[i]}"; a=$_cu
        case "$a" in
          --cpus=*) cpus=${a#*=} ;;
          --cpus) ctr_u "${w[i+1]:-}"; cpus=$_cu; i=$((i + 1)) ;;
          --cpu-quota=*) quota=${a#*=} ;;
          --cpu-quota) ctr_u "${w[i+1]:-}"; quota=$_cu; i=$((i + 1)) ;;
          --cpu-period=*) period=${a#*=} ;;
          --cpu-period) ctr_u "${w[i+1]:-}"; period=$_cu; i=$((i + 1)) ;;
          --memory=*) mem=${a#*=} ;;
          --memory|-m) ctr_u "${w[i+1]:-}"; mem=$_cu; i=$((i + 1)) ;;
          -m*) mem=${a#-m}; mem=${mem#=} ;;
          --entrypoint=*) entry=${a#*=} ;;
          --entrypoint) ctr_u "${w[i+1]:-}"; entry=$_cu; i=$((i + 1)) ;;
          --*=*) ;;
          --rm|--detach|--interactive|--tty|--init|--privileged|--read-only|--publish-all|--no-healthcheck|--oom-kill-disable|--quiet|--sig-proxy|--help|--disable-content-trust|--use-api-socket) ;;
          --*) i=$((i + 1)) ;;                              # a long option and its value
          -[ditPq]|-[ditPq][ditPq]|-[ditPq][ditPq][ditPq]) ;;  # flag clusters (-it, -dit)
          -[ditPq]*[A-Za-z]) i=$((i + 1)) ;;                # a cluster ending in an option that takes a value (-itv /x:/y)
          -?) i=$((i + 1)) ;;                               # a short option and its value
          -*) ;;                                            # a short option with its value attached
          *) break ;;
        esac
        i=$((i + 1))
      done
      i=$((i + 1))                                          # the image
      ctr_u "$entry ${w[*]:i}"; rest=$_cu
      ctr_is_runner "$rest" || return 0
      case "$cpus$quota$period$mem" in *'$'*|*'`'*) block "a test suite in a docker run whose CPU or memory cap is a variable this hook cannot read. Give the caps as numbers. $ctr_route" "AIC-3, SC-6, CP-2" ;; esac
      { ctr_cpu_ok "$cpus" "$quota" "$period" && ctr_mem_ok "$mem"; } \
        || block "running a test suite in a $eng run without a CPU cap of at most 2 (--cpus, or --cpu-quota) and a memory cap of at most 2g (--memory) before the image. $ctr_route" "AIC-3, SC-6, CP-2"
      return 0 ;;
  esac
  return 0
}
if g_lit exec "$docker_exec$prod_ctr$runner_after"; then
  block "running a test suite inside a production container with docker exec. It runs under no --cpus/--memory cap (the 2026-10-23 outage, TheHub #61001). Run it in a capped test container through the shared lock instead: bash scripts/docker-test-lock.sh run <owner> -- bash scripts/test-offline.sh ... (--cpus 2 --memory 2g)." "AIC-3, SC-6, CP-2"
fi
}

# ── A push of the current branch (TheHub #62031, best effort) ────────────────────
# `git push`, `git push origin`, or a push of HEAD (or `@`, or `head`, which resolves to HEAD
# on a case-insensitive file system) pushes the CURRENT branch. On a checkout that is on main
# that is a push to main, the likeliest real one. Review round 1 narrowed this to what can be
# read without guessing, since enforce_admins server-side is the real control:
#   - only a literal `git push` invocation, read as shell words with quotes honoured, never
#     `git stash push`, `git log --grep push` or quoted text;
#   - git's own -C, -c and --git-dir/--work-tree are read; -c push.* or -c remote.*.push on a
#     push is refused outright (they can map a push onto main);
#   - if the command changes directory, sets GIT_DIR or GIT_WORK_TREE, or checks out or
#     switches a branch anywhere, the branch the push will see cannot be read from here, so
#     the push is refused with a clear message: run it as a command of its own;
#   - otherwise the branch is read where the push runs, with git symbolic-ref through the
#     fault-recording wrapper. Outside a repository (git exits 128) there is nothing to judge,
#     and the push is allowed.
# Not read: a git alias, xargs, a push run by a script, and push.default other than
# simple/current/upstream (a plain push is taken as the current branch).
read -r -d '' push_tok_awk <<'AWK'
# T1 (review round 3): a segment is printed only when one of its words can make it matter to
# the judge (git, a shell, eval, a directory change, GIT_DIR / GIT_WORK_TREE), so a long heredoc
# of prose costs this one awk pass and no shell work per line.
# The test mirrors push_judge's own reading of the words before the command (assignments and
# the same wrappers), so a dropped segment is one push_judge would have returned from unread.
function emit(x, lx) {
  seg = seg x "\n"
  if (decided) return
  lx = tolower(x)
  if (lx ~ /^(git_dir=|git_work_tree=|\$env:git_dir|\$env:git_work_tree)/) { keep = 1; return }
  if (lx ~ /^[a-z_].*=/ || lx ~ /^\$env:/) return
  if (lx ~ /^(env|command|builtin|exec|nice|nohup|time|sudo|doas)$/) return
  decided = 1
  # Hook train review: without its directory (either slash) or .exe, as push_judge reads it.
  sub(/^.*[\/\\]/, "", lx); sub(/\.exe$/, "", lx)
  if (lx ~ /^(cd|pushd|popd|chdir|set-location|sl|push-location|pop-location|sh|bash|dash|zsh|ash|eval)$/) keep = 1
  if (lx ~ /git$/) keep = 1
}
function flush() { if (have) { emit(tok); tok = ""; have = 0 } }
function sep() { flush(); if (keep) printf "%s", seg; print "\001"; seg = ""; keep = 0; decided = 0 }
{ s = (NR > 1) ? s "\n" $0 : $0 }
END {
  n = length(s); q = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q != "") { if (c == q) q = ""; else if (c == "\\" && q == "\"" && i < n) tok = tok substr(s, ++i, 1); else tok = tok c; continue }
    if (c == "'" || c == "\"") { q = c; have = 1; continue }
    if (c == "\\" && i < n) { tok = tok substr(s, ++i, 1); have = 1; continue }
    if (c == "$" && substr(s, i + 1, 1) == "(") {           # $(...) stays inside its word (round 2)
      d = 0
      for (; i <= n; i++) { c = substr(s, i, 1); tok = tok c; if (c == "(") d++; else if (c == ")" && --d == 0) break }
      have = 1; continue
    }
    if (c == " " || c == "\t") { flush(); continue }
    if (c == "\n" || c == ";" || c == "|" || c == "&" || c == "(" || c == ")" || c == "`") { sep(); continue }
    if (c == "<" || c == ">") { if (tok ~ /^[0-9]+$/) { tok = ""; have = 0 } else flush(); while (i < n && index("<>", substr(s, i + 1, 1))) i++; emit(">"); continue }
    tok = tok c; have = 1
  }
  sep()
}
AWK
push_moves=0   # 1 once a word that changes the directory, the git dir or the branch is seen
push_lit() { case "$1" in *'$'*|*'`'*|'~'*) return 1 ;; esac; return 0; }   # a word read as written
push_judge() { # $@: the words of one invocation
  local w=("$@") n=$# i=0 a dir="" ndir=0 sub="" pos=0 cur=0 cfg_bad="" first="" dry=0
  # Words before the command: VAR=value assignments (GIT_DIR and GIT_WORK_TREE move the push),
  # PowerShell $env: assignments, and a few wrappers. A word that changes the directory, as
  # the command, moves every push after it (in any case: PowerShell's CD is cd).
  # T1 (review round 3): matched in any case with nocasematch (bash 3.1+), not by starting tr
  # twice per command; the option is set for these two case statements only.
  local kind=""
  shopt -s nocasematch
  while [ "$i" -lt "$n" ]; do
    a=${w[i]}
    case "$a" in
      git_dir=*|git_work_tree=*|'$env:git_dir'*|'$env:git_work_tree'*) push_moves=1; i=$((i + 1)); continue ;;
      [a-z_]*=*|'$env:'*) i=$((i + 1)); continue ;;
      env|command|builtin|exec|nice|nohup|time|sudo|doas) i=$((i + 1)); continue ;;
    esac
    break
  done
  # Hook train review (keel #205): the program word is read without its directory (either
  # slash) and without .exe, in any case, as normalize() reads it. normalize() leaves a
  # non-plain spelling (git.exe, GIT, a path) in place and appends the bare name after it,
  # so that next word is the program again, not the subcommand (as in ctr_judge).
  local isgit=0
  if [ "$i" -lt "$n" ]; then
    first=${w[i]}
    a=${first##*[/\\]}; [[ $a == *.exe ]] && a=${a%????}
    case "$a" in
      cd|pushd|popd|chdir|set-location|sl|push-location|pop-location) kind="cd" ;;
      sh|bash|dash|zsh|ash) kind="sh" ;;
      eval) kind="eval" ;;
      git) isgit=1 ;;
      *git) [ "${w[i+1]:-}" = "git" ] && isgit=1 ;;   # a path whose separators the tokenizer dropped
    esac
  fi
  shopt -u nocasematch
  [ "$i" -ge "$n" ] && return 0
  case "$kind" in
    cd) push_moves=1; return 0 ;;
    sh)
      # A shell -c body is a command of its own: judge it the same way (review round 2).
      local k=$((i + 1))
      while [ "$k" -lt "$n" ]; do
        case "${w[k]}" in -*c*) [ $((k + 1)) -lt "$n" ] && push_guard "${w[k+1]}"; return 0 ;; -*) ;; *) return 0 ;; esac
        k=$((k + 1))
      done
      return 0 ;;
    eval) push_guard "${w[*]:i+1}"; return 0 ;;
  esac
  [ "$isgit" -eq 1 ] || return 0
  i=$((i + 1))
  [ "${w[i]:-}" = "git" ] && i=$((i + 1))   # the bare name normalize() appended
  # git's global options. One this hook does not know, before a push, is refused (round 2):
  # skipping it would let the push go unread.
  local unknown=""
  while [ "$i" -lt "$n" ]; do
    a=${w[i]}
    case "$a" in
      -C) ndir=$((ndir + 1)); dir=${w[i+1]:-}; push_lit "$dir" || dir='$'; i=$((i + 2)) ;;
      -c) case "${w[i+1]:-}" in [Pp][Uu][Ss][Hh].*|[Rr][Ee][Mm][Oo][Tt][Ee].*.[Pp][Uu][Ss][Hh]=*|[Rr][Ee][Mm][Oo][Tt][Ee].*.[Mm][Ii][Rr][Rr][Oo][Rr]=*) cfg_bad=${w[i+1]} ;; esac; i=$((i + 2)) ;;
      -c*) case "${a#-c}" in [Pp][Uu][Ss][Hh].*|[Rr][Ee][Mm][Oo][Tt][Ee].*.[Pp][Uu][Ss][Hh]=*) cfg_bad=${a#-c} ;; esac; i=$((i + 1)) ;;
      --git-dir|--work-tree) push_moves=1; i=$((i + 2)) ;;
      --git-dir=*|--work-tree=*) push_moves=1; i=$((i + 1)) ;;
      --namespace|--config-env|--attr-source|--super-prefix|--list-cmds) i=$((i + 2)) ;;
      --namespace=*|--config-env=*|--attr-source=*|--super-prefix=*|--exec-path=*|--exec-path|--list-cmds=*) i=$((i + 1)) ;;
      -p|-P|--paginate|--no-pager|--bare|--no-replace-objects|--no-lazy-fetch|--no-optional-locks|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--no-advice) i=$((i + 1)) ;;
      -*) unknown=$a; i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  sub=${w[i]:-}
  case "$sub" in
    checkout|switch) push_moves=1; return 0 ;;
    send-pack) block "git send-pack, the plumbing under git push, which can move main. Push a feature branch with git push." "AC-5, CM-5" ;;
    push) ;;
    *'$'*|*'`'*) block "a git command whose subcommand ($sub) is not written literally; it may be a push. Write the command out." "AC-5, CM-5" ;;
    *) return 0 ;;
  esac
  [ -n "$unknown" ] && block "a git push after a global option this hook cannot read ($unknown). Push without it, or name the branch: git push origin <feature>." "AC-5, CM-5"
  [ -n "$cfg_bad" ] && block "a git push with -c $cfg_bad, which can map the push onto main. Push a feature branch by name." "AC-5, CM-5"
  i=$((i + 1))
  local dyn=0 r dst name
  while [ "$i" -lt "$n" ]; do
    a=${w[i]}
    case "$a" in
      ">") i=$((i + 2)); continue ;;                       # a redirect and its target
      -o|--push-option|--repo|--receive-pack|--exec) i=$((i + 2)); continue ;;
      --push-option=*|--repo=*|--receive-pack=*|--exec=*|-o?*) ;;
      --dry-run|-n) dry=1 ;;
      --no-dry-run) dry=0 ;;                               # the last one wins
      --no-*) ;;
      --*)
        name=${a#--}; name=${name%%=*}
        if [ -n "$name" ]; then
          local opt
          for opt in all mirror branches; do         # git accepts any unique prefix of a long option
            case "$opt" in "$name"*) block "a push of every branch or ref (--$opt, read from --$name), main included. Push one feature branch." "AC-5, CM-5" ;; esac
          done
        fi ;;
      -*) ;;
      *)
        pos=$((pos + 1))
        if [ "$pos" -gt 1 ]; then                          # the first is the repository
          r=$a
          case "$r" in
            *'$'*|*'`'*) dyn=1 ;;
            *)
              case "$r" in *'*'*) block "a wildcard refspec ($r), which can include main. Push one feature branch by name." "AC-5, CM-5" ;; esac
              case "$r" in '+'*) block "force push (a + refspec). Published history is immutable — it is the AU-12 audit trail." "AIC-3, AU-12, SI-7" ;; esac
              [ "$r" = ":" ] && block "a push of every matching branch (a bare ':' refspec), main included. Push one feature branch." "AC-5, CM-5"
              case "$r" in *:*) dst=${r#*:} ;; *) dst=$r ;; esac
              dst=${dst#refs/}; dst=${dst#heads/}
              case "$dst" in main|master) block "a push to main ($r). All change goes through a reviewed PR." "AC-5, CM-5" ;; esac
              case "$r" in HEAD|@|head) cur=1 ;; esac ;;
          esac
        fi ;;
    esac
    i=$((i + 1))
  done
  [ "$dry" -eq 1 ] && return 0                             # a dry run moves nothing
  [ "$pos" -le 1 ] && cur=1
  [ "$dyn" -eq 1 ] && cur=1                                # $(...) or $VAR as a refspec: as the current branch
  [ "$cur" -eq 1 ] || return 0
  [ "$push_moves" -eq 1 ] && block "a push of the current branch after the command changes directory, the git directory or the branch: which branch it pushes cannot be read here. Run the push as a command of its own, from the checkout you mean, or name the branch: git push origin <feature>." "AC-5, CM-5"
  { [ "$ndir" -gt 1 ] || [ "$dir" = '$' ]; } && block "a push of the current branch from a git -C this hook cannot read literally (a variable, \$(...), ~, or -C given twice). Name the branch: git push origin <feature>." "AC-5, CM-5"
  [ -n "${guard_cwd_read:-}" ] || { guard_read_cwd; guard_cwd_read=1; }   # TheHub #62258: on first use
  local base="${payload_cwd:-$PWD}" branch rc
  if [ -n "$dir" ]; then case "$dir" in /*|[A-Za-z]:[/\\]*) base=$dir ;; *) base="$base/$dir" ;; esac; fi
  branch=$(command git -C "$base" symbolic-ref --short -q HEAD 2>/dev/null); rc=$?
  case "$rc" in
    0) ;;
    1) return 0 ;;                                         # a detached HEAD is not a branch
    128) [ -z "$dir" ] && return 0                          # the payload cwd is not a repository: nothing to judge
         block "a push of the current branch from ${dir} (git -C), which git cannot read as a repository. Name the branch: git push origin <feature>." "AC-5, CM-5" ;;
    *) block "a push of the current branch, which this hook cannot read (git exited ${rc}): it may be main. Name the branch: git push origin <feature>." "AC-5, CM-5" ;;
  esac
  case "$branch" in
    main|master) block "a push of the current branch, which is $branch (in $base). All change goes through a reviewed PR: push a feature branch." "AC-5, CM-5" ;;
  esac
  return 0
}
push_guard() { # $1: one view of the command
  local toks=() seg=() t src=$1
  # The tokenizer ends a command at a \001 mark (heredoc bodies use \002 and \003). One written into
  # the text, as a control character inside a quoted argument, would end the command there and leave
  # the rest judged as a push with no refspec, which on main reads as a push of main. As ? it is a
  # word this hook cannot read, as in tag_guard (TheHub #61972).
  src=${src//[$'\001\002\003']/?}
  mapfile -t toks < <(printf '%s' "$src" | LC_ALL=C awk "$push_tok_awk")
  toks+=($'\001')
  for t in "${toks[@]}"; do
    if [ "$t" = $'\001' ]; then
      [ "${#seg[@]}" -gt 0 ] && push_judge "${seg[@]}"
      seg=(); continue
    fi
    seg+=("$t")
  done
}
# Review of #198 (round 1): the container rules read shell words with quotes honoured, so
# --entrypoint "python -m pytest" is one word and -e X="--cpus 2 -m 2g" is not a cap. Run on
# the masked view (a separator inside quotes is already a space) and the PowerShell view.
read -r -d '' ctr_tok_awk <<'AWK'
function hd_open(   dash, dl, e) {   # after "<<": read the delimiter; the body starts at the next newline
  i++; dash = 0; if (substr(s, i + 1, 1) == "-") { dash = 1; i++ }
  while (substr(s, i + 1, 1) ~ /[ \t]/) i++
  dl = ""
  while (i < n) { e = substr(s, i + 1, 1); if (e ~ /[ \t\n;|&<>()]/) break; i++; if (e != "'" && e != "\"" && e != "\\") dl = dl e }
  nhd++; hdelim[nhd] = dl; hdash[nhd] = dash
}
function hd_bodies(emit,   k, line, body, j, dl) {   # at a newline: consume the pending bodies
  for (k = 1; k <= nhd; k++) {
    body = ""
    while (i < n) {
      j = index(substr(s, i + 1), "\n"); if (j == 0) j = n - i + 1
      line = substr(s, i + 1, j - 1); i += j
      dl = line; if (hdash[k]) sub(/^\t+/, "", dl)
      if (dl == hdelim[k]) break
      body = body line "\003"
    }
    if (emit) print "\002" body
  }
  nhd = 0
}
function flush() { if (have) { print tok; tok = ""; have = 0 } }
{ s = (NR > 1) ? s "\n" $0 : $0 }
END {
  n = length(s); q = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q != "") { if (c == q) q = ""; else if (c == "\\" && q == "\"" && i < n) tok = tok substr(s, ++i, 1); else tok = tok c; continue }
    if (c == "'" || c == "\"") { q = c; have = 1; continue }
    if (c == "\\" && i < n) { tok = tok substr(s, ++i, 1); have = 1; continue }
    if (c == "$" && substr(s, i + 1, 1) == "(") {           # $(...) stays inside its word (round 2)
      d = 0
      for (; i <= n; i++) { c = substr(s, i, 1); tok = tok c; if (c == "(") d++; else if (c == ")" && --d == 0) break }
      have = 1; continue
    }
    if (c == "<" && substr(s, i + 1, 1) == "<" && substr(s, i + 2, 1) != "<") { flush(); hd_open(); continue }   # round 4: a heredoc
    if (c == " " || c == "\t") { flush(); continue }
    if (c == "\n") { flush(); if (nhd) hd_bodies(1); print "\001"; continue }
    if (c == ";" || c == "|" || c == "&" || c == "(" || c == ")" || c == "`") { flush(); print "\001"; continue }
    tok = tok c; have = 1
  }
  flush()
}
AWK
ctr_seg() { # $@: one segment. Round 3: judged from EVERY engine word (an outer docker exec
  # <container> docker compose ... is two invocations), and a NAME=value word is never an engine.
  # Round 4: a heredoc body (one \002 word) is a command only when a shell is fed it
  # (bash <<EOF ...); fed to anything else (git commit -F -, cat > file) it is text.
  local w=() k a first="" bodies=()
  for a in "$@"; do case "$a" in $'\002'*) bodies+=("${a#?}") ;; *) w+=("$a") ;; esac; done
  for a in "${w[@]}"; do case "$a" in [A-Za-z_]*=*|env|sudo|command|exec|nice|nohup|timeout) ;; *) ctr_u "$a"; first=${_cu##*[/\\]}; first=${first,,}; first=${first%.exe}; break ;; esac; done
  case "$first" in
    sh|bash|dash|zsh|ash|ksh) for a in "${bodies[@]}"; do ctr_guard "${a//$'\003'/$'\n'}"; done ;;
  esac
  set -- "${w[@]}"
  for ((k = 0; k < $#; k++)); do
    case "${w[k]}" in [A-Za-z_]*=*) continue ;; *[Dd][Oo][Cc][Kk][Ee][Rr]*|*[Pp][Oo][Dd][Mm][Aa][Nn]*|*[Nn][Ee][Rr][Dd][Cc][Tt][Ll]*) ;; *) continue ;; esac
    ctr_u "${w[k]}"; a=${_cu##*[/\\]}; a=${a,,}; a=${a%.exe}   # any case, either slash (hook train review)
    case "$a" in docker|podman|nerdctl|docker-compose|podman-compose) ctr_judge "${w[@]:k}" ;; esac
  done
}
read -r -d '' HD_AWK <<'AWK' || true
function hd_open(   dash, dl, e) {   # after "<<": read the delimiter; the body starts at the next newline
  i++; dash = 0; if (substr(s, i + 1, 1) == "-") { dash = 1; i++ }
  while (substr(s, i + 1, 1) ~ /[ \t]/) i++
  dl = ""
  while (i < n) { e = substr(s, i + 1, 1); if (e ~ /[ \t\n;|&<>()]/) break; i++; if (e != "'" && e != "\"" && e != "\\") dl = dl e }
  nhd++; hdelim[nhd] = dl; hdash[nhd] = dash
}
function hd_bodies(emit,   k, line, body, j, dl) {   # at a newline: consume the pending bodies
  for (k = 1; k <= nhd; k++) {
    body = ""
    while (i < n) {
      j = index(substr(s, i + 1), "\n"); if (j == 0) j = n - i + 1
      line = substr(s, i + 1, j - 1); i += j
      dl = line; if (hdash[k]) sub(/^\t+/, "", dl)
      if (dl == hdelim[k]) break
      body = body line "\003"
    }
    if (emit) print "\002" body
  }
  nhd = 0
}
AWK
ctr_subst_awk="$HD_AWK"'
{ s = (NR > 1) ? s "\n" $0 : $0 }
END {
  n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "<" && substr(s, i + 1, 1) == "<" && substr(s, i + 2, 1) != "<") { hd_open(); continue }
    if (c == "\n") { if (nhd) hd_bodies(0); continue }
    if (c == "$" && substr(s, i + 1, 1) == "(") {
      d = 0; b = ""
      for (j = i + 1; j <= n; j++) { e = substr(s, j, 1); if (e == "(") d++; else if (e == ")" && --d == 0) break; if (j > i + 1) b = b e }
      gsub(/\n/, " ", b); print b; i = j   # past the body: a nested one is found by the recursion, once (round 4)
    } else if (c == "`") {
      j = index(substr(s, i + 1), "`"); if (j == 0) j = n - i + 1
      b = substr(s, i + 1, j - 1); gsub(/\n/, " ", b); print b; i += j
    }
  }
}'
ctr_depth=0
ctr_guard() { # $1: one view of the command
  local toks=() seg=() t bodies=() b src=$1
  # The tokenizer ends a command at a \001 mark and reads a word starting with \002 as a heredoc
  # body (\003 ends its lines). One written into the text, as a control character inside a quoted
  # argument (docker run -l "<\001>" ...), ended the invocation there, so the image and the test
  # runner after it were never judged. As ? it is a word this hook cannot read, as in tag_guard and
  # push_guard (review of keel #210, TheHub #61972).
  src=${src//[$'\001\002\003']/?}
  mapfile -t toks < <(printf '%s' "$src" | LC_ALL=C awk "$ctr_tok_awk")
  toks+=($'\001')
  for t in "${toks[@]}"; do
    if [ "$t" = $'\001' ]; then
      [ "${#seg[@]}" -gt 0 ] && ctr_seg "${seg[@]}"
      seg=(); continue
    fi
    seg+=("$t")
  done
  # Round 3: the body of every $(...) and backtick, quoted or not, is a command of its own.
  case "$src" in *'$('*|*'`'*) ;; *) return 0 ;; esac
  ctr_depth=$((ctr_depth + 1))
  [ "$ctr_depth" -gt 6 ] && block "a command with substitutions nested more than 6 deep, which this hook does not unfold. Write it flatter; an ordinary command does not nest that far." "AIC-3, SC-6, CP-2"
  if [ "$ctr_depth" -le 6 ]; then
    mapfile -t bodies < <(printf '%s' "$src" | LC_ALL=C awk "$ctr_subst_awk")
    for b in "${bodies[@]}"; do [ -n "$b" ] && ctr_guard "$b"; done
  fi
  ctr_depth=$((ctr_depth - 1))
}
# ── Release tags (TheHub #61972) ──────────────────────────────────────────────
# A v* tag is the ref a release is cut from (release.yml signs "release.yml@refs/tags/TAG"),
# so an agent never creates one, pushes one, or writes one through the API. Regexes over the
# command line both missed and over-matched here (review of keel #192): git accepts any
# unique prefix of a long option (--tag, --follow-tag, --mirr), v-words in a commit message
# or a redirect target (> v1.log) are not refspecs, and `git stash push` is not a push. So
# the command is split into shell words (quotes honoured, $(...) and backticks as word
# breaks) and only the arguments that name refs are judged:
#
#   git [global options] push ...  --tags, --follow-tags, --mirror by any unique prefix;
#       a refspec that names refs/tags/..., a version-like bare name (v1, v1.2.3, vNext),
#       `tag <v...>`, or anything this hook cannot resolve from the text ($VAR, $(...), a
#       glob such as refs/* or refs/t*); -c / --config-env of push.followTags,
#       remote.<name>.push or remote.<name>.mirror.
#   git send-pack                   always (the plumbing under push).
#   git tag <name>                  creating a tag named v*, or one named by a variable.
#                                   Listing (-l, --list, no name), -d and -v stay allowed.
#   git config                      setting push.followTags, remote.<name>.push or .mirror;
#                                   --get, --list and get/list stay allowed.
#   gh api                          a write to git/tags or git/refs/tags/...; a write to
#                                   git/refs unless it carries exactly one literal
#                                   ref=refs/heads/<name> (-f/--raw-field, or -F without @)
#                                   and no --input. The endpoint is normalised first: a
#                                   query string, trailing or doubled slashes, a leading
#                                   slash and the API host are dropped.
# A branch named v2-migration is allowed; a bare name shaped like a release (v<digits> with
# dots, or v and a capital) is refused, because it is a tag when one by that name exists.
# Review of #192, round 2 (rescoped by the PO): the tag guard judges only the command word of
# each simple command and the words that belong to it. Quoted text (a -m message, a --body, an
# echo or grep argument), a heredoc body fed to anything but a shell, and a # comment are never
# read as a command. The text is split the way the shell that runs it would split it: bash
# (quotes, backslash-newline deleted, a redirect and its target, heredocs, comments) or
# PowerShell (backtick escapes, '' and "" in quotes, script blocks, (Get-Command x).Source).
# A Bash payload is read the bash way and a PowerShell payload the PowerShell way. A shell, eval, Invoke-Expression, cmd /c or
# Start-Process that runs a command is judged on that command. A payload that names no tool is
# a Bash one: Claude Code's PowerShell tool always sends tool_name.
read -r -d '' tok_awk <<'AWK'
function flush() { if (have) { gsub(/\n/, "\003", tok); print tok; tok = ""; have = 0 } }
function bodies(   k, line, body, j, dl) {        # the heredoc bodies that start after this newline
  for (k = 1; k <= nhd; k++) {
    body = ""
    while (i < n) {
      j = index(substr(s, i + 1), "\n"); if (j == 0) j = n - i + 1
      line = substr(s, i + 1, j - 1); i += j
      dl = line; if (hdash[k]) sub(/^\t+/, "", dl)
      if (dl == hdelim[k]) break
      body = body line "\n"
    }
    gsub(/\n/, "\003", body); print "\002" body
  }
  nhd = 0
}
{ s = (NR > 1) ? s "\n" $0 : $0 }
END {
  n = length(s); q = ""; tok = ""; have = 0; nhd = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1); d = substr(s, i + 1, 1)
    if (q == "'") { if (c == "'") q = ""; else tok = tok c; continue }
    if (q == "\"") {
      if (c == "\"") q = ""
      else if (c == "\\" && d == "\n") i++
      else if (c == "\\" && (d == "$" || d == "`" || d == "\"" || d == "\\")) { tok = tok d; i++ }
      else tok = tok c
      continue
    }
    if (c == "'" || c == "\"") { q = c; have = 1; continue }
    if (c == "\\" && i < n) { i++; if (d != "\n") { tok = tok d; have = 1 }; continue }
    if (c == "#" && !have) { while (i < n && substr(s, i + 1, 1) != "\n") i++; continue }
    if (c == " " || c == "\t") { flush(); continue }
    if (c == "\n") { flush(); if (nhd) bodies(); print "\001"; continue }
    if (c == "&" && d == ">") { flush(); i++; while (substr(s, i + 1, 1) ~ /[>|&]/) i++; print ">"; continue }
    if (c == ";" || c == "|" || c == "&" || c == "(" || c == ")") { flush(); print "\001"; continue }
    if (c == "`") { tok = tok c; have = 1; flush(); print "\001"; continue }   # a word holding ` is not literal
    if (c == "<" && d == "<" && substr(s, i + 2, 1) == "<") { flush(); i += 2; print "<<<"; continue }
    if (c == "<" && d == "<") {
      flush(); i++
      dash = 0; if (substr(s, i + 1, 1) == "-") { dash = 1; i++ }
      while (substr(s, i + 1, 1) ~ /[ \t]/) i++
      dl = ""
      while (i < n) { e = substr(s, i + 1, 1); if (e ~ /[ \t\n;|&<>()]/) break; i++; if (e != "'" && e != "\"" && e != "\\") dl = dl e }
      nhd++; hdelim[nhd] = dl; hdash[nhd] = dash
      continue
    }
    if (c == "<" || c == ">") {
      if (tok ~ /^[0-9]+$/) { tok = ""; have = 0 } else flush()
      while (substr(s, i + 1, 1) ~ /[<>&|]/) i++
      print ">"; continue
    }
    tok = tok c; have = 1
  }
  flush()
}
AWK
read -r -d '' ps_tok_awk <<'AWK'
function flush() { if (have) { gsub(/\n/, "\003", tok); print tok; tok = ""; have = 0 } }
{ s = (NR > 1) ? s "\n" $0 : $0 }
END {
  n = length(s); q = ""; tok = ""; have = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1); d = substr(s, i + 1, 1)
    if (q == "'") {
      if (c == "'" && d == "'") { tok = tok "'"; i++ } else if (c == "'") q = ""; else tok = tok c
      continue
    }
    if (q == "\"") {
      if (c == "`" && i < n) { i++; if (d != "\n") tok = tok d }
      else if (c == "\"" && d == "\"") { tok = tok "\""; i++ }
      else if (c == "\"") q = ""
      else tok = tok c
      continue
    }
    if (c == "@" && (d == "'" || d == "\"") && substr(s, i + 2, 1) == "\n") {   # a here-string (round 3)
      e = "\n" d "@"; j = index(substr(s, i + 3), e)
      if (j == 0) { tok = tok substr(s, i + 3); have = 1; i = n; continue }
      tok = tok substr(s, i + 3, j - 1); have = 1; i = i + 2 + j + 2; continue
    }
    if (c == "'" || c == "\"") { q = c; have = 1; continue }
    if (c == "`" && i < n) { i++; if (d != "\n") { tok = tok d; have = 1 }; continue }
    if (c == "#" && !have) { while (i < n && substr(s, i + 1, 1) != "\n") i++; continue }
    if (c == " " || c == "\t" || c == ",") { flush(); continue }
    if (c == "\n" || c == ";" || c == "|" || c == "&" || c == "(" || c == ")" || c == "{" || c == "}") { flush(); print "\001"; continue }
    if (c == "<" || c == ">") {
      if (tok ~ /^([0-9]+|\*)$/) { tok = ""; have = 0 } else flush()
      while (substr(s, i + 1, 1) ~ /[<>&]/) i++
      print ">"; continue
    }
    tok = tok c; have = 1
  }
  flush()
}
AWK
tag_msg="A v* tag is the ref a release is cut from, and cutting a release is the operator's decision. Push your branch and open a PR; after merge the operator creates the tag and dispatches release.yml."
tag_mode=bash; tag_depth=0
tag_dyn() { # a word this hook cannot read as written
  case "$1" in *'$'*|*'`'*|*'*'*|*'?'*|*'['*|*'{'*) return 0 ;; esac
  [ "$tag_mode" = ps ] && case "$1" in @*) return 0 ;; esac
  return 1
}
# Round 3 (timing): in-process, no process per refspec.
tag_vre='^v([0-9]+([.][0-9]+)+([-+.][0-9A-Za-z.-]*)?|[0-9]+|[A-Z][A-Za-z0-9._-]*)$'
tag_versionish() { [[ $1 =~ $tag_vre ]]; }
tag_side() { # one side of a refspec
  [ -z "$1" ] && return 0
  tag_dyn "$1" && block "a git push whose refspec ($1) cannot be read here: a variable, a substitution, a brace or a glob may name a release tag. Name the branch literally. $tag_msg" "CM-3, AIC-1, AC-5"
  case "$1" in
    refs/tags/*|tags/*) block "pushing a release tag ($1). $tag_msg" "CM-3, AIC-1, AC-5" ;;
  esac
  case "$1" in refs/*|heads/*) return 0 ;; esac
  tag_versionish "$1" && block "pushing a release tag ($1, a tag when one by that name exists). $tag_msg" "CM-3, AIC-1, AC-5"
  return 0
}
tag_cre='^([Pp][Uu][Ss][Hh][.][Ff][Oo][Ll][Ll][Oo][Ww][Tt][Aa][Gg][Ss]|[Rr][Ee][Mm][Oo][Tt][Ee][.].+[.]([Pp][Uu][Ss][Hh]|[Mm][Ii][Rr][Rr][Oo][Rr]))(=|$)'
tag_cfg() { [[ $1 =~ $tag_cre ]]; }   # a git config key that makes push send tags (in-process, round 3)
# Round 3: a word that is shaped like a release tag or a tag-sending option, used where the hook
# cannot read the command fully (a non-literal command word, a nest past the depth cap).
tag_shaped() {
  local a r
  for a in "$@"; do
    case "$a" in refs/tags/*|tags/*|*:refs/tags/*|*:tags/*|--tag|--tags|--follow-tag*|--mirr*|--fol*) return 0 ;; esac
    r=${a#+}; r=${r##*:}
    tag_versionish "$r" && return 0
  done
  return 1
}
tag_git() { # tag_git <words after git>
  local a sub="" cfg_bad="" k
  while [ "$#" -gt 0 ]; do
    a=$1; shift
    case "$a" in
      -c) [ "$#" -gt 0 ] && { tag_cfg "$1" && cfg_bad="$1"; shift; } ;;
      -c*) tag_cfg "${a#-c}" && cfg_bad="${a#-c}" ;;
      --config-env=*) tag_cfg "${a#--config-env=}" && cfg_bad="${a#--config-env=}" ;;
      --config-env) [ "$#" -gt 0 ] && { tag_cfg "$1" && cfg_bad="$1"; shift; } ;;
      -C|--git-dir|--work-tree|--namespace|--super-prefix|--attr-source) [ "$#" -gt 0 ] && shift ;;
      ">") [ "$#" -gt 0 ] && shift ;;                       # a redirect and its target (git 2>&1 push)
      -*) ;;
      *) sub=$a; break ;;
    esac
  done
  # A subcommand this hook cannot read as written may be push or tag (round 2).
  if [ -n "$sub" ] && tag_dyn "$sub"; then
    block "a git command whose subcommand ($sub) is not written literally; it may push or create a tag. Write the command out. $tag_msg" "CM-3, AIC-1, AC-5"
  fi
  case "$sub" in
    push)
      [ -n "$cfg_bad" ] && block "a git push with $cfg_bad set, which sends tags or every ref. $tag_msg" "CM-3, AIC-1, AC-5"
      local dd=0 pos=0 name want_tag=0
      while [ "$#" -gt 0 ]; do
        a=$1; shift
        if [ "$a" = ">" ]; then [ "$#" -gt 0 ] && shift; continue; fi
        if [ "$dd" -eq 0 ] && [ "$a" = "--" ]; then dd=1; continue; fi
        if [ "$dd" -eq 0 ]; then
          case "$a" in
            --no-*) continue ;;
            --*)
              name=${a#--}; name=${name%%=*}
              for k in tags follow-tags mirror; do
                case "$k" in "$name"*) block "a git push that sends tags (--$name, read as --$k: git accepts any unique prefix). $tag_msg" "CM-3, AIC-1, AC-5" ;; esac
              done
              case "$a" in *=*) ;; --repo|--receive-pack|--exec|--push-option) [ "$#" -gt 0 ] && shift ;; esac
              continue ;;
            -o) [ "$#" -gt 0 ] && shift; continue ;;
            -*) continue ;;
          esac
        fi
        if [ "$want_tag" -eq 1 ]; then
          want_tag=0
          { tag_dyn "$a" || case "$a" in v*) true ;; *) false ;; esac; } \
            && block "pushing a release tag (tag $a). $tag_msg" "CM-3, AIC-1, AC-5"
          continue
        fi
        pos=$((pos + 1))
        [ "$pos" -eq 1 ] && continue                  # the repository
        [ "$a" = "tag" ] && { want_tag=1; continue; }
        a=${a#+}
        case "$a" in
          *:*) tag_side "${a%%:*}"; tag_side "${a#*:}" ;;
          *)   tag_side "$a" ;;
        esac
      done ;;
    send-pack)
      block "git send-pack, the plumbing under git push, which can send any ref, tags included. $tag_msg" "CM-3, AIC-1, AC-5" ;;
    update-ref)
      # Round 2: a tag ref written without git tag. --stdin reads refs this hook cannot see.
      for a in "$@"; do
        case "$a" in
          --stdin) block "git update-ref --stdin, whose refs this hook cannot read; it may write a tag. $tag_msg" "CM-3, AIC-1, AC-5" ;;
          refs/tags/*|tags/*) block "writing a tag ref with git update-ref ($a). $tag_msg" "CM-3, AIC-1, AC-5" ;;
        esac
        tag_dyn "$a" && block "git update-ref with a ref this hook cannot read ($a); it may be a tag. $tag_msg" "CM-3, AIC-1, AC-5"
      done ;;
    fetch)
      # Round 2: a fetch whose refspec writes a local tag (git fetch . HEAD:refs/tags/v1).
      for a in "$@"; do
        case "$a" in *:*) case "${a#*:}" in refs/tags/*|tags/*) block "a git fetch that writes a tag ref ($a). $tag_msg" "CM-3, AIC-1, AC-5" ;; esac ;; esac
      done ;;
    tag)
      # --sort, --format and --column do not list on their own: with a name they create the
      # tag (round 2). The options that do list are the ones git documents as implying -l.
      local listing=0 tname=""
      while [ "$#" -gt 0 ]; do
        a=$1; shift
        if [ "$a" = ">" ]; then [ "$#" -gt 0 ] && shift; continue; fi
        case "$a" in
          -l|--list|-d|--delete|-v|--verify|--contains*|--no-contains*|--points-at*|--merged*|--no-merged*|-n*) listing=1 ;;
          --sort|--format|-m|-F|-u|--message|--file|--local-user|--cleanup|--trailer) [ "$#" -gt 0 ] && shift ;;
          -*) ;;
          *) [ -z "$tname" ] && tname=$a ;;
        esac
      done
      if [ "$listing" -eq 0 ] && [ -n "$tname" ]; then
        { tag_dyn "$tname" || case "$tname" in v*) true ;; *) false ;; esac; } \
          && block "creating a release tag ($tname). $tag_msg" "CM-3, AIC-1, AC-5"
      fi ;;
    config)
      local reading=0 first="" skip=0
      for a in "$@"; do
        if [ "$skip" -eq 1 ]; then skip=0; continue; fi
        case "$a" in
          --get|--get-all|--get-regexp|--get-urlmatch|--list|-l|--unset|--unset-all|--get-color|--get-colorbool) reading=1 ;;
          --comment|--type|--file|-f|--blob|--default|--value) skip=1 ;;
          -*) ;;
          *) [ -z "$first" ] && first=$a ;;
        esac
      done
      case "$first" in get|list|unset) reading=1 ;; esac
      if [ "$reading" -eq 0 ]; then
        for a in "$@"; do
          tag_cfg "$a" && block "setting $a, which makes git push send tags or every ref. $tag_msg" "CM-3, AIC-1, AC-5"
        done
      fi ;;
  esac
  return 0
}
tag_ref_field() { # $1: the flag, $2: key=value. Counts ref= fields; marks one this hook cannot trust.
  case "$2" in ref=*) ;; *) return 0 ;; esac
  refs=$((refs + 1))
  local v=${2#ref=}
  if tag_dyn "$v"; then ref_ok=0; return 0; fi
  case "$1" in -F|--field) case "$v" in @*) ref_ok=0; return 0 ;; esac ;; esac
  grep_in "$v" -qE '^refs/heads/[A-Za-z0-9._/-]+$' || ref_ok=0
  return 0
}
tag_ghapi() { # tag_ghapi <words after gh api>
  local a method="" body=0 input=0 ep="" refs=0 ref_ok=1 k ch v
  while [ "$#" -gt 0 ]; do
    a=$1; shift
    if [ "$a" = ">" ]; then [ "$#" -gt 0 ] && shift; continue; fi
    case "$a" in
      -X|--method) [ "$#" -gt 0 ] && { method=$1; shift; } ;;
      --method=*) method=${a#--method=} ;;
      -f|-F|--field|--raw-field)
        body=1
        if [ "$#" -gt 0 ]; then tag_ref_field "$a" "$1"; shift; fi ;;
      --field=*|--raw-field=*)
        body=1; tag_ref_field "${a%%=*}" "${a#*=}" ;;
      --input) body=1; input=1; [ "$#" -gt 0 ] && shift ;;
      --input=*) body=1; input=1 ;;
      --header|--jq|--template|--cache|--preview|--hostname) [ "$#" -gt 0 ] && shift ;;
      --*) ;;
      -?*)
        # Round 2: a cluster of short flags, read letter by letter the way gh reads it. A
        # letter that takes a value takes the rest of the word, or the next word.
        k=1
        while [ "$k" -lt "${#a}" ]; do
          ch=${a:k:1}
          case "$ch" in
            X|f|F|H|q|t|p)
              v=${a:k+1}
              if [ -z "$v" ] && [ "$#" -gt 0 ]; then v=$1; shift; fi
              case "$ch" in
                X) method=$v ;;
                f|F) body=1; tag_ref_field "-$ch" "$v" ;;
              esac
              break ;;
          esac
          k=$((k + 1))
        done ;;
      *) [ -z "$ep" ] && ep=$a ;;
    esac
  done
  # A write: a write method, or a body with no explicit GET. A method this hook cannot read is a write.
  case "$method" in
    [Gg][Ee][Tt]) return 0 ;;
    "") [ "$body" -eq 0 ] && return 0 ;;
  esac
  # Round 2: the endpoint in any case, with any scheme, host and port, a fragment or a
  # query, and by repository id.
  ep=${ep,,}; ep=${ep%%\#*}; ep=${ep%%\?*}
  case "$ep" in http://*|https://*) ep=${ep#*://}; case "$ep" in */*) ep=/${ep#*/} ;; *) ep="" ;; esac ;; esac
  while case "$ep" in *//*) true ;; *) false ;; esac; do ep=${ep//\/\//\/}; done
  ep=${ep#/}; while case "$ep" in */) true ;; *) false ;; esac; do ep=${ep%/}; done
  local R='^(repos/[^/]+/[^/]+|repositories/[^/]+)'
  grep_in "$ep" -qE "$R/git/tags\$" \
    && block "creating a tag object through gh api. $tag_msg" "CM-3, AIC-1, AC-5"
  grep_in "$ep" -qE "$R/git/refs/tags(/|\$)" \
    && block "writing a tag ref through gh api. $tag_msg" "CM-3, AIC-1, AC-5"
  if grep_in "$ep" -qE "$R/git/refs\$"; then
    { [ "$input" -eq 1 ] || [ "$refs" -ne 1 ] || [ "$ref_ok" -eq 0 ]; } \
      && block "creating a ref through gh api that is not one literal ref=refs/heads/<branch> (a tag, a variable, a file, --input or more than one ref). $tag_msg" "CM-3, AIC-1, AC-5"
  fi
  return 0
}
# Round 4 (timing, keel #192 / binnacle #87): a nested shell, pwsh -c, cmd /c, eval or iex runs
# this whole judge again on its text, and the tokenizer is a process. 300 `pwsh -c Write-Host hi`
# lines took 342 s on Git Bash (main 4.5 s). Nested text is judged only when it could reach a
# rule below: a word this judge acts on (git, gh, a tag-writing subcommand, an encoded command)
# or a word shaped like a release tag. In-process; the text is read with its quoting and escape
# characters removed, so `g"i"t` and `pu`sh` still count.
tag_ere='(^|[[:space:];|&(])-e(c|n[a-z]*)?([[:space:]]|$)'   # pwsh -e / -ec / -EncodedCommand
tag_gate() { # $1: nested command text -> true when it must be judged
  local t=$1 r=0 deep=()
  t=${t//$'\\\n'/}   # round 5: a backslash-newline joins the words around it, as the shell does
  t=${t//[\'\"\`\\^\$]/}
  shopt -s nocasematch
  case "$t" in
    *git*|*gh*|*push*|*tag*|*send-pack*|*update-ref*|*fetch*|*config*|*api*) r=1 ;;
  esac
  [ "$r" -eq 0 ] && [[ $t =~ $tag_ere ]] && r=1
  shopt -u nocasematch
  [ "$r" -eq 1 ] && return 0
  read -r -a deep <<< "${t//[;|&(){}<>=,]/ }"
  tag_shaped "${deep[@]}"
}
tag_guard() { # $1: bash|ps, $2: the command text
  local toks=() seg=() t mode_was=$tag_mode src=$2
  # Round 5: the tokenizers mark commands and heredoc bodies with \001-\003; one written into the
  # text would end a command or drop a word. As ? it is a word this hook cannot read.
  src=${src//[$'\001\002\003']/?}
  [ "$tag_depth" -gt 0 ] && ! tag_gate "$src" && return 0
  tag_depth=$((tag_depth + 1))
  if [ "$tag_depth" -gt 8 ]; then
    # Round 3: past the cap, refuse only when a word shaped like a release tag (or a tag-sending
    # option) appears; an ordinary deep nest is left to the rest of this hook, as on main.
    local deep=() ; read -r -a deep <<< "${src//[\'\"]/ }"
    if tag_shaped "${deep[@]}"; then
      block "a command nested more than 8 levels deep that names a release tag; this hook cannot read it. Run it directly. $tag_msg" "CM-3, AIC-1, AC-5"
    fi
    tag_depth=$((tag_depth - 1)); return 0
  fi
  tag_mode=$1
  if [ "$1" = ps ]; then
    # (Get-Command git).Source and its spellings run git. (Round 4: sed only when one is there.)
    shopt -s nocasematch; [[ $src == *gcm* || $src == *get-command* ]] && src=$(printf '%s' "$src" | sed -E 's/\([[:space:]]*([Gg][Ee][Tt]-[Cc][Oo][Mm][Mm][Aa][Nn][Dd]|[Gg][Cc][Mm])([[:space:]]+-[A-Za-z]+)*[[:space:]]+["'"'"']?([^()"'"'"'[:space:]]+)["'"'"']?[[:space:]]*\)[.][A-Za-z]+/ \3 /g'); shopt -u nocasematch
    mapfile -t toks < <(printf '%s' "$src" | LC_ALL=C awk "$ps_tok_awk")
  else
    mapfile -t toks < <(printf '%s' "$src" | LC_ALL=C awk "$tok_awk")
  fi
  toks+=($'\001')
  for t in "${toks[@]}"; do
    if [ "$t" = $'\001' ]; then
      [ "${#seg[@]}" -gt 0 ] && tag_seg "${seg[@]}"
      seg=(); continue
    fi
    seg+=("${t//$'\003'/$'\n'}")
  done
  tag_mode=$mode_was; tag_depth=$((tag_depth - 1))
}
tag_names_ref_cmd() { # true when a word among $@ is a git subcommand that can write a tag
  local a; for a in "$@"; do case "$a" in push|tag|send-pack|update-ref|fetch|config) return 0 ;; esac; done; return 1
}
# No process per word (the #62031 T1 lesson): a word is classified in any case with
# nocasematch (bash 3.1+), set only inside these two helpers, into a lower-case name.
tag_pre() { # $1: a word before the command -> tag_pre_out: skip | assign | <wrapper> | ""
  local x
  tag_pre_out=""
  shopt -s nocasematch
  case "$1" in
    '{'|'}'|'!'|if|then|else|elif|do|while|until|time|'&'|'.'|'$env:'*=*) tag_pre_out=skip ;;
    *)
      for x in env command builtin exec nohup sudo doas nice timeout stdbuf xargs; do
        [[ $1 == "$x" ]] && { tag_pre_out=$x; break; }
      done ;;
  esac
  shopt -u nocasematch
  if [ -z "$tag_pre_out" ] && [[ $1 =~ ^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?[+]?= ]]; then tag_pre_out=assign; fi
  return 0
}
tag_cmdkind() { # $1: a command name, path and .exe removed -> tag_cmdkind_out
  tag_cmdkind_out=""
  shopt -s nocasematch
  case "$1" in
    sh|bash|dash|zsh|ash|ksh) tag_cmdkind_out="sh" ;;
    pwsh|powershell) tag_cmdkind_out=pwsh ;;
    cmd) tag_cmdkind_out=cmd ;;
    eval) tag_cmdkind_out="eval" ;;
    iex|invoke-expression) tag_cmdkind_out=iex ;;
    start-process|saps|start) tag_cmdkind_out=start ;;
    git) tag_cmdkind_out=git ;;
    gh) tag_cmdkind_out=gh ;;
  esac
  shopt -u nocasematch
  return 0
}
tag_seg() { # $@: the words of one simple command
  local w=() bodies=() hs=() a lw base i=0 n k xargs=0 rest
  while [ "$#" -gt 0 ]; do
    a=$1; shift
    case "$a" in
      $'\002'*) bodies+=("${a#?}") ;;
      "<<<") [ "$#" -gt 0 ] && { hs+=("$1"); shift; } ;;
      *) w+=("$a") ;;
    esac
  done
  n=${#w[@]}
  # The words before the command: assignments, keywords and wrappers that run the rest.
  while [ "$i" -lt "$n" ]; do
    a=${w[i]}
    # Round 3: a PowerShell assignment, `$name = git ...`: judge the command after the `=`.
    if [ "$tag_mode" = ps ] && [[ $a == '$'* ]] && [ "${w[i+1]:-}" = "=" ]; then i=$((i + 2)); continue; fi
    tag_pre "$a"; lw=$tag_pre_out
    case "$lw" in skip|assign) i=$((i + 1)); continue ;; esac
    case "$lw" in
      env|command|builtin|exec|nohup|sudo|doas|nice|timeout|stdbuf|xargs)
        [ "$lw" = xargs ] && xargs=1
        i=$((i + 1))
        while [ "$i" -lt "$n" ]; do
          case "${w[i]}" in
            -I|-n|-L|-P|-d|-E|-s|-a|-u|-g|-C|-k|--signal|--kill-after|--user|--group|-i|-o|-e) [ "$lw" = env ] && [ "${w[i]}" != -u ] && [ "${w[i]}" != -C ] && { i=$((i + 1)); continue; }; i=$((i + 2)) ;;
            -*) i=$((i + 1)) ;;
            *=*) [ "$lw" = env ] && i=$((i + 1)) || break ;;
            *) break ;;
          esac
        done
        [ "$lw" = timeout ] && [ "$i" -lt "$n" ] && i=$((i + 1))  # the duration
        continue ;;
    esac
    break
  done
  [ "$i" -ge "$n" ] && return 0
  a=${w[i]}; base=${a##*/}; base=${base##*\\}; base=${base%.[Ee][Xx][Ee]}; tag_cmdkind "$base"; lw=$tag_cmdkind_out
  # A command word this hook cannot read, followed by words a tag write needs (round 2).
  # Round 3 (false positives against main): `[ -f config ]`, `"$PYTHON" -m pip config list` and
  # `$DOCKER push image` are not a git push. A non-literal command word is refused only with a
  # tag-capable subcommand AND a word shaped like a release tag after it.
  if [ "$a" != "[" ] && [ "$a" != "[[" ] && tag_dyn "$a" && tag_names_ref_cmd "${w[@]:i+1}" && tag_shaped "${w[@]:i+1}"; then
    block "a command whose name ($a) is not written literally, with arguments that can push or create a tag. Write the command out. $tag_msg" "CM-3, AIC-1, AC-5"
  fi
  case "$lw" in
    sh)
      for ((k = i + 1; k < n; k++)); do
        case "${w[k]}" in
          -*c*) [ $((k + 1)) -lt "$n" ] && tag_guard bash "${w[k+1]}"; return 0 ;;
          -*) ;;
          *) return 0 ;;                                    # a script file
        esac
      done
      for a in "${bodies[@]}" "${hs[@]}"; do tag_guard bash "$a"; done ;;
    pwsh)
      for ((k = i + 1; k < n; k++)); do
        case "${w[k],,}" in
          -c|-co*) rest="${w[*]:k+1}"; tag_guard ps "$rest"; return 0 ;;
          -e|-ec|-en*) case "${w[*]:k+1}" in *) block "a PowerShell -EncodedCommand, which this hook cannot read. Run the command directly. $tag_msg" "CM-3, AIC-1, AC-5" ;; esac ;;
          -*) ;;
          *) return 0 ;;
        esac
      done
      for a in "${bodies[@]}" "${hs[@]}"; do tag_guard ps "$a"; done ;;
    cmd)
      for ((k = i + 1; k < n; k++)); do
        case "${w[k]}" in /[cCkK]) rest="${w[*]:k+1}"; tag_guard "$tag_mode" "$rest"; return 0 ;; esac   # once per level (round 3)
      done ;;
    eval) rest="${w[*]:i+1}"; tag_guard "$tag_mode" "$rest" ;;
    iex)
      rest=""; for ((k = i + 1; k < n; k++)); do case "${w[k]}" in -[Cc]*) ;; *) rest="$rest ${w[k]}" ;; esac; done
      tag_guard ps "$rest" ;;
    start)
      rest=""; for ((k = i + 1; k < n; k++)); do
        case "${w[k],,}" in
          -filepath|-file*|-argumentlist|-arg*|-wait|-nonewwindow|-passthru|-noprofile) ;;
          -workingdirectory|-verb|-windowstyle|-redirectstandard*|-credential) k=$((k + 1)) ;;
          *) rest="$rest ${w[k]}" ;;
        esac
      done
      tag_guard ps "$rest" ;;
    git)
      if [ "$xargs" -eq 1 ] && tag_names_ref_cmd "${w[@]:i+1}"; then
        block "xargs git with a subcommand that can push or create a tag: the refs come from input this hook cannot read. Name them in the command. $tag_msg" "CM-3, AIC-1, AC-5"
      fi
      tag_git "${w[@]:i+1}" ;;
    gh)
      [ "${w[i+1]:-}" = "api" ] && tag_ghapi "${w[@]:i+2}" ;;
  esac
  return 0
}

cmd="$raw_cmd"; guard
guard_read_tool_name   # TheHub #62258: on first use, after the rules that block without it
case "$tool_name" in
  Bash) tag_guard bash "$tag_src" ;;
  PowerShell) tag_guard ps "$tag_src" ;;
  *) tag_guard bash "$tag_src" ;;   # no tool named: the Bash tool (the PowerShell tool always names itself)
esac
if [ "$word_cmd" != "$raw_cmd" ]; then cmd="$word_cmd"; guard; fi
if [ "$ps_cmd" != "$raw_cmd" ] && [ "$ps_cmd" != "$word_cmd" ]; then cmd="$ps_cmd"; guard; fi
# T1 (review round 3): the judge runs only when git can be a command word: "git" at the start,
# or after a separator, a space, a quote, a path or an opening bracket, followed by an end, a
# space, a quote or .exe. A heredoc that merely mentions git in prose still pays the
# tokenizer once, never a process per word.
push_gate='(^|[][[:space:];&|(){}`"'"'"'/\\=!])[Gg][Ii][Tt]([.][Ee][Xx][Ee])?([[:space:];&|()`"'"'"']|$)'
if [[ $raw_cmd =~ $push_gate ]] || { [ "$ps_cmd" != "$raw_cmd" ] && [[ $ps_cmd =~ $push_gate ]]; }; then
  push_moves=0; push_guard "$raw_cmd"
  if [ "$ps_cmd" != "$raw_cmd" ]; then push_moves=0; push_guard "$ps_cmd"; fi
fi
# Round 4 (timing): the word judge runs only when a view names a container engine at all,
# tested in-process. It used to run whenever the PowerShell view differed, which is most commands.
ctr_eng_re='[Dd][Oo][Cc][Kk][Ee][Rr]|[Pp][Oo][Dd][Mm][Aa][Nn]|[Nn][Ee][Rr][Dd][Cc][Tt][Ll]'
if [[ $raw_cmd =~ $ctr_eng_re ]] || [[ $ps_cmd =~ $ctr_eng_re ]]; then
  ctr_guard "$raw_cmd"   # round 3: the quote-aware tokenizer reads the raw text; the masked view turns a quoted && into spaces
  [ "$ps_cmd" != "$raw_cmd" ] && ctr_guard "$ps_cmd"
fi

guard_allow   # the verdict, and the last line of this file (TheHub #62264)
