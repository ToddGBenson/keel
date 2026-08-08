# L0003: Scan only what is being added

**Date:** 2026-08-07 · **Source:** platform build · **Class:** promotable · **Severity:** High
**Applies to:** any pre-write, pre-commit, or diff-based content check
**Landed as:** GP-3 in `docs/11-ai-agent-controls.md` · payload extraction in `guard-write.sh`

## What happened

`jq` was absent, so the hook's fallback set the scan target to the entire tool payload —
which for an edit includes `old_string`, the text being **removed**.

The guard therefore scanned what was leaving the file. **An edit that took a secret out of a
file was blocked**, on the grounds that the file contained a secret.

Rated High: it makes remediation impossible during exactly the incident the control exists
for, while appearing to protect you.

## Why it happened

The fallback was written for robustness — *if we cannot parse it, scan everything* — without
noticing that "everything" has the wrong sign for a diff.

## The rule

Extract `new_string` / `content` explicitly. Never scan the raw payload. In a diff-based
check, scan added lines only:

```bash
git diff --cached -U0 | grep '^+'
```

## How you would know you hit this

Removing a flagged string does not clear the flag. The check fails identically before and
after the fix — which is the signature of measuring the wrong side of the change.

## Related

The same root appears in CI as *scan the whole repo* rather than *scan the diff*, which
produces the fail-on-total problem instead: a permanently red pipeline that everyone learns
to ignore. Both come from not asking which side of the change you are measuring.
