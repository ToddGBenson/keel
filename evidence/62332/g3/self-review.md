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

## Rework after the independent review (2026-11-28)

- Finding 1 (the push reader's comment rule dropped a line bash runs): a `#` is dropped only
  outside `${ }`, a backtick, any `( )` and any `[ ]`. Elsewhere the rest of the line is read as
  words with quotes as text, and `push_guard` reads the text a second time with that `#` as an
  ordinary character (main's reading). Both readings are judged. One shared reader with the tag
  reader (#62331) was not done: the two PRs are separate and must not stack.
- Nits: a `-c` alias that names no push is read as the subcommand it names;
  `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM` set to `/dev/null` or `NUL` is allowed. Any other config
  file stays refused: `remote.<name>.push` in it maps even `git push origin feat` onto main
  (checked with git: `feat -> main`).
- The review's three nocasematch rows are selftest rows.
- Still open (not in this rework): finding 2 (follow-ups TheHub #62450, #62451).

## Second rework after the independent re-review (2026-11-28)

PO ruling: change the strategy, not the patch count. Wherever the reader cannot prove its reading it
now fails closed. Commits: the rows first (red at the reviewed head), then the fix; no force-push.

- Finding 1 (a closer lowered the wrong counter): the four counters are one stack of open
  constructs (`${`, `[`, `(`, a backtick). A closer pops only the opener it matches, and one that
  matches none leaves no `#` of that body proved; a `#` is proved only with the stack empty.
  Found during this rework and closed the same way (`cf`): a `$( )` whose body holds more than
  plain words (its parentheses are counted as written; one such input was refused on main and
  allowed at the reviewed head); a `$( )`, `${ }` or backtick inside `"..."`; a bare `{` inside an
  open construct; and a heredoc, whose body this reader reads as words (a quote in it was allowed
  on main too). An unproved `#` costs a second reading (main's), never a dropped line.
- Finding 2 (the alias rule): an allow-list. A `-c` alias is read as its first word only when its
  value is a letter, then letters, digits, spaces and `-` only. Any other value, a value that
  starts with `-`, a first word that is any `-c` alias name (compared in any case), and a name
  given twice (git takes the last) are refused; a name with a dot is compared by its first part too.
- Finding 3 (`GIT_CONFIG_GLOBAL=nul`): removed. `GIT_CONFIG_GLOBAL` and `GIT_CONFIG_SYSTEM` are
  allowed for `/dev/null` only, as written (`[ = ]` ignores nocasematch). NUL was not kept for
  Windows: Git for Windows accepts `/dev/null` from Git Bash, and that a relative `nul` is the
  device in every directory on every Windows build is not something the hook can prove.
- Rows: one per class in keel, every input in the mirror; each block row is allowed at the reviewed
  head.
- New false positives: a `-c` alias whose value holds anything but letters, digits, spaces and `-`
  (`alias.lg='log --format=%h'`) or starts with `-`; a `-c` alias given twice or a chain of them;
  `GIT_CONFIG_GLOBAL=nul`/`NUL`; and more comments read twice, which refuses a command only when the
  comment's text after an unprovable `#` holds a push the judge refuses.
- Out of scope, open on main: finding 4 (one text both readings get wrong) and finding 5 (config
  this judge does not read: `GIT_CONFIG_*` or `--config-env` aliases, `-c include.path`, a moved
  `HOME` or `XDG_CONFIG_HOME`), TheHub #62450.

### How it was checked

- **The reviewer's full probe set** (the first review's p1 to p12, the earlier builder matrices,
  the re-review's pA1 to pA4, pB1 to pB4, p6 and the timing set) plus the inputs this rework added:
  438 distinct inputs, through the real hook (PreToolUse JSON on stdin, Git Bash 5.2.37, at most 4
  hook runs at a time) at main, both reviewed heads, both new heads and the two merged into main:
  2628 hook runs per repository. Inputs main refuses that a new head or the merged tree allows:
  **0** of the reviewer's set. Of the inputs this rework added, 1: a comment after a plain `$( )`
  that holds a push in its text (`echo $(git rev-parse HEAD) # then; git push origin feat:main`).
  Bash reads it as a comment and runs no push (checked with stubs in git's place); main refused it
  because main read every `#` as a word. It is a kept selftest row, and the reviewed head allowed it
  too. Inputs a reviewed head refuses that its new head allows: 0. keel and the mirror gave the same
  verdict in every one of the 2628 cells. No deadline hit; the slowest run took 8.2 s.
- **44 everyday agent commands** (pushes, heredoc commit messages and PR bodies, comments, `case`,
  `-c` aliases, PowerShell) at the same six trees: the same verdict everywhere except one false
  positive listed in the PR (`git -c alias.lg='log --format=%h' lg`).
- **Hooks identical:** `guard-bash.sh` differs from the pair's only in the known comment at lines
  1050-1053, at each new head and in the merged trees.

- **Full selftest, Git Bash, in 4 shards (each check row once, the 8 assertions outside
  check() in every shard, the hook's stderr read on every block):** this head 859 check rows,
  0 failed; the two PRs merged into main 896 check rows, 0 failed. Every shard exit 0, no
  deadline hit, every block names a rule.
- **Corpus, the mirror's merged tree, every class, both parser modes, 4 workers:** 554
  entries, 1874 hook runs, 0 failed, 36 open (the known gaps), exit 0, 1114 s.
- **Not run:** Linux, the python:3.13 container (no Docker for this rework), shellcheck
  (not installed on this host). CI runs them.

