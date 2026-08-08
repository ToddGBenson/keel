# Lessons

The cross-project memory. This is the difference between forking a template ten times and
running one platform that gets better.

## The problem this solves

`/retro` and `/learn` close the loop *inside* a project. A lesson learned in project A lands
as a diff in project A and stops there. Fork the template ten times and you learn the same
thing ten times, badly, in sequence.

A lesson recorded here travels: it ships with the platform, arrives in every fork on the next
`sync-platform.sh`, and is read by whoever hits the same wall next.

## The two kinds of lesson

`/learn` classifies every retro finding as one or the other. Getting this wrong in either
direction is costly, so the test is explicit:

**Project-local** — true because of *this* project's stack, domain, team, or customers.
Stays in the fork. Lands in that project's docs, checks, or agent definitions.

> "Our Postgres connection pool needs a 30s timeout because the reporting queries are slow."

**Promotable** — true for *any* project using this platform. Goes here, then upstream via
`/promote`.

> "A detection pattern that matches its own source blocks its own repair."

**The test:** *would a team on a completely different stack, in a different domain, hit this
same wall?* If yes, promote it. If you are unsure, write it as project-local — a lesson
wrongly promoted becomes noise in every fork, and noise is what makes people stop reading.

## Format

One file per lesson, `NNNN-kebab-slug.md`:

```markdown
# L0004: Detection patterns must not match their own source

**Date:** 2026-08-07 · **Source:** platform build · **Class:** promotable
**Applies to:** any repo with content-scanning hooks
**Landed as:** GP-1 in docs/11-ai-agent-controls.md · guard-write.sh comment

## What happened
The secret-detection hook matched the literal keywords in its own pattern list, so every
edit to the hook was blocked — including the fix for the defect that prompted the edit.

## Why it happened
The pattern was written for readability against a threat model that did not include
"someone edits this file."

## The rule
A control must be repairable through the normal path. Detection patterns get character-class
splits so they cannot self-match.

## How you would know you hit this
You cannot edit a scanner, hook, or lint rule without it rejecting your own change.
```

Keep them short. A lesson nobody finishes is a lesson nobody applies.

## Rules

**A lesson without a landed artifact is a note, not a lesson.** The `Landed as:` line is
mandatory — it names the doc, check, skill, or agent definition that now encodes the rule.
If nothing changed, nothing was learned.

**Record the "how you would know" line.** It is what makes a lesson findable by someone who
does not yet know they need it — which is everyone, until they do.

**Do not record what the repo already says.** A lesson restating an existing gate is
duplication that will drift. Lessons capture what was *surprising*.

**Prune.** A lesson whose rule is now enforced by an automated check has done its job; mark
it `superseded-by:` and stop carrying it. The ledger is a working set, not an archive.

## Index

| ID | Lesson | Class | Landed as |
|---|---|---|---|
| [L0001](0001-controls-must-be-repairable.md) | Controls must be repairable through the normal path | promotable | GP-1 |
| [L0002](0002-match-value-shape-not-keywords.md) | Detection matches value shape, not keywords | promotable | GP-2 |
| [L0003](0003-scan-only-what-is-added.md) | Scan only what is being added | promotable | GP-3 |
| [L0004](0004-detection-fails-open.md) | Detection fails open; enforcement fails closed | promotable | GP-4 |
| [L0005](0005-test-beats-examine.md) | Test the control; reading it finds nothing | promotable | GP-5, control-assessment |
| [L0006](0006-enforcement-strength-is-not-uniform.md) | State enforcement strength honestly per control | promotable | AIC-3 table, POAM-001 |
| [L0007](0007-checkers-that-cry-wolf-get-muted.md) | A checker with false positives gets muted | promotable | validate-platform.py |
| [L0008](0008-fixes-must-be-propagated-to-siblings.md) | A fix in one control is not a fix in its siblings | promotable | guard-bash.sh, selftest.sh |
