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
