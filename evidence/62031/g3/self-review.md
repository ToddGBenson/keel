# Self-review — TheHub #62031 (main through a refspec, a + force push, commit -n)

Mode: solo (POAM-008); agent self-review, pending the independent review before merge
PR: #199   Pair: binnacle #93   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-18
verdict: pass

guard-bash.sh's push-to-main rule knew one shape: `git push [origin] [HEAD:]main`. With
`enforce_admins` off and the agents pushing as the owner's admin account, `git push origin
feat:main` moves main with no review and no required check at all. The force-push rule knew
`--force`/`-f`, not a `+` refspec. The `-n` (no-verify) rule needed a space before the flag that
`commit[[:space:]]+` had already consumed, which is the bug #120 fixed for push. All three
predate the hook sprint.

## The change

- **A refspec whose destination is main or master is refused:** `src:main`,
  `src:refs/heads/main`, a `+`forced one, and `:main` (a delete). So is a bare `refs/heads/main`.
- **A `+` refspec is a force push**, whatever the flags say.
- **A git commit's `-n` is read inside a cluster of flags** that take no value (`-an`, `-anm`).
  `-mnotes` is a message, because `m` takes the rest of the word.
- **A push of the current branch while the checkout is on main** (the PO's addition) is refused:
  `git push`, `git push origin`, `git push -u origin HEAD`. The branch is read where the push runs:
  the payload's `cwd` (both parsers read it), or `git -C <dir>`. That uses
  `git symbolic-ref --short -q HEAD` through the fault-recording wrapper, so a git that cannot answer
  blocks, and a detached HEAD (exit 1) is not a branch. It runs only for those push shapes: one git
  process on those calls.
- Corpus: KB-260..262 (`feat:main`, `+feat`, `commit -anm`). #196 holds KB-229..231 and #192
  holds KB-240..252.

## Verified independently

- **Red first:** the 15 new selftest cases against main bd2ef2f. All 11 must-block cases were
  ALLOWED: feat:main, HEAD:refs/heads/main, refs/heads/feat:refs/heads/main, feat:master,
  refs/heads/main, :main, +feat, +feat:feat, commit -n, commit -anm, and PowerShell feat:main.
  The 4 must-allow cases passed: feat:feat, feat:main-fix, HEAD:feat/main-x, and
  `commit -m "notes"`.
- **Corpus on main:** 12 of 816 runs failed (the 3 new entries, on both tools and in both modes).
- **Red first, the addition:** 6 more cases built on throwaway repos, against the first #199 head
  738876d: 347 passed, 4 failed. `git push`, `git push origin` and `git push -u origin HEAD` on main,
  and `git -C <main repo> push origin HEAD`, were ALLOWED. The must-allow cases passed: HEAD on a
  feature branch, and `git push origin feat` from main.
- **Green after:** selftest 351 passed / 0 failed. Corpus 227 entries, 816 runs, 0 failed, 32 open.
  shellcheck v0.10.0 `-S warning` clean. Pinned gitleaks v8.18.4: no leaks.

## Review round 1 (Fable 5.2 on a3ce8d1 / 61cc44a, BLOCK)

- **B1:** the corpus jq shim refused the new `.cwd // empty` filter, so 16 of 816 runs failed
  without a real jq. The shim now answers it, and `git` is in HOOK_TOOLS.
- **B2:** a push argument now ends at a separator or a redirect (`; & | < >`), not only at a space
  or quote, so `feat:main;`, `feat:main&&`, `feat:main|cat` and `feat:main>out` are refused.
  `heads/main` is read like `refs/heads/main`.
- **Refused too:** `--all`, `--mirror` and `--branches` by unique prefix; a bare `:` refspec;
  `-c push.*` and `-c remote.*.push` on a push; `git send-pack`; `-c core.hooksPath=` on commit or
  push; and `git commit -n;` (the `-n` rules had the same terminator gap).
- **No false blocks from messages:** only git's own global options may stand between `git` and
  `push`, so a commit or stash message containing "push feat:main" or "+1" is not a push. That
  also fixes the older force-push and push-to-main rules.
- **The current-branch rule, narrowed (best effort; enforce_admins server-side is the real
  control):**
  - It reads shell words with quotes honoured, and fires only on a literal `git push`
    subcommand.
  - git's `-C`, `-c` and `--git-dir`/`--work-tree` are read. `@` and `head` count as HEAD.
  - A redirect and its target are skipped, a dry run is allowed, and a refspec from a variable
    or `$(...)` is judged as the current branch.
  - If the command changes directory, sets GIT_DIR/GIT_WORK_TREE, or checks out or switches a
    branch, the push is refused with "run the push as a command of its own".
  - Outside a repository (git exits 128) it allows.
- **Red at a3ce8d1:** selftest 353 passed, 22 failed. **Green:** 375 / 0. The review's 55 inputs plus
  5 more, run with real on-main and on-feature repos: 60 checks, 0 wrong. Corpus 816 runs, 0
  failed, in both modes, with the shim.

## Review round 2 (Fable 5.2 on acad2f5 / 5aff46a, BLOCK; the PO's last full round)

- **D1, regression:** a quoted global value with a space (`-c user.name='A B'`, `-C "my dir"`) or an
  option not on the list (`--attr-source`) took the command out of every push rule.
  - The force-push and push-to-main rules are back on main's prefix, which these do not break.
  - Every rule #62031 added (refspec to main, `+` refspec, --all/--mirror/--branches, `:`,
    `-c push.*`, send-pack, a wildcard refspec) moved into the quote-aware word judge. That judge
    parses git's global options, and refuses one it does not know before a push.
- **D4:** the branch is read with git directly. Only exit 128 (not a repository), from the plain
  payload cwd with no -C, allows. A detached HEAD (exit 1) allows. Anything else blocks: no git, a
  git that exits 2, a missing -C dir.
- **D2:**
  - `sh -c`, `bash -c` and `eval` bodies are judged as commands of their own.
  - A non-literal subcommand is refused. `pu""sh` and `pu\sh` read as push. The PowerShell view is
    judged too, so `` pu`sh `` reads as push.
  - The last of --dry-run/--no-dry-run wins.
  - A -C that is not literal (`$VAR`, `$(...)`, `~`) or that is repeated is refused for a
    current-branch push. `$(...)` stays inside one word.
- **D3:** PowerShell `$env:GIT_DIR` and `$env:GIT_WORK_TREE` move the push like `GIT_DIR=`. CD and
  Set-Location are matched in any case.
- **False blocks cleared:** `git` counts only as the command word (after assignments and env,
  command, builtin, exec, nice, nohup, time, sudo, doas), so `echo use git push` is not a push.
  send-pack and `-o ci.skip:main` are read as words, so a notes message naming send-pack, and an
  option's value, are not refspecs.
- **The review's inputs for rounds 1 and 2,** run against real on-main and on-feature repos laid
  out as in the review: 109 checks, 1 differs. `git commit -m "never push --force"` is blocked,
  by main's own force rule, which this round restored; main blocks it too.

**Documented gaps (the PO's list; same on main, the server-side control's job):** cd not as the
first word (via builtin, command, if, for, `env -C`, `{ ...; }`); PowerShell script blocks;
`git symbolic-ref` then `push HEAD`; `GIT_CONFIG_COUNT`/`GIT_CONFIG_PARAMETERS`/`--config-env`; git
aliases; xargs; a push run by a script. The two #199 tokenizers (this one and #198's) are to be
reconciled into one by whichever merges second.

## Review round 3 (Fable 5.2 on 2a0c2bc / afcc867, BLOCK on T1 only; scope stop)

**T1, a fail-open by #61939's definition.** The word judge started `tr` twice per command and
ran on any line containing "git", so a long heredoc passed the hook's 60 s limit, which allows the
command. Concourse / keel build 290 timed out in guard-selftest for the same reason. The fix:
- no process per word: the two lower-casings are `shopt -s nocasematch` around the two case
  statements that need them (bash 3.1+; macOS's 3.2 has it), not `tr`, and not `${x,,}`;
- the judge runs only when `git` can be a command word (a regex gate on the line);
- the awk tokenizer prints only the segments whose command word, read past assignments and the
  same wrappers as push_judge, is git, a shell, eval or a directory change, or that set GIT_DIR or
  GIT_WORK_TREE. A dropped segment is one push_judge would have returned from without reading,
  so no verdict changes.

Timing on this host (the CPU is clamped at 400 MHz), for an allowed `git commit -F - <<'EOF'`:

| heredoc | main | round 2 (2a0c2bc) | round 3 |
|---|---|---|---|
| 50 lines of prose naming git mid-line | 1.1 s | 8.7 s | 1.9 s |
| 300 lines of prose naming git mid-line | 1.4 s | 53.9 s | 3.5 s |
| 50 lines starting with `git` | 1.1 s | 5.1 s | 1.7 s |
| 300 lines starting with `git` | 1.2 s | 26.4 s | 3.5 s |

**Further documented gaps (Fable's round-3 classes; not fixed, by the scope stop; server-side
protection, the `keel-main` ruleset since 2026-11-18, carries them):** a push after `timeout`,
`nice` with an option, or `env -i`; after `then`, `do` or `!`; inside `$(...)`; PowerShell
`$r = git push`; `g\it push`; `feat:$'main'`; and `export GIT_DIR=`.

## Not verified

- Git Bash on Windows was not run.
- hook-fail-closed.test.py's 5 s timing budget fails on this laptop for every head, main included,
  because the CPU is clamped at 400 MHz. Its result here says nothing about this change. CI's run
  is the one to trust once the clamp is fixed.
- **Not read:** a git alias (`git -c alias.p=push p origin feat:main`), xargs, a push run by a script,
  `remote.*.push` or `push.default` set in config earlier, and `git branch -u origin/main` followed
  later by a plain push in a separate command.
  The 61972 tokenizer (held) is the general fix for refspecs it cannot read.

## Residual risk accepted

The three "not read" cases, until server-side rulesets land (TheHub #61006).
