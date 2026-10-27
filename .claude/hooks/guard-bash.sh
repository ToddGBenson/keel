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

# Decode a JSON string body (the sed fallback below hands over the raw escapes).
# \uXXXX is left as it is.
read -r -d '' json_unescape_awk <<'AWK'
{ s = (NR > 1) ? s "\n" $0 : $0 }
END {
  n = length(s); out = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\\" && i < n) {
      d = substr(s, ++i, 1)
      if (d == "n") c = "\n"; else if (d == "t") c = "\t"; else if (d == "r") c = "\r"
      else if (d == "u") c = "\\u"; else if (d == "b" || d == "f") c = " "; else c = d
    }
    out = out c
  }
  printf "%s", out
}
AWK

# Extract the command. Prefer jq; fall back to a tolerant sed for environments without it.
if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')"
else
  # TheHub #61038 review: take the JSON string itself (not everything up to the
  # payload's last quote, which swallowed the "description" field) and decode it, so
  # this mode sees the command jq would. Undecoded, \" is not a quote and \n is not a
  # newline, and the quote-aware view below could not tell what is quoted.
  cmd="$(printf '%s' "$payload" | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p')"
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
for pair in 'gh:[Gg][Hh]' 'git:[Gg][Ii][Tt]' 'curl:[Cc][Uu][Rr][Ll]'; do
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
{ s = (NR > 1) ? s "\n" $0 : $0 }
END {
  n = length(s); q = ""; out = ""; nh = 0; ws = 1; dp = 0; i = 1
  while (i <= n) {
    c = substr(s, i, 1)
    if (q == "" || q == "\"") {
      if (c == "$" && substr(s, i + 1, 1) == "(") {
        sv[++dp] = q; ft[dp] = "("; pc[dp] = 1; q = ""
        out = out "$("; i += 2; ws = 1; continue
      }
      if (c == "`") {
        if (q == "" && dp > 0 && ft[dp] == "`") q = sv[dp--]
        else { sv[++dp] = q; ft[dp] = "`"; q = "" }
        out = out c; i++; ws = 1; continue
      }
    }
    if (q == "") {
      if (c == "\\") {
        d = substr(s, i + 1, 1)
        out = out ((d == "\n" || d == "|" || d == ";" || d == "&") ? "  " : c d)
        i += 2; ws = 0; continue
      }
      if (c == "#" && ws) {
        j = index(substr(s, i), "\n"); if (j == 0) j = n - i + 2
        t = substr(s, i, j - 1); gsub(/[|;&]/, " ", t)
        out = out t; i += j - 1; continue
      }
      if (dp > 0 && ft[dp] == "(" && c == "(") pc[dp]++
      if (dp > 0 && ft[dp] == "(" && c == ")" && --pc[dp] == 0) {
        q = sv[dp--]; out = out c; i++; ws = 0; continue
      }
      if (c == "'") q = (i > 1 && substr(s, i - 1, 1) == "$") ? "$" : "'"
      else if (c == "\"") q = "\""
      else if (c == "<" && substr(s, i, 3) ~ /^<<[^<]/) {
        r = substr(s, i + 2); hdash = (substr(r, 1, 1) == "-")
        if (hdash) r = substr(r, 2)
        sub(/^[ \t]*/, "", r)
        if (match(r, /^["'\\]?[A-Za-z0-9_.-]+["']?/)) {
          w = substr(r, 1, RLENGTH); gsub(/["'\\]/, "", w)
          hw[++nh] = w; hd[nh] = hdash
        }
      }
      else if (c == "\n" && nh > 0) {
        out = out c; i++
        for (k = 1; k <= nh && i <= n; k++) {
          while (i <= n) {
            j = index(substr(s, i), "\n")
            line = (j > 0) ? substr(s, i, j - 1) : substr(s, i)
            out = out line; i += length(line)
            if (j > 0) { out = out "\n"; i++ }
            t = line; if (hd[k]) sub(/^\t+/, "", t)
            if (t == hw[k]) break
          }
        }
        nh = 0; ws = 1; continue
      }
      ws = (c == " " || c == "\t" || c == "\n" || c == ";" || c == "&" || c == "|" || c == "(")
      out = out c; i++; continue
    }
    if (c == "\\" && q != "'") {
      d = substr(s, i + 1, 1)
      out = out c ((d == "\n" || d == "|" || d == ";" || d == "&") ? " " : d)
      i += 2; continue
    }
    if ((q == "\"" && c == "\"") || (q != "\"" && c == "'")) q = ""
    else if (c == "|" || c == ";" || c == "&" || c == "\n") c = " "
    out = out c; i++
  }
  printf "%s", out
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
{ s = (NR > 1) ? s "\n" $0 : $0 }
END {
  n = length(s); q = ""; out = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q == "'") { if (c == "'") q = ""; else out = out c; continue }
    if (c == "\\" && i < n) { out = out substr(s, ++i, 1); continue }
    if (q == "$") { if (c == "'") q = ""; else out = out c; continue }
    if (q == "" && c == "$" && substr(s, i + 1, 1) == "'") { q = "$"; i++; continue }
    if (q == "" && c == "'") { q = "'"; continue }
    if (c == "\"") { q = (q == "\"") ? "" : "\""; continue }
    out = out c
  }
  printf "%s", out
}
AWK
word_cmd="$(printf '%s' "$masked_cmd" | LC_ALL=C awk "$dequote_awk" 2>/dev/null | normalize)" || word_cmd="$masked_cmd"
raw_cmd="$cmd"

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
  if printf '%s' "$gql" | grep -qE '(^|[^A-Za-z0-9_])mutation([^A-Za-z0-9_]|$)'; then
    m() { printf '%s' "$gql" | grep -qE '(^|[^A-Za-z0-9_])('"$1"')([^A-Za-z0-9_]|$)'; }
    m 'mergePullRequest|enablePullRequestAutoMerge|mergeBranch' \
      && block "merging through a GraphQL mutation. Merge happens after independent review, via GitHub." "AC-5, CM-5, AIC-2"
    m 'addPullRequestReview|submitPullRequestReview|dismissPullRequestReview' \
      && block "reviewing a PR through a GraphQL mutation. Agents recommend; a human or a separate identity approves. Use gh pr comment to say something." "AC-5, AIC-2"
    m '(create|update|delete)Release' \
      && block "creating or changing a release through GraphQL. G5 requires human authorization via the Environment." "CM-3, AIC-1"
    m '(create|update|delete)(BranchProtectionRule|RepositoryRuleset)' \
      && block "changing branch protection or a ruleset through GraphQL. This enforces separation of duties." "AC-5, CM-5"
    m '(create|update|delete)Environment' \
      && block "changing a deployment environment through GraphQL. Its reviewers ARE the G5 authorization gate." "CM-3, AC-5, AIC-1"
    m '(approve|reject)Deployments' \
      && block "approving or rejecting an environment deployment through GraphQL. Only a human reviews a deployment; the environment's reviewers ARE the G5 authorization gate." "CM-3, AC-5, AIC-1, AIC-2"
    # #127: moving a ref is a push. A ref id is opaque -- it may be main -- so any
    # GraphQL ref move is refused; a commit is refused when main appears anywhere in
    # the call (inline, or as a variable: -f b=main) or its branch is named only by
    # id. Quotes may still be JSON-escaped here, so main is matched as a word, not
    # as "main". Push a feature branch with git instead.
    m 'updateRefs?' \
      && block "moving a ref through GraphQL. A ref id may be main; push a feature branch with git." "AC-5, CM-5"
    if m 'createCommitOnBranch'; then
      { printf '%s' "$gql" | grep -qE '(^|[^A-Za-z0-9_/.-])(refs/heads/)?(main|master)([^A-Za-z0-9_/.-]|$)' \
        || ! printf '%s' "$gql" | grep -qE '(^|[^A-Za-z0-9_])branchName([^A-Za-z0-9_]|$)'; } \
        && block "a commit to main through GraphQL (or to a branch named only by id). All change goes through a reviewed PR." "AC-5, CM-5"
    fi
  fi
fi

# TheHub #61038: curl reaches the same endpoints as gh api, with the token from
# `gh auth token`, and no rule above reads curl. Judged per invocation (backslash-
# continued lines are rejoined at the top) and on the endpoint path, not the host, so
# a full api.github.com URL and an Enterprise one are the same request. As with gh
# api, a body makes it a write unless a GET was asked for (-G/--get, or -X GET); a GET
# of pending_deployments lists what is waiting and stays allowed. A config file
# (-K/--config) can carry the method and the body, so to these endpoints it counts
# as a body.
if g "$B"'curl([[:space:]]|$)'; then
  curl_segs=$(printf '%s' "$cmd" | tr '|;&' '\n' | grep -E "$B"'curl[[:space:]]')
  # TheHub #61038 review: a GraphQL document sent from a file (-d @file, --data-binary
  # @file, --json @file, -T file, -K config) is read, or refused when it cannot be --
  # stdin, a missing file -- exactly as the gh api graphql rule does.
  curl_text="$curl_segs"
  curl_gql=$(printf '%s\n' "$curl_segs" | grep -E '/graphql([^A-Za-z0-9_-]|$)')
  if [ -n "$curl_gql" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ "$f" = "-" ] || [ ! -r "$f" ]; then
        block "a GraphQL document sent with curl that this hook cannot read ($f). Pass it inline with -d '{\"query\":\"...\"}'." "CM-3, AC-5, AIC-1, AIC-2"
      fi
      curl_text="$curl_text
$(cat -- "$f")"
    done < <(printf '%s\n' "$curl_gql" \
      | grep -oE '(^|[[:space:]])((-[a-zA-Z]*d[[:space:]]*|--(data|data-ascii|data-binary|json)[[:space:]]+)["'"'"']?@|(-[a-zA-Z]*[TK][[:space:]]*|--(upload-file|config)[[:space:]]+)["'"'"']?)[^[:space:]"'"'"'`)]+' \
      | sed -E 's/^[[:space:]]*(-[a-zA-Z]*[dTK][[:space:]]*|--[a-z-]+[[:space:]]+)["'"'"']?@?//'
      printf '%s\n' "$curl_gql" | cat_files)
  fi
  printf '%s' "$curl_text" | grep -qE '(^|[^A-Za-z0-9_])(approve|reject)Deployments([^A-Za-z0-9_]|$)' \
    && block "approving or rejecting an environment deployment through GraphQL over curl. Only a human reviews a deployment; the environment's reviewers ARE the G5 authorization gate." "CM-3, AC-5, AIC-1, AIC-2"
  # Second review: curl rewrites the URL before sending it. It removes dot segments
  # (runs/1/x/../pending_deployments is runs/1/pending_deployments) and expands {} and
  # [] globs (pending_deployment{s}). So dot segments are removed first, and a glob
  # anywhere after a run id counts as these endpoints. (-g and --path-as-is turn the
  # rewriting off; matching as if they were absent can only add a block.)
  curl_dr=$(printf '%s\n' "$curl_segs" | sed -E ':a
s#/\./#/#g
s#/[^/[:space:]]+/\.\./#/#
ta' | grep -E "$DEPLOY_REVIEW"'|/actions/runs/[^|;&/[:space:]]+/[^[:space:]]*[][{}]')
  if [ -n "$curl_dr" ]; then
    # Second review: curl, like gh, sends the LAST -X it is given (curl -XGET -XPOST
    # is a POST). So a call is a write if ANY -X/--request on it is not GET or HEAD,
    # or if it carries a body and gives no -X and no -G.
    curl_m='(-[a-zA-Z]*X[[:space:]]*|--request[[:space:]=]+)[\"'"'"']*'
    while IFS= read -r seg; do
      ms=$(printf '%s' "$seg" | grep -oE "$curl_m"'[A-Za-z]+' | sed -E "s/^$curl_m//")
      if [ -n "$ms" ]; then
        printf '%s\n' "$ms" | grep -qvxE '[Gg][Ee][Tt]|[Hh][Ee][Aa][Dd]' || continue
      else
        printf '%s' "$seg" | grep -qE '[[:space:]](-[a-zA-Z]*[dFTK]|--data|--json|--form|--upload-file|--config)' || continue
        printf '%s' "$seg" | grep -qE '[[:space:]](-[a-zA-Z]*G|--get)([[:space:]]|$)' && continue
      fi
      block "approving or rejecting an environment deployment through curl. Only a human reviews a deployment; the environment's reviewers ARE the G5 authorization gate." "CM-3, AC-5, AIC-1, AIC-2"
    done <<< "$curl_dr"
  fi
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
}

cmd="$raw_cmd"; guard
if [ "$word_cmd" != "$raw_cmd" ]; then cmd="$word_cmd"; guard; fi

exit 0
