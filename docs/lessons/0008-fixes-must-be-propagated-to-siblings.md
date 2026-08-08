# L0008: A fix in one control is not a fix in its siblings

**Date:** 2026-08-07 · **Source:** platform build · **Class:** promotable
**Applies to:** any codebase with parallel implementations of the same check
**Landed as:** the credential-file pattern in `guard-bash.sh` · two regression tests in
`selftest.sh`
**Recurrence of:** [L0002](0002-match-value-shape-not-keywords.md)

## What happened

L0002 identified keyword-shaped matching as a defect and fixed it in `guard-write.sh`. The
same defect existed in `guard-bash.sh`, whose rule was:

```
*"cat "*"credentials"*
```

That matched any command mentioning the word anywhere — including heredoc content. It blocked
the command writing the lesson file that documents this exact failure mode, hours after the
"same" bug was declared fixed.

## Why it happened

The two guards were written together, share a threat model, and duplicate several patterns.
Fixing one felt like fixing the class. Nothing in the process asked *where else does this
pattern live?*

## The rule

When you fix a defect in a control, **grep for the pattern across every sibling
implementation before closing the finding.** The POA&M entry is not closeable until you have
either fixed or explicitly cleared each sibling.

Then add a regression test **per sibling**, not one for the class. A single test proves one
implementation; the second implementation is exactly where the bug survives.

## How you would know you hit this

You have two or more files that implement "the same check" for different surfaces — a
pre-commit hook and a CI job, a client validator and a server validator, a bash guard and a
write guard. Every one of those pairs is a place for this.

## Second recurrence — same file, next glob (2026-08-08)

Having fixed the credential glob in `guard-bash.sh`, I did not check the **other** globs in
the same file. The hook-bypass rule was:

```
*--no-verify*|*" -n "*"commit"*|*"commit -n"*
```

The middle pattern matched any command containing ` -n ` anywhere followed by `commit`
anywhere. So this was refused as a hook bypass:

```bash
bash -n scripts/sync-platform.sh && git commit -m "..."
```

A shell **syntax check**. Blocked as a security violation, one day after the "same" bug was
declared fixed — in the same file I had just edited.

The lesson is sharper than first written: it is not enough to grep other *files*. Grep the
**other patterns in the file you are already editing.** Proximity is not coverage; I had the
file open and still missed it.

Both are now anchored to a git invocation, with four regression tests: two that must allow
(`bash -n`, `sort -n` before a commit) and two that must block (real `--no-verify` on commit
and push).

## Third recurrence — and the fix that should have come first (2026-08-08)

A read-only command was blocked as a direct push to main:

```bash
echo "force-push pending" && git ls-remote origin main
```

The glob was `*"push"*"origin"*"main"*`. The three substrings appeared in that order across
an echo string and a *separate, read-only* command. Nothing was being pushed.

Three false positives in two days, each fixed individually, each time believing the class
was closed. **The point fix was the wrong move from the start.**

The right move — taken on the third occurrence — was a systematic pass: every rule in the
file converted from substring globs to a shared anchored matcher that requires an actual
`git`/`gh` invocation. Plus nine must-allow regression tests covering read-only operations
that resemble destructive ones.

**The generalisation:** when the same defect class recurs a second time in one file, stop
point-fixing. The recurrence is evidence that the *pattern* is wrong, not that you missed a
spot. Rewrite the mechanism.

## The compounding version

This is the argument for skills. Three of the four guard defects came from method duplicated
across files. A method that lives in one place cannot drift out of sync with itself — which
is why `.claude/skills/` exists and why agents point at skills rather than restating them.

The guards are shell scripts and cannot load a skill, so they carry the duplication and need
this discipline instead. Note that honestly rather than pretending the structure prevents it.
