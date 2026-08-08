# L0002: Detection matches value shape, not keywords

**Date:** 2026-08-07 · **Source:** platform build · **Class:** promotable
**Applies to:** secret scanning, PII detection, any content heuristic
**Landed as:** GP-2 in `docs/11-ai-agent-controls.md` · `guard-write.sh`, `guard-bash.sh`,
`scripts/install-hooks.sh`
**Recurred as:** [L0008](0008-fixes-must-be-propagated-to-siblings.md) — fixed in one guard,
not the other

## What happened

The secret guard matched bare credential parameter names. Those names appear legitimately in
secret-*detection* code — the hook itself, the pre-commit installer, the security workflow,
and the `scanner-triage` skill. The control blocked all security tooling work in the repo,
which is to say it blocked precisely the work it existed to support.

## Why it happened

Keyword matching is the obvious first implementation and it looks thorough. The
false-positive population — code *about* secrets rather than code *containing* secrets — is
invisible until someone writes some.

## The rule

Named credentials require an assignment **and** a plausible value:

```
(api_key|client_secret|password)["' ]*[=:][ "']*[A-Za-z0-9/+_-]{16,}
```

Opaque token formats are already value-shaped and can match alone.

For commands rather than content, anchor on the **argument**, not the vocabulary: a reader
command followed by a path with a credential extension — not any command mentioning the word.

## How you would know you hit this

Your scanner fires on documentation, on test fixtures, on its own configuration, or on a
`.gitignore`. The finding count is high and the true-positive rate is near zero.

## Consequence if ignored

Teams add blanket suppressions to get work done, and a suppressed scanner reports green while
detecting nothing.
