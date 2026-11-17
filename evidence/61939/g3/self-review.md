# Self-review — TheHub #61939 (guard-bash.sh decides a large command in linear time)

Mode: solo (POAM-008); agent self-review, pending the independent review before merge
PR: (set when opened)   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-17
verdict: pass

Claude Code gives a hook 60 s and lets the tool call proceed when it runs out, so a slow guard
FAILS OPEN. On the ~390 KB padded command in test/hook-fail-closed.test.py ("a large command: a
match is still a match (review #1)") main took 15-16 s without jq and 8-12 s with it on this box,
and 7-16 s depending on load across runs: inside 60 s here, but with little margin on a slower or
busier host.

## Measured (main 9d9b5fb, mawk 1.3.4, the KB-177 case, Bash tool, 3 runs each)

| mode  | main 9d9b5fb            | this branch          |
|-------|-------------------------|----------------------|
| jq    | 8.12 s, 9.61 s, 12.06 s | 0.58 s, 0.54 s, 0.53 s |
| no-jq | 14.88 s, 15.71 s, 15.90 s | 0.68 s, 0.67 s, 0.65 s |

A per-line trace (`bash -x` with `$EPOCHREALTIME`) of the no-jq run on main put the time in four
awk programs: ps_awk 5.3 s, dequote_awk 5.0 s, json_unescape_awk 3.2 s (no-jq only), mask_awk
0.8 s. Micro-benchmarks in mawk showed each cost growing 4x when the input doubles:

- `out = out c`, one character at a time: each append copies the whole output so far.
- `s = (NR > 1) ? s "\n" $0 : $0`, one line at a time: the same, per line.
- `index(substr(s, i), "\n")` at every comment and here-document line (mask_awk): copies the
  rest of the command each time. 100,000 one-character comment lines (195 KB) took 7.2 s on main.

## The change

- Every view prints as it goes (`printf "%s", x` in place of `out = out x`); `out` is gone.
- Input lines are kept in an array and joined pairwise (O(n log n)), not appended one by one.
- mask_awk finds the next newline through a forward cursor over the line ends (`guard_nextnl`),
  and reads a here-document word from the rest of its own line only, which is all the anchored
  match could ever see.

## Verified independently

- **Same semantics:** a differential fuzz ran main's and this branch's json_unescape, mask, dequote
  and PowerShell views on 3,012 inputs (edge cases plus random strings over quotes, escapes, `$(`,
  backticks, here-documents, `<<-`, comments, CRLF, `u{..}`, `--%`): 0 byte differences under mawk
  1.3.4, 0 of 1,512 under busybox awk, 0 of 1,512 under gawk 5.3.2. The exit status matched too.
- **Red first:** the new budget check (every large command decided in under 5 s, still blocked)
  against main's hook: 16 of 16 timing checks failed; every command was still blocked.
- **Green after:** test/hook-fail-closed.test.py 192 passed, 0 failed; slowest large case 0.7 s.
- **No regressions:** selftest 305 passed / 0 failed; bypass corpus 224 entries, 804 hook runs,
  0 failed (32 open known gaps, unchanged); every test in test/manifest.txt passes in a capped
  python:3.12-slim container (mykronos-preflight and atlas-evidence need curl in the image).
- shellcheck v0.10.0 at CI's `-S warning`: clean. The SC2015/SC2016 infos are on main already.

## Not verified

- Git Bash on Windows (gawk) running the whole hook. The views were fuzzed under gawk, not timed.
- The remaining ~0.5 s is bash and the rules' sed/grep calls; not profiled further.

## Residual risk accepted

None new. The budget is 5 s, so a host roughly 7x slower than this one fails the test; that is the
intended alarm, well before the 60 s hook timeout.
