# Self-review — TheHub #62037 (guard-write.sh: the nits from the round-3 review of #62022)

Mode: solo (POAM-008); agent self-review, pending the independent review before merge
PR: (this PR)   Pair: binnacle (same change)   Author: Claude Opus 5.5 on Laptop A (AI-authored)   Date: 2026-11-21
verdict: pass

The round-3 independent review of #197 (TheHub #62022) shipped with three nits. The exact inputs are
in the binnacle pair's review comments; this record describes them by class.

## The change (`.claude/hooks/guard-write.sh`)

1. **The trailing-dot flag belongs to the last segment KEPT.** It was the flag of the last segment
   READ, so a later segment that `..` then removed could clear it. A narrative file name with a
   trailing dot or space under evidence/, followed by a segment and `..`, was allowed, and on
   Windows a writer that passes the path through unnormalised creates a file with the dot in its
   name. This was not a report-extension bypass, and it was refused on main. The flag is now kept per
   segment and popped with it.
2. **The older "hand-editing generated evidence" refusal no longer echoes control characters.** Only
   the round-3 refusal was cleaned. Both now replace C0 controls and DEL with `?`.
3. **The cut reading (a segment cut at its first `:`) is popped by `..`.** It was never popped, so a
   `:` in a segment that `..` left behind (in the cwd, or under evidence/) made the path read as
   evidence and refused it. That was over-refusal, in the safe direction. `guard_cut` now moves in
   step with the kept segments, including the drive and an unpoppable leading `..`.

Not changed: a `:` anywhere in the joined path still refuses a path that resolves under evidence/,
including a `.md`, so a checkout whose path holds a `:` cannot write evidence narratives. That
`guard_colon` rule is the round-3 stream defence. It is a whole-path flag, not tied to the cut
reading, and it errs in the safe direction. Narrowing it is a separate story.

## Verified independently

- **Red first:** 8 new selftest cases. Against main 6c7af3b: 567 passed, 6 failed (two trailing-dot
  forms allowed, two `..`-resolved colon paths refused, two control-character messages raw). At this
  head: 573 passed, 0 failed.
- **No evidence-rule block lost.** I rebuilt the reviewers' probe sets from the cases listed in the
  round-1 to round-3 review comments: 192 path/cwd cases. Each of the 175 with no cwd also ran from a
  POSIX and a Windows repo root, 542 runs in all, against main and against this head. 529 gave the
  same verdict. 4 are newly allowed: all are item 3's paths, which resolve outside evidence/. 9 are
  newly blocked: item 1's spellings. The same counts in jq and no-jq mode.
- **Suites in one disposable container each** (python:3.12-slim, `--cpus 2 --memory 2g`, bash
  5.2.37, git installed), no-jq and jq modes:
  - selftest: 573 passed, 0 failed, in both modes;
  - bypass corpus: 284 entries, 1032 hook runs, 0 failed, in both modes;
  - hook-write-fail-closed: all passed.

## Not verified

- Windows / Git Bash was not run, and neither was bash 3.2 (macOS). The change uses indexed arrays
  and `unset` of an element, as the loop already did.
- The reviewers' own probe scripts were not posted, so the probe set is reconstructed from the
  listed cases, not the original files.
- Node on NTFS was not asked what the new item-1 refusals resolve to. They block, so a wrong answer
  would only be over-refusal.

## Cold-read notes

- A drive segment (`C:`) now enters the cut reading too. Before, a drive path's cut reading was
  relative (no leading drive). Both forms match the evidence patterns, so no verdict changes; the
  probe set covers drive paths.
