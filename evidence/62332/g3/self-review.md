# Self-review — TheHub #62332 (guard-bash.sh: the push judge reads wrappers, reserved words, & redirects, a backslash and more launchers)

Mode: solo (POAM-008); agent self-review per the operator's 2026-11-04 decision, pending the independent review the PO starts
PR: #226 (pair of binnacle #124)   Author: workflow builder lane (Claude Opus 5.5, AI-authored)   Date: 2026-11-28
verdict: pass

Found by the Fable 5.2 review of keel#219 / binnacle#114 / keel#220 / keel#216. The exact inputs
are in the binnacle pair's corpus (KB-460 to KB-500); keel is public, so this record describes them
by class. Server side, `enforce_admins` and the `keel-main` ruleset have refused a push to main for
every identity since 2026-11-18, so this rule is defence in depth.

- **Opened / reviewed:** 2026-11-28T01:59:18Z → 2026-11-28T02:15Z (cold read of the diff before this record; not merged in this session)

## The change (`.claude/hooks/guard-bash.sh`)

- **The tokenizer (`push_tok_awk`)** reads a redirect written with `&` as one redirect whose target
  is the next word (`&` no longer ends the command), marks a here-string, deletes a
  backslash-newline as bash does, decodes `$'...'`, and skips a comment (a `#` that starts a word
  after a blank or an operator) so a quote in it opens nothing. Any other `#` is read as a word.
- **`push_judge`** reads past reserved words and a redirect before the command, and past the
  options, option values and leading words of the wrappers it names (`push_wrap`). It judges the
  bodies of more shells and launchers (`-c`, `-Command`, `/c`, `find -exec`, a here-string, a
  shell named by a variable), refuses a push with push/mirror/alias config given in `GIT_CONFIG_*`
  variables, a subcommand that is an alias given with `-c`, and `--force` by a prefix or `-f` in a
  short cluster.
- **The gate** also reads the text with a backslash-newline deleted and backslashes and quotes
  removed, and any `$'...'`. The rules before it read a backslash-newline as a space, so a command
  holding one is judged a second time from the original text.
- **The corpus:** the push judge also closes two release-tag gaps the corpus recorded as open
  (KB-250, push config in `GIT_CONFIG_*`; KB-251, a `-c` alias), so their `open_in` and `gap` are
  deleted and they are regression tests (the corpus header's rule). Actions found this; the commit
  is the fourth on the branch.

Out of scope, kept for later: a case pattern's `)` ending a `$( )` body early (TheHub #62356), and
three container-rule forms in the story's "also open" list (TheHub #62391).

## Verified independently

- **Red first:** the new rows were committed before the fix. keel's 17 class block rows all fail on
  main; the 8 allow rows pass on main and at this head. In the pair's full list, 41 of 45 block
  rows fail on main; the 4 that pass on main are kept as guards.
- **GitHub Actions `unit-suites` (ubuntu-26.04) at 0eda43b:** selftest 841 passed, 0 failed; corpus
  324 entries, 1186 hook runs, 0 failed, 36 open; hook-tag-timing and hook-heredoc-timing pass;
  every suite passed. (At the commit before, 2642e80, the corpus failed 8 runs: KB-250 and KB-251
  blocked while still recorded open, fixed by the corpus commit.)
- **Git Bash (Windows), the hook at 2642e80 (unchanged at 0eda43b):** selftest 841 passed, 0 failed
  (exit 0); hook-tag-timing and hook-heredoc-timing pass. The binnacle pair's corpus at its corpus
  commit: 447 entries, 1638 hook runs, 0 failed, 36 open; its Concourse `pr-checks` pass.
- **Everyday commands:** 84 commands an agent runs, through the hook on main and at this head: the
  same verdicts (83 allowed; 1 refused on both by an existing regex rule).
- **Hooks identical:** `diff` against binnacle #124's hook shows only the known comment at lines
  1050-1053.
- **Merge order:** `git merge-tree` of this branch and the #62331 branch (keel #225): no conflict.
- **Both PRs merged (this branch + #225), python:3.13 (the pr-checks image, mawk 1.3.4), `--cpus 2
  --memory 2g`:** every `test/*.test.py` exit 0; selftest 862 passed, 0 failed (816 on main + 21 + 25);
  corpus 324 entries, 1186 hook runs, 0 failed, 36 open; agent evals exit 0.
- **Cost, same container:** selftest 99 s on main, 120 s here (the push judge now reads every
  segment that starts with a wrapper); hook-tag-timing passes.
- **shellcheck v0.10.0 (the CI image), the repo's `ci/scripts/shellcheck.sh`:** `-S warning` exit 0.
  At style level `guard-bash.sh` has one SC2015 more than main: `[ -n "$v" ] && [[ ... ]] || continue`
  in `push_wrap`'s short-option loop, where `continue` is meant to run unless both tests hold (it
  skips a letter that takes no value).
- **Concourse `pr-checks`:** build 1454 at 0eda43b passed on worker linux-2 (corpus 257 s). Build
  1456 at 8de2406 (only the record added) timed out at the task's 20 minutes on worker linux-3, every
  finished suite green, corpus 1004 s. TheHub #62268 (linux-3 overruns keel pr-checks) is the cause;
  this commit asks for a new judgment.
- **Cold read:** a return from inside `push_judge`'s nocasematch section (the `env -S` and the xargs
  here-string paths) left the option set for the rest of the hook. Fixed in the third commit.

## Agent findings

- developer · security-engineer · qa-engineer: not run by the builder. The PO starts the
  independent review.

## Not verified

- bash 3.2 (macOS) was not run.
- A PowerShell `-EncodedCommand` is not decoded; git config set in a file, a push run by a script,
  and xargs reading its words from a file or pipe are still not read.
- No test covers the nocasematch fix directly, and what the leaked option did to the rules after
  the push judge was not measured.

## Cold-read notes

- A command word that is not written literally, followed by `push`, is now judged as git. A
  `"$DOCKER" push image` on a checkout of main would be refused. That is a false positive the
  agents can avoid by naming the program.
- `GIT_CONFIG_GLOBAL=...` (or `_SYSTEM`, or `GIT_CONFIG`) before any push is refused, like `-c push.*`.
