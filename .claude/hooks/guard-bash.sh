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
  [ "$rc" -eq 141 ] && return 0
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
  exit "$rc"
}
trap guard_exit EXIT

payload="$(cat)"

# Decode a JSON string body (the sed fallback below hands over the raw escapes).
# \uXXXX is left as it is.
read -r -d '' json_unescape_awk <<'AWK'
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
      else if (d == "u") c = "\\u"; else if (d == "b" || d == "f") c = " "; else c = d
    }
    printf "%s", c
  }
}
AWK

# Extract the command. Prefer jq; fall back to a tolerant sed for environments without it.
# `type -P`, not `command -v`: jq() is a wrapper function now (#61794), and `command -v`
# would report it even where no jq binary exists.
if type -P jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')"
  payload_cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty')"
else
  # TheHub #61038 review: take the JSON string itself (not everything up to the
  # payload's last quote, which swallowed the "description" field) and decode it, so
  # this mode sees the command jq would. Undecoded, \" is not a quote and \n is not a
  # newline, and the quote-aware view below could not tell what is quoted.
  cmd="$(printf '%s' "$payload" | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p')"
  payload_cwd="$(printf '%s' "$payload" | sed -nE 's/.*"cwd"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | sed 's/\\\\/\\/g')"
  cmd_json="$cmd"
  cmd="$(printf '%s' "$cmd_json" | LC_ALL=C awk "$json_unescape_awk" 2>/dev/null)" || cmd="$cmd_json"
fi

[ -z "$cmd" ] && exit 0

# TheHub #61038 review: a backslash-newline continues the command, for every command.
# This was done for curl only, so `gh api --method POST \<newline> .../pending_deployments`
# put the endpoint on a line of its own, which no gh api rule read.
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
  norm+=(-e 's#"([^"]*[/\\])?'"$pat"'(\.[Ee][Xx][Ee])?"#'"$name"'#g'
         -e "s#'([^']*[/\\\\])?$pat(\\.[Ee][Xx][Ee])?'#$name#g"
         -e 's#(^|[|;&[:space:](`"'"'"'])\\?([^[:space:]|;&()`"'"'"'<>]*[/\\])?'"$pat"'(\.[Ee][Xx][Ee])?([[:space:])`"'"'"'|;&]|$)#\1'"$name"'\4#g')
done
norm+=(-e 's#(gh[[:space:]]+alias[[:space:]]+set([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^[:space:]-][^[:space:]]*[[:space:]]+)(["'"'"']?)#\1\3gh #g')
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
function guard_nextnl(i) { while (guard_nl[guard_nc] < i) guard_nc++; return guard_nl[guard_nc] }
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
        -e 's#\(([Gg][Ee][Tt]-[Cc][Oo][Mm][Mm][Aa][Nn][Dd]|[Gg][Cc][Mm])([[:space:]]+-[A-Za-z]+)*[[:space:]]+([^()[:space:]]+)[[:space:]]*\)(\.[A-Za-z]+)?# \3 #g')
ps_cmd="$(printf '%s' "$raw_cmd" | LC_ALL=C awk "$ps_awk" 2>/dev/null | sed -E "${ps_sed[@]}" | normalize)" || ps_cmd="$raw_cmd"

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
if printf '%s' "$cmd" | grep -qE "$B"'git[[:space:]]+[^|;&]*(commit|push|merge)[^|;&]*[[:space:]]--no-verify\b' \
   || printf '%s' "$cmd" | grep -qE "$B"'git[[:space:]]+(commit|push)[[:space:]]+[^|;&]*[[:space:]]-[a-zA-Z]*n'"$E"; then
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
  printf '%s' "$cmd" | grep -qE "$1"
}

# TheHub #61038 second review: `gh alias import FILE` defines aliases from a YAML file,
# one `name: body` per line. Each body is a gh command (or `!gh ...` for a shell
# alias), so it is read and judged with the rest; a file this hook cannot read (stdin,
# a missing file) is refused. `gh alias set` is handled in normalize() above.
if g "$B"'gh[[:space:]]+alias[[:space:]]+import\b'; then
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
g "$B"'git[[:space:]]+([^|;&]*[[:space:]])?push[[:space:]]([^|;&]*[[:space:]])?--?(force|f)(-with-lease)?\b' \
  && block "force push. Published history is immutable — it is the AU-12 audit trail." "AIC-3, AU-12, SI-7"
g "$B"'git[[:space:]]+([^|;&]*[[:space:]])?reset([[:space:]]|$)[^|;&]*--hard\b' \
  && block "git reset --hard. Discards work irrecoverably; use git revert or a branch." "AIC-3"
g "$B"'git[[:space:]]+(filter-branch|filter-repo)\b' \
  && block "history rewrite. Destroys the attributable, signed commit record." "AU-12, SI-7"
g "$B"'git[[:space:]]+([^|;&]*[[:space:]])?push([[:space:]]+[^|;&]*)?[[:space:]](origin[[:space:]]+)?(HEAD:)?(main|master)'"$E" \
  && block "direct push to main. All change goes through a reviewed PR." "AC-5, CM-5"
# TheHub #62031: main as a refspec's destination. `git push origin feat:main` (or
# HEAD:refs/heads/main, +x:main, :main, refs/heads/main) moves main just as `git push origin
# main` does, and with enforce_admins off and the agents pushing as the owner it lands with no
# check at all. A `+` refspec is a force push of that ref, whatever the flags say. A git
# commit's -n is --no-verify inside a cluster of flags too (-an, -anm), not only on its own;
# -mnotes is a message, not -n, because m takes the rest of the word as its value.
GIT_PUSH_SEG="$B"'git[[:space:]]+([^|;&]*[[:space:]])?push[[:space:]]([^|;&]*[[:space:]])?'
g "$GIT_PUSH_SEG"'\+?[^[:space:]:]*:(refs/heads/)?(main|master)'"$E" \
  && block "a push to main through a refspec (src:main). All change goes through a reviewed PR." "AC-5, CM-5"
g "$GIT_PUSH_SEG"'\+?refs/heads/(main|master)'"$E" \
  && block "direct push to main (refs/heads/main). All change goes through a reviewed PR." "AC-5, CM-5"
g "$GIT_PUSH_SEG"'\+[^[:space:]]' \
  && block "force push (a + refspec). Published history is immutable — it is the AU-12 audit trail." "AIC-3, AU-12, SI-7"
# A push that names no ref, or names HEAD, pushes the CURRENT branch: `git push`, `git push
# origin`, `git push -u origin HEAD`. On a checkout that is on main that is a push to main,
# and the likeliest real one. The branch is read where the push runs (the payload's cwd, or
# git -C <dir>), with git through a fault-recording wrapper: a git that cannot answer blocks.
guard_push_current() { # $1: one invocation; true if it pushes the current branch
  local w pos=0 skip=0 head=0 seen=0
  for w in $1; do
    if [ "$seen" -eq 0 ]; then [ "$w" = "push" ] && seen=1; continue; fi
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    case "$w" in
      -o|--push-option|--repo|--receive-pack|--exec) skip=1 ;;
      -*) ;;
      HEAD) head=1; pos=$((pos + 1)) ;;
      *) pos=$((pos + 1)) ;;
    esac
  done
  [ "$seen" -eq 1 ] && { [ "$pos" -le 1 ] || [ "$head" -eq 1 ]; }
}
if g "$GIT_PUSH_SEG" || g "$B"'git[[:space:]]+([^|;&]*[[:space:]])?push'"$E"; then
  while IFS= read -r guard_seg; do
    printf '%s' "$guard_seg" | grep -qE "$B"'git[[:space:]]+([^|;&]*[[:space:]])?push([[:space:]]|$)' || continue
    guard_push_current "$guard_seg" || continue
    guard_dir="${payload_cwd:-$PWD}"
    guard_c=$(printf '%s' "$guard_seg" | grep -oE "$B"'git[[:space:]]+-C[[:space:]]+[^[:space:]]+' | head -n1 | sed -E 's/.*-C[[:space:]]+//')
    if [ -n "$guard_c" ]; then case "$guard_c" in /*|[A-Za-z]:[/\\]*) guard_dir=$guard_c ;; *) guard_dir="$guard_dir/$guard_c" ;; esac; fi
    guard_branch=$(guard_run git 1 -C "$guard_dir" symbolic-ref --short -q HEAD)
    case "$guard_branch" in
      main|master) block "a push of the current branch, which is $guard_branch (in $guard_dir). All change goes through a reviewed PR: push a feature branch." "AC-5, CM-5" ;;
    esac
  done <<< "$(printf '%s' "$cmd" | tr '|;&' '\n\n\n')"
fi
g "$B"'git[[:space:]]+([^|;&]*[[:space:]])?commit[[:space:]]([^|;&]*[[:space:]])?-[aeiopqsvzn]*n[a-zA-Z]*'"$E" \
  && block "hook bypass (-n on a git commit, alone or in a cluster of flags). Fix the cause the hook found." "AIC-3, IA-5"

# Self-approval and self-merge — the control that makes every gate meaningful
g "$B"'gh[[:space:]]+pr[[:space:]]+review\b[^|;&]*--approve\b' \
  && block "approving a PR. Agents recommend; a human or a separate identity approves." "AC-5, AIC-2"
g "$B"'gh[[:space:]]+pr[[:space:]]+merge\b' \
  && block "merging a PR. Merge happens after independent review, via GitHub." "AC-5, CM-5, AIC-2"
g "$B"'gh[[:space:]]+release[[:space:]]+(create|edit|delete)\b' \
  && block "creating a release. G5 requires human authorization via the Environment." "CM-3, AIC-1"

# Weakening a security control
g 'continue-on-error:[[:space:]]*true' \
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
  g "$B"'gh[[:space:]]+api\b' || return 1
  printf '%s' "$cmd" | grep -qE "$GH_M$GH_WRITE" && return 0
  printf '%s' "$cmd" | tr '|;&' '\n' \
    | grep -E "$B"'gh[[:space:]]+api\b' \
    | grep -E '[[:space:]](-i*[fF]|--(raw-)?field([=[:space:]]|$)|--input([=[:space:]]|$))' \
    | grep -qvE "$GH_M"'[A-Za-z]'
}

# Second review: a body flag supplied by $(...), backticks or an array expansion
# (gh api .../pending_deployments $(printf -- '-f state=approved')) cannot be seen, so
# a call to these endpoints that carries one and is not an explicit GET is refused.
if g "$B"'gh[[:space:]]+api\b'; then
  # The endpoint path itself is dropped first: a run id from $(gh run list ...) in a
  # listing is still a read.
  printf '%s' "$cmd" | tr '|;&' '\n' | grep -E "$B"'gh[[:space:]]+api\b' | grep -E "$DEPLOY_REVIEW" \
    | sed -E 's#[^[:space:]]*/actions/runs/[^[:space:]]*/(pending_deployments|deployment_protection_rule)##' \
    | grep -E '\$\(|`|\[[@*]\]' | grep -qvE "$GH_M"'[Gg][Ee][Tt]\b' \
    && block "a gh api call to an environment deployment review whose arguments come from \$(...), backticks or an array. Its method cannot be read here; list pending deployments with a plain GET." "CM-3, AC-5, AIC-1, AIC-2"
fi

if gh_api_write; then
  g "$B"'gh[[:space:]]+api[^|;&]*/pulls/[^|;&/]+/merge([^A-Za-z0-9_-]|$)' \
    && block "merging a PR through gh api. Merge happens after independent review, via GitHub." "AC-5, CM-5, AIC-2"
  g "$B"'gh[[:space:]]+api[^|;&]*/pulls/[^|;&/]+/reviews([^A-Za-z0-9_-]|$)' \
    && block "reviewing a PR through gh api. Agents recommend; a human or a separate identity approves. Use gh pr comment to say something." "AC-5, AIC-2"
  g "$B"'gh[[:space:]]+api[^|;&]*/releases([^A-Za-z0-9_-]|$)' \
    && block "creating or changing a release through gh api. G5 requires human authorization via the Environment." "CM-3, AIC-1"
  g "$B"'gh[[:space:]]+api[^|;&]*/branches/[^|;&]*/protection' \
    && block "removing branch protection. This enforces separation of duties." "AC-5, CM-5"
  g "$B"'gh[[:space:]]+api[^|;&]*/rulesets([^A-Za-z0-9_-]|$)' \
    && block "changing a ruleset. Rulesets are branch protection under a newer name, and the same separation of duties rests on them." "AC-5, CM-5"
  g "$B"'gh[[:space:]]+api[^|;&]*/(actions|codespaces|dependabot)/secrets' \
    && block "writing a secret through gh api. Agents never touch secrets; escalate to a human." "AIC-5, IA-5"
  g "$B"'gh[[:space:]]+api[^|;&]*/environments([^A-Za-z0-9_-]|$)' \
    && block "changing a deployment environment. Its reviewers ARE the G5 authorization gate." "CM-3, AC-5, AIC-1"
  # TheHub #61038: approving the deployment is the gate itself, not its configuration.
  g "$B"'gh[[:space:]]+api[^|;&]*'"$DEPLOY_REVIEW" \
    && block "approving or rejecting an environment deployment through gh api. Only a human reviews a deployment; the environment's reviewers ARE the G5 authorization gate." "CM-3, AC-5, AIC-1, AIC-2"
  # Second review, run-time values (the cheap part of TheHub #61039): the endpoint named
  # anywhere in the command, not only in the gh api call (P=.../pending_deployments;
  # gh api -X POST $P, or piped to xargs gh api), and an action segment that is a
  # variable (.../runs/1/$E). A run id in a variable (.../runs/$ID/rerun) stays allowed.
  { g "$DEPLOY_REVIEW" || g "$B"'gh[[:space:]]+api[^|;&]*/actions/runs/[^|;&/[:space:]]+/\$'; } \
    && block "a gh api write in a command that names an environment deployment review, or whose action is a variable. Only a human reviews a deployment." "CM-3, AC-5, AIC-1, AIC-2"
  # #127: the push-to-main rule knew one spelling, git push. These three reach main
  # through the REST API instead.
  g "$B"'gh[[:space:]]+api[^|;&]*/git/refs/heads/(main|master)'"$E" \
    && block "moving main through the git refs API. All change goes through a reviewed PR." "AC-5, CM-5"
  # The value a -f/-F/--field/--raw-field flag gives to field $1, if any.
  api_field() { printf '%s' "$cmd" \
    | grep -oE '(-[fF][[:space:]]*|--(raw-)?field[[:space:]=]+)'"$1"'=[^[:space:]|;&)`"'"'"']+' \
    | head -n1 | sed -E 's/^[^=]*=//'; }
  is_main() { printf '%s' "$1" | grep -qE '^(refs/heads/)?(main|master)$'; }
  # A contents write is a commit. With no branch field it lands on the default branch.
  if g "$B"'gh[[:space:]]+api[^|;&]*/contents/'; then
    br=$(api_field branch)
    { [ -z "$br" ] || is_main "$br"; } \
      && block "a commit to main through the contents API (it commits to the default branch when no branch is named). All change goes through a reviewed PR; pass -f branch=<feature>." "AC-5, CM-5"
  fi
  if g "$B"'gh[[:space:]]+api[^|;&]*/merges'"$E"; then
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
  printf '%s' "$gql" | grep -qE '(^|[^A-Za-z0-9_])mutation([^A-Za-z0-9_]|$)' || return 0
  m() { printf '%s' "$gql" | grep -qE '(^|[^A-Za-z0-9_])('"$1"')([^A-Za-z0-9_]|$)'; }
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
  m 'updateRefs?' \
    && block "moving a ref through GraphQL$via. A ref id may be main; push a feature branch with git." "AC-5, CM-5"
  if m 'createCommitOnBranch'; then
    { printf '%s' "$gql" | grep -qE '(^|[^A-Za-z0-9_/.-])(refs/heads/)?(main|master)([^A-Za-z0-9_/.-]|$)' \
      || ! printf '%s' "$gql" | grep -qE '(^|[^A-Za-z0-9_])branchName([^A-Za-z0-9_]|$)'; } \
      && block "a commit to main through GraphQL$via (or to a branch named only by id). All change goes through a reviewed PR." "AC-5, CM-5"
  fi
  return 0
}
if g "$B"'gh[[:space:]]+api[[:space:]]+([^|;&]*[[:space:]])?graphql'"$E"; then
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
  printf '%s' "$seg" | grep -qiE "$B$PS_HTTP"'([[:space:]]|$)' \
    && printf '%s' "$seg" | grep -qE '(^|[[:space:]])@[A-Za-z_]' && return 0
  ms=$(printf '%s' "$seg" | grep -oE "$curl_m"'[$(A-Za-z][A-Za-z]*' | sed -E "s/^$curl_m//"
       printf '%s' "$seg" | grep -oE "$ps_m"'[$(A-Za-z][A-Za-z]*' | sed -E "s/^$ps_m//")
  if [ -n "$ms" ]; then
    printf '%s\n' "$ms" | grep -qvxE '[Gg][Ee][Tt]|[Hh][Ee][Aa][Dd]'
    return
  fi
  printf '%s' "$seg" | grep -qiE "$B"'curl([[:space:]]|$)' || return 1
  printf '%s' "$seg" | grep -qE '[[:space:]](-[a-zA-Z]*[dFTK]|--data|--json|--form|--upload-file|--config)' || return 1
  printf '%s' "$seg" | grep -qE '[[:space:]](-[a-zA-Z]*G|--get)([[:space:]]|$)' && return 1
  return 0
}

if g "$B"'curl([[:space:]]|$)' || printf '%s' "$cmd" | grep -qiE "$B$PS_HTTP"'([[:space:]]|$)'; then
  curl_segs=$(printf '%s' "$cmd" | tr '|;&' '\n' | grep -iE "$B"'(curl|'"$PS_HTTP"')([[:space:]]|$)')
  # TheHub #61038 review: a GraphQL document sent from a file (-d @file, --data-binary
  # @file, --json @file, -T file, -K config) is read, or refused when it cannot be --
  # stdin, a missing file -- exactly as the gh api graphql rule does. TheHub #61064:
  # and a cmdlet's -InFile file, or a -Body read with (Get-Content FILE) / (gc FILE).
  curl_text="$curl_segs"
  curl_gql=$(printf '%s\n' "$curl_segs" | grep -E '/graphql([^A-Za-z0-9_-]|$)')
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
  printf '%s' "$curl_text" | grep -qE '(^|[^A-Za-z0-9_])(approve|reject)Deployments([^A-Za-z0-9_]|$)' \
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
  if g "$DEPLOY_REVIEW" || g "$HTTP_GH"; then
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
  curl_main() { printf '%s' "$1" | grep -qE '^(refs/heads/)?(main|master)$'; }
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
    cu() { printf '%s\n' "$cu_text" | grep -qE "$1"; }
    cu "$DEPLOY_REVIEW"'|/actions/runs/[^|;&/[:space:]]+/[^[:space:]]*[][{}]' \
      && block "approving or rejecting an environment deployment through curl. Only a human reviews a deployment; the environment's reviewers ARE the G5 authorization gate." "CM-3, AC-5, AIC-1, AIC-2"
    cu '^CURL_GLOB_OVERFLOW$' \
      && block "a curl write whose URL glob is too large to read here. Name the endpoint without {} or [] globs." "AC-5, CM-5"
    cu '/pulls/[^/[:space:]]+/merge([^A-Za-z0-9_-]|$)' \
      && block "merging a PR through curl. Merge happens after independent review, via GitHub." "AC-5, CM-5, AIC-2"
    cu '/pulls/[^/[:space:]]+/reviews([^A-Za-z0-9_-]|$)' \
      && block "reviewing a PR through curl. Agents recommend; a human or a separate identity approves. Use gh pr comment to say something." "AC-5, AIC-2"
    cu '/releases([^A-Za-z0-9_-]|$)' \
      && block "creating or changing a release through curl. G5 requires human authorization via the Environment." "CM-3, AIC-1"
    cu '/branches/[^[:space:]]*/protection' \
      && block "changing branch protection through curl. This enforces separation of duties." "AC-5, CM-5"
    cu '/rulesets([^A-Za-z0-9_-]|$)' \
      && block "changing a ruleset through curl. Rulesets are branch protection under a newer name, and the same separation of duties rests on them." "AC-5, CM-5"
    cu '/(actions|codespaces|dependabot)/secrets' \
      && block "writing a secret through curl. Agents never touch secrets; escalate to a human." "AIC-5, IA-5"
    cu '/environments([^A-Za-z0-9_-]|$)' \
      && block "changing a deployment environment through curl. Its reviewers ARE the G5 authorization gate." "CM-3, AC-5, AIC-1"
    cu '/git/refs/heads/(main|master)([^A-Za-z0-9_./-]|$)' \
      && block "moving main through the git refs API with curl. All change goes through a reviewed PR." "AC-5, CM-5"
    # A contents write is a commit; with no branch in the body it lands on the
    # default branch. A body this hook cannot see (a file) names no branch.
    if cu '/contents/'; then
      br=$(curl_field "$seg" branch)
      { [ -z "$br" ] || curl_main "$br"; } \
        && block "a commit to main through the contents API with curl (it commits to the default branch when the body names no branch). All change goes through a reviewed PR; put \"branch\":\"<feature>\" in an inline body." "AC-5, CM-5"
    fi
    if cu '/merges([^A-Za-z0-9_-]|$)'; then
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
if printf '%s' "$cmd" | grep -qE "$B"'(cat|less|more|head|tail|bat|type)[[:space:]]+[^|;&]*([.]env([.][A-Za-z0-9_-]+)?|[.]pem|[.]p12|[.]pfx|[.]key|/[.]ssh/|/[.]aws/|id_rsa|id_ed25519)'"$E" \
   && ! printf '%s' "$cmd" | grep -qE '[.]pub'"$E"; then
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
docker_exec="$B"'docker([[:space:]]+[^|;&]*)?[[:space:]](container[[:space:]]+)?exec[[:space:]]+([^|;&]*[[:space:]])?'
compose_exec="$B"'(docker([[:space:]]+[^|;&]*)?[[:space:]]compose|docker-compose)[[:space:]]+([^|;&]*[[:space:]])?exec[[:space:]]+([^|;&]*[[:space:]])?'
if g "$docker_exec$prod_ctr$runner_after" || g "$compose_exec$prod_svc$runner_after"; then
  block "running a test suite inside a production container with docker exec. It runs under no --cpus/--memory cap (the 2026-10-23 outage, TheHub #61001). Run it in a capped test container through the shared lock instead: bash scripts/docker-test-lock.sh run <owner> -- bash scripts/test-offline.sh ... (--cpus 2 --memory 2g)." "AIC-3, SC-6, CP-2"
fi
}

cmd="$raw_cmd"; guard
if [ "$word_cmd" != "$raw_cmd" ]; then cmd="$word_cmd"; guard; fi
if [ "$ps_cmd" != "$raw_cmd" ] && [ "$ps_cmd" != "$word_cmd" ]; then cmd="$ps_cmd"; guard; fi

exit 0
