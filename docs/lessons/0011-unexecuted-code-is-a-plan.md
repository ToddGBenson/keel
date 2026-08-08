# L0011: Unexecuted code is not code — it is a plan

**Date:** 2026-08-08 · **Source:** first end-to-end run of `bootstrap.sh` and
`sync-platform.sh` · **Class:** promotable · **Severity:** High
**Applies to:** any generator, migration, installer, or sync tool
**Landed as:** nine fixes across both scripts · output validation in `bootstrap.sh` ·
placeholder reporting · `tr -d '\r'` on manifest parsing
**Related:** [L0005](0005-test-beats-examine.md) · [L0009](0009-scanners-need-a-no-input-path.md)

## What happened

Two scripts — the template's entire reason to exist — were written carefully, reviewed,
documented, syntax-checked with `bash -n`, and shipped. Every self-review flagged them as
**UNVERIFIED**, honestly, in writing.

The first time they were actually executed, **nine defects surfaced**, four of them total
blockers:

### `bootstrap.sh`

1. **`set -euo pipefail` + `grep` finding nothing → immediate death.** Once the base repo's
   own placeholders were substituted, nothing matched, so bootstrap failed **100% of the
   time**. The template could not be used at all.
2. **Forks inherited the upstream author as CODEOWNER.** It only rewrote the literal
   `@your-org`, and the base repo carries a real owner so its own CI works. Every fork got a
   stranger with review authority.
3. **`indent()` ended in `.strip()`**, removing the pad from the *first* line only. Every
   spliced block emitted line 1 at column 0 — **invalid YAML**, generated silently.
4. **The key regex was `[a-z_]+`, which excludes digits.** `e2e_test` never parsed as a key
   and was silently dropped from every stack profile, leaving its placeholder in the
   pipeline where the step would "pass" by echoing.
5. No validation of its own output — it printed a success banner over broken YAML.
6. A hardcoded assertion count that had already gone stale.

### `sync-platform.sh`

7. **An existence guard skipped every directory in the manifest**, so the script reported
   `already current` on a fork that was behind. *A sync tool that says you are up to date
   when you are not is worse than no sync tool.*
8. On Windows, MSYS path conversion mangled `<ref>:<path>` into `ref\main;.claude\agents\`.
9. **Python's text-mode stdout on Windows emits `\r\n`**, so every manifest path carried a
   trailing carriage return and matched nothing. Same silent-wrong-answer failure as 7,
   independently sufficient to cause it.

## Why none were caught

Every defensible practice was applied and none of them execute code:

- careful authoring and review — finds intent errors, not runtime errors
- `bash -n` — syntax only; all nine scripts were syntactically perfect
- honest self-review — *correctly* recorded them as unverified, which is why this was
  discovered rather than deployed
- the platform's own validators — check the repo, not the generators

## The rule

**A script that has never run is a hypothesis with good formatting.**

For any generator, migration, installer, or sync tool: run it against a real target before
declaring it done. Not a mock — a clone. The whole path.

Three practices that would have caught all nine:

1. **Execute once end to end**, on a throwaway clone, before shipping.
2. **Validate your own output.** `bootstrap.sh` now parses the YAML it generated and refuses
   to mark the repo bootstrapped if it is broken. A generator that does not check its output
   is a generator you cannot trust.
3. **Report what you did not do.** It now lists unreplaced command placeholders by name —
   the symptom of a silently dropped config key.

## How you would know you hit this

Your setup or migration script has a thorough README, careful error messages, and no
evidence of ever having been run against a real target. Ask: *what is the newest file it
has actually written, and did anyone look at it?*

## The cross-cutting one

Defects 8 and 9 are Windows-specific and would never appear on a CI runner. **Authoring
platform on Windows, execution platform on Linux.** If those differ, the scripts must be
exercised on both — or the failure waits for the first contributor on the other one.
