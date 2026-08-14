# L0016: A check answers the question it asks, not the one it prints

**Date:** 2026-08-14 · **Source:** #58 · **Class:** promotable
**Applies to:** any repo with a validator, linter or gate that summarises its own result
**Landed as:** per-file coverage in `scripts/validate-manifest.py` · POAM-015

## What happened

A check written the previous day printed, on success:

```
[ok] every tracked path is governed, and every shipped entry exists
```

It iterated over **top-level paths**. The manifest it validates enumerates documentation
*file by file*, so `docs/` was "governed" the moment any single doc was listed. Six were
not, and the check said everything was fine each time it ran.

The six included `docs/13-solo-operation.md` — the document that defines solo operation and
the compensating control that a fork's self-review gate exists to enforce. A fork would have
inherited the gate and never received the document explaining what it is for.

Two things hid it:

- **The output was a summary, not a report.** "Every tracked path is governed" is a claim
  about files. The loop was over directories. Nobody compares those two sentences after the
  check goes green.
- **Reading the manifest did not reveal it either.** `docs/12` and `docs/18` were both
  listed, so the run of numbered documents looked complete. 13 through 17 were missing from
  the middle, which is the one place a human eye interpolates.

It was found by accident, while adding an unrelated file and wondering whether it would be
delivered.

## Why it matters

A check that passes for the wrong reason is worse than no check, because it *ends* the
inquiry. The absent check leaves a known hole; the weak one converts a hole into a
documented assurance. This is the same shape as the self-review gate that once passed on the
presence of a markdown heading, and the same shape as a coverage threshold met by tests that
assert nothing.

The failure is not laziness in the loop. It is that **the summary line was written from the
intent and the loop was written from the data**, and nothing ever forced the two to agree.

## The rule

**Make a check fail before you trust it passing, and fail it on the specific claim its output
makes.** Not "does this validator work" — delete the exact thing the summary says is present,
and confirm the run goes red naming it.

Concretely:

- Write the failure case first, as a test or as a hand-run: remove one governed file, break
  one pin, unlink one document.
- Read the success message as a **specification** and check the code against it. If the
  message says "every file", the loop is over files. If it cannot honestly say "every", make
  the message narrower rather than the loop wider.
- Prefer the check to enumerate what it examined (`228 tracked files, 79 entries`) over
  asserting a property. A count that looks wrong is noticed; a green tick is not.
- When a list is maintained by hand, sort it and let the gaps show. `12, 18` reads as
  complete; `12, 13, 14, 15, 16, 17, 18` with five missing does not.

## Related

- [[0005-test-beats-examine]] — the same instinct, applied to reviewing rather than checking
- [[0011-unexecuted-code-is-a-plan]] — a check that has never failed has never fully run
- [[0014-fixing-the-instance-is-not-fixing-the-class]] — this was found one day after fixing
  an instance of the very same class in the very same file
