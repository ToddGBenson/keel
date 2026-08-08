# L0001: Controls must be repairable through the normal path

**Date:** 2026-08-07 · **Source:** platform build · **Class:** promotable
**Applies to:** any repo with content-scanning hooks, lint rules, or pre-commit checks
**Landed as:** GP-1 in `docs/11-ai-agent-controls.md` · comment in `.claude/hooks/guard-write.sh`

## What happened

The secret-detection hook matched credential keywords literally. Those keywords appeared in
the hook's own pattern list, so the hook blocked every edit to itself — including the fix for
the defect that prompted the edit. Three attempts, three blocks.

## Why it happened

The pattern was written against a threat model that did not include *someone edits this file*.
The control's own maintenance was outside its design scope.

## The rule

A control must be repairable through the normal path. If the only way to fix it is to bypass
it, the control has created a second, larger problem — because the bypass becomes habit, and
the habit outlives the defect.

Concretely: a detection pattern must not match its own source text. Character-class splits
match identically and cannot self-trigger.

## How you would know you hit this

You cannot edit a scanner, hook, or lint rule without it rejecting your own change. The tell
is that the block message quotes text you just wrote *as the pattern*.

## Test for it

Ask of any new control: **can I edit this, using the normal tools, to change what it detects?**
