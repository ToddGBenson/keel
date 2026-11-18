# Self-review — TheHub #62031 (main through a refspec, a + force push, commit -n)

Mode: solo (POAM-008); agent self-review, pending the independent review before merge
PR: #199   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-18
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
- Corpus: KB-260..262 (`feat:main`, `+feat`, `commit -anm`). #196 holds KB-229..231 and #192
  holds KB-240..252.

## Verified independently

- **Red first:** the 15 new selftest cases against main bd2ef2f. All 11 must-block cases were
  ALLOWED: feat:main, HEAD:refs/heads/main, refs/heads/feat:refs/heads/main, feat:master,
  refs/heads/main, :main, +feat, +feat:feat, commit -n, commit -anm, and PowerShell feat:main.
  The 4 must-allow cases passed: feat:feat, feat:main-fix, HEAD:feat/main-x, and
  `commit -m "notes"`.
- **Corpus on main:** 12 of 816 runs failed (the 3 new entries, on both tools and in both modes).
- **Green after:** selftest 345 passed / 0 failed. Corpus 227 entries, 816 runs, 0 failed, 32 open.
  shellcheck v0.10.0 `-S warning` clean. Pinned gitleaks v8.18.4: no leaks.

## Not verified

- Git Bash on Windows was not run.
- hook-fail-closed.test.py's 5 s timing budget fails on this laptop for every head, main included,
  because the CPU is clamped at 400 MHz. Its result here says nothing about this change. CI's run
  is the one to trust once the clamp is fixed.
- **Not read:** a refspec held in a variable (`git push origin "$R"`); `push.default`/`remote.*.push`
  config that maps a plain push onto main; and `git push origin HEAD` while main is checked out.
  That last one is a push of the current branch, which is main only if the agent works on main.
  The 61972 tokenizer (held) is the general fix for refspecs it cannot read.

## Residual risk accepted

The three "not read" cases, until server-side rulesets land (TheHub #61006).
