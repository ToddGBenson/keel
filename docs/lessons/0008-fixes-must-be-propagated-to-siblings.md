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

## The compounding version

This is the argument for skills. Three of the four guard defects came from method duplicated
across files. A method that lives in one place cannot drift out of sync with itself — which
is why `.claude/skills/` exists and why agents point at skills rather than restating them.

The guards are shell scripts and cannot load a skill, so they carry the duplication and need
this discipline instead. Note that honestly rather than pretending the structure prevents it.
