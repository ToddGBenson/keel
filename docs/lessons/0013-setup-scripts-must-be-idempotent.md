# L0013: A setup script must be safe to run twice

**Date:** 2026-08-08 · **Source:** enabling commit signing · **Class:** promotable · **Severity:** High
**Applies to:** any script that configures controls via an API — branch protection, IAM, firewall rules
**Landed as:** `EXISTING_CHECKS` preservation + a required-checks assertion in
`scripts/configure-github.sh`
**Related:** [L0007](0007-checkers-that-cry-wolf-get-muted.md) · [L0010](0010-verify-capability-before-enabling-control.md)

## What happened

`configure-github.sh` configures branch protection with a full `PUT`. GitHub's protection API
is **replace-the-whole-object**, and the payload hardcoded `"required_status_checks": null`
because on a fresh repo no checks exist yet.

That was correct exactly once. On every subsequent run it **silently wiped the 10 registered
status checks** — the branch went from fully gated to *merges not gated on CI at all* — and
the script reported success throughout.

It was caught only because the dashboard reads branch protection from the **live API** and
rendered `required status checks: 0` with a red stripe. The script's own verification never
looked at the field it was destroying.

## Why it survived

Three failures lined up:

1. **Replace-semantics treated as merge-semantics.** `PUT` on a config object means "this is
   now the entire object," and any field you omit or null is *removed*, not left alone.
2. **The script verified what it set, not what it wrote.** Nine controls were asserted;
   the tenth — the one being destroyed — had no assertion.
3. **It only manifested on the second run.** A first-run test passes perfectly. The defect
   requires running the tool the way it is actually used: repeatedly.

## The rule

**Any script that configures controls must be idempotent, and must be tested by running it
twice.** Specifically:

- With replace-semantics APIs, **read the current state and merge it forward** before writing.
  Never send a literal `null` for a field you did not intend to clear.
- **Assert every field you write**, including the ones you write conditionally. A verification
  step that skips a field is an invitation for that field to rot.
- Test = run it, run it again, then diff the resulting state against the first run. Equal
  means idempotent; anything else is a defect.

## How you would know you hit this

Your setup script works, and a week later a control is quietly off. Or: the only way anyone
notices is an *external* view of the real state — which is the accidental hero here, and not a
plan you should rely on.

## The compounding detail

While fixing this I added the missing assertion using `jq` — which is **not installed** on
stock Git-for-Windows. It reported a false failure against 11 healthy checks: the third
recurrence of L0007 in this one script. The fix that verifies a control must itself be
verified, on the platform it actually runs on.
