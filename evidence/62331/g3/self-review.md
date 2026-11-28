# Self-review — TheHub #62331, #62350 (guard-bash.sh: the release-tag readers read a #, an ANSI-C quote and "$( )" as the shell does)

Mode: solo (POAM-008); agent self-review per the operator's 2026-11-04 decision, pending the independent review the PO starts
PR: #225 (pair of binnacle #123)   Author: workflow builder lane (Claude Opus 5.5, AI-authored)   Date: 2026-11-28
verdict: pass

Both stories were found by the Fable 5.2 review of keel#219 / binnacle#114 and its follow-ups in
keel#224 / binnacle#119. They change the same tokenizer lines, so they land together in this PR.
The exact inputs are in the binnacle pair's corpus (KB-419 to KB-450); keel is public, so this
record describes them by class.

- **Opened / reviewed:** 2026-11-28T01:59:05Z → 2026-11-28T02:10Z (cold read of the diff before this record; not merged in this session)

## The change (`.claude/hooks/guard-bash.sh`)

1. **The bash reader is built on the shared heredoc reader (HD_AWK).** A heredoc delimiter is read
   as bash reads it, and one it cannot read opens no heredoc (it is reported, below). Before, it
   waited for a line bash never ends the body with and read every later line as heredoc text.
2. **#62331, the comment rule.** A `#` is skipped as a comment only where the reader can prove bash
   reads one. After a `)` or a closing backtick, and inside arithmetic, an extglob pattern or a
   `${...}` that holds a substitution, the rest of the line is read as words, with quotes as plain
   characters. A `<<` in arithmetic opens no heredoc.
3. **#62350, quoting.** `$'...'` is an ANSI-C quote: a backslash escapes the next character and the
   escapes are decoded. The body of `"$( )"` and of a backtick inside double quotes is read as
   commands, with its own quotes and comments. The PowerShell reader reads `"$( )"` the same way and
   ends a `<# ... #>` block comment at its `#>`.
4. **Where the reading can still be wrong**, the tokenizer prints a `\004` line: such a `#` holding
   a quote, a backslash, a `$`, a backtick or a `<<`; a delimiter it cannot read; a quote or a
   substitution left open; a PowerShell here-string holding `$(`. `tag_amb` then judges the text
   the blunt way: a release-shaped word (or a tag-sending option or config key) and a word that can
   write a tag, anywhere, is refused.
5. **A pre-existing bug, found on the way:** the character class in `tag_gate`'s word split ended
   the `${t//[...]/ }` expansion at its `}`, so the split never happened. It is held in `tag_sep`.

Not changed, on purpose: a `#` that bash does read as a comment is still text, so a comment that
names a tag push stays allowed (the #192 rescoping, and the existing allow rows). This is the
challenge to #62331's AC-2 recorded in the PR body.

## Verified independently

- **Red first:** the new rows were committed before the fix. keel's 16 class block rows: 15 fail on
  main; the `$'...'` escape row passes on main (a guard: the command word it decodes to is not
  literal there). The 5 allow rows pass on main and at this head. In the pair's full list, 30 of 32
  block rows fail on main.
- **Bash ground truth:** every block row was run in Git Bash 5.2.37 with the tag command replaced by
  an echo; bash runs that command in each.
- **Git Bash (Windows), the fix commit:** selftest 837 passed, 0 failed (exit 0); hook-tag-timing
  and hook-heredoc-timing pass; hook-cut-short and hook-path-pinned pass.
- **GitHub Actions `unit-suites` (ubuntu-26.04) at the fix commit d48cf7e:** selftest 837 passed,
  0 failed; corpus 324 entries, 1186 hook runs, 0 failed, 44 open (the same 44 as main); every
  suite passed.
- **Everyday commands:** 84 commands an agent runs, through the hook on main and at this head: the
  same verdicts (83 allowed; 1 refused on both by an existing regex rule).
- **Hooks identical:** `diff` of keel's and binnacle's `guard-bash.sh` at the two heads shows only
  the known comment at lines 1050-1053.
- **Merge order:** `git merge-tree` of this branch and the #62332 branch (keel #226): no conflict.
- **Both PRs merged (this branch + #226), python:3.13 (the pr-checks image, mawk 1.3.4), `--cpus 2
  --memory 2g`:** every `test/*.test.py` exit 0; selftest 862 passed, 0 failed (816 on main + 21 + 25);
  corpus 324 entries, 1186 hook runs, 0 failed, 36 open; agent evals exit 0.
- **Cost, same container, alternating runs:** corpus 115 s and 133 s on main, 123 s and 115 s here;
  selftest 99 s on main, 82 s here; hook-tag-timing's 300-line case 0.34 s on main, 0.35 s here.
- **shellcheck v0.10.0 (the CI image), the repo's `ci/scripts/shellcheck.sh`:** `-S warning` exit 0.
  At style level `guard-bash.sh` has one SC2016 more than main (a `$` in the single-quoted awk program).
- **Concourse `pr-checks`:** builds 1453 (d48cf7e) and 1455 (af041fd) hit the task's 20-minute
  timeout with every finished suite green. Both ran on worker linux-3, where the corpus took 955 s
  and 968 s; #226's build 1456 on linux-3 timed out the same way (1004 s), while its build 1454 on
  linux-2, same hook, took 257 s. Quiet builds on linux-1/2 take 96-112 s. TheHub #62268 (linux-3
  overruns keel pr-checks) is the cause; this commit asks for a new judgment.

## Agent findings

- developer · security-engineer · qa-engineer: not run by the builder. The PO starts the
  independent review.

## Not verified

- bash 3.2 (macOS) was not run.
- hook-deadline, hook-fail-closed and hook-write-fail-closed could not run on this host
  (`os.symlink` needs a privilege the Windows account lacks); they ran in CI only.
- The `\004` blunt judgment can refuse an ordinary command that holds an unreadable form and also
  names a release-shaped word next to `push`/`tag`; no such command is in the selftest or the
  corpus, but a real one could exist. Unverified.
- The reviewers' own probe scripts were not posted; the inputs are rebuilt from their comments.

## Cold-read notes

- `tok_awk` is now `"$HD_AWK"'...'`: one more awk program text is concatenated per call, no extra
  process. The timing tests are the check (see above).
- `ansi()` maps a non-ASCII escape to `?`, so a decoded word with one is never a literal git.

## Rework after the independent review (2026-11-28)

- Finding 1 (a quoted substitution ended the outer command): `tok_awk` and `ps_tok_awk` now hold
  a body's output (`buf`) and print it after the command it stands in has ended (`dfr`); the
  outer word goes on after the body as one that is not literal. The unquoted `$( )` and backtick
  are read the same way (finding 3g, open on main, closed by the same change).
- Finding 2 (an escaped `case`): a word with a quote or a backslash in it (`lq`) is never the
  reserved word.
- Fell out of the same change (finding 3a): a `}` in a body nested in `${ }` no longer ends the
  `${ }`; a `#` inside `[ ]` (a subscript, a `[[ =~ ]]` group) is not proved a comment; a case
  pattern `)` inside a body no longer pops the level outside it.
- Every input of the review's blocking table is a selftest row (and, in the private mirror, a
  corpus entry), red at the reviewed head and green at this one.
- Still open (not in this rework): findings 3b, 3c, 3d, 3e, 3f and 4 (follow-ups TheHub #62450,
  #62451).

## Second rework after the independent re-review (2026-11-28)

PO ruling: change the strategy, not the patch count. Wherever the reader cannot prove its reading it
now fails closed. Commits: the rows first (red at the reviewed head), then the fix; no force-push.

- Findings 1 and 2 (a reserved word the reader did or did not count): a `$( )` or backtick body
  holding a word spelled `case` or `esac`, in any place and however quoted, is a reading that can
  be wrong (`\004`), so `tag_amb` judges the text the blunt way. The word-position counting stays
  for the reading, but no longer decides on its own.
- Finding 3 (a comment in a `$( )` inside a backtick): `inbt()` is true when any open level is a
  backtick, so the comment ends at the next backtick, as bash ends it. A backtick read inside a
  `$( )` inside a backtick is also reported as a reading that can be wrong.
- PowerShell: a backtick escape inside a `"$( )"` body is reported the same way. The re-review
  called the one such input harmless, but main refused it and the reviewed head allowed it.
- Rows: every input of the re-review's three tables (and the PowerShell one) is a block row, two
  allow rows keep ordinary `case` use; each block row is allowed at the reviewed head.
- New false positives: a body holding `case`/`esac` (or a backtick inside a `$( )` inside a
  backtick, or a PowerShell `"$( )"` holding a backtick escape) in a command that also names a
  release-shaped word and one of push, tag, send-pack, update-ref, fetch, config or api is refused,
  for example `echo "$(case $v in v*) echo v1.2.3;; esac)"; git push origin feat`.
- Out of scope, open on main: finding 4 (a heredoc opened inside a substitution that ends on the
  same line), TheHub #62450.

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
  check() in every shard, the hook's stderr read on every block):** this head 845 check rows,
  0 failed; the two PRs merged into main 896 check rows, 0 failed. Every shard exit 0, no
  deadline hit, every block names a rule.
- **Corpus, the mirror's merged tree, every class, both parser modes, 4 workers:** 554
  entries, 1874 hook runs, 0 failed, 36 open (the known gaps), exit 0, 1114 s.
- **Not run:** Linux, the python:3.13 container (no Docker for this rework), shellcheck
  (not installed on this host). CI runs them.

