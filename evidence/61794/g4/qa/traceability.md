# G4 QA verification - TheHub #61794, keel half (keel #179, merged as af0607e5)

key: 61794
gate: g4 (Verified), Part A (QA)
verdict: fail
failed criterion: AC2 (no regression test runs the no-jq fallback N >= 50 times) and so AC5 (the N-run test is not in the log); AC3 is partly met (the helper-fault half holds, the parse-error half is not implemented; Security finding F1, TheHub 62016)
date: 2026-11-17 (06:42Z to 07:20Z)
verified at: keel main c7ba09eccb363a4badb2ad80f5fbf01311440b8a (contains af0607e5)
recorded by: Verifier agent for the PO (Claude Opus 5.5, model claude-opus-5-5), session https://claude.ai/code/session_017AsgBjWY1XqoZ6sEHuwhc1
independence: did not build, review or merge #179 (built by Claude Opus 5.5 on the Linux runner laptop, reviewed by Opus). Same model as the builder and reviewer, so this is not independent of their blind spots (POAM-008, POAM-017).
story: "guard-bash.sh: KB-177 allowed once in the no-jq PowerShell fallback (possible intermittent fail-open)"
scope: keel only. The binnacle port (binnacle #79, AC4) is the binnacle sub-PO's and was not examined.
refs: TheHub #61006 (v0.1.0), POAM-018

## Real environment

The delivered thing is `.claude/hooks/guard-bash.sh` on keel main, which runs as a PreToolUse hook in every keel checkout and fork, and is exercised by the Concourse `keel/test` lane (linux workers) and Actions `Unit results`.

## Traceability (AC -> test -> result -> evidence)

| AC | Test / check | Result | Evidence |
|---|---|---|---|
| AC1 the nondeterminism is reproduced (with the run count) or bounded with evidence | evidence/61794/g3/self-review.md and test/hook-fail-closed.test.py | partly met | not reproduced; bounded by mechanism: a failing `tr` alone lets KB-177 through on the old hook, and the new hook blocks when any helper fails. The self-review itself says the root cause is "unproven" |
| AC2 a regression test runs the fallback N times (N stated, >= 50) on KB-177 and the other curl write cases, every run blocks | searched test/hook-fail-closed.test.py, test/hook-bypass-corpus.test.py, .claude/hooks/selftest.sh for a repeat count | **not met** | no such test exists. The only `range(5000)` in those files builds a padding string. The corpus test runs each entry once per mode (224 entries, 804 hook runs) |
| AC3 the fallback fails closed on any parse error or ambiguity (test) | test/hook-fail-closed.test.py | **partly met** (corrected 2026-11-18, see Correction) | Concourse keel/test 168 (build 2434598, ref c7ba09ec): every check in the section [ok] — helper exit 2, jq killed, exit 1/127, unbound variable, fault file emptied or removed all block; 390 KB padded commands block in no-jq Bash and PowerShell. That is the helper-fault half. The parse-error half does not hold: the Security record (evidence/61794/g4/security/control-verification.md, F1) shows the no-jq fallback allows a payload it cannot parse, with no message; tracked as TheHub 62016 |
| AC4 the same fix and test land in binnacle | - | not examined | out of keel scope |
| AC5 keel and binnacle main unit suites green at the merged sha, and the N-run test is in the log | Actions Unit results 43807902062 on af0607e5: success; Concourse keel/test 168 on c7ba09ec: success | keel suite met; **N-run part not met** | no N-run test exists to appear in the log (AC2) |

## What I ran

1. `git clone` keel -> c7ba09ec; read the hook, both hook tests and the corpus (35 `curl-route` must-block entries, KB-051..KB-177).
2. Read Concourse anonymously: keel/test build 168 resources (ref c7ba09ec) and events; the hook-fail-closed section and the corpus summary "224 corpus entries, 804 hook runs, 0 failed, 32 open (known gaps)".
3. `gh run list --workflow unit-results.yml --branch main`: af0607e5 success (43807902062); 9d9b5fb7 and c7ba09ec success.
4. **Attempted, no result:** a driver (scratchpad, not committed) that imports the corpus test's own `load_corpus`, `make_env("no-jq")` and `run_one` and runs every curl-route must-block entry x {Bash, PowerShell} 50 times in the no-jq fallback, 8 in parallel, on this host's Git Bash (no jq installed, so the fallback is the real one). 3,500 hook runs; started 06:46:50Z. Claude Code killed it at about 07:15Z because the host was low on memory (it runs production), before it printed a result. It was not restarted. **No N-run evidence exists from this verification**, so none is claimed.

## Could not verify

- That the fallback blocks on every one of N >= 50 runs: the attempt above produced no result.
- The original allow's root cause (the self-review says so too).
- Git Bash on Windows, where the hook also runs, through the full fail-closed test: not run here (the same memory constraint).

## Did not examine

- binnacle #79 and binnacle/test.
- guard-write.sh (follow-up 61844) and PATH pinning (follow-up 61843).
- Part B (security verification) as a separate verdict, and Part C (not AI-relevant). This is the QA verdict only.

## To pass

Fix AC3 (TheHub 62016): the no-jq fallback must refuse a payload it cannot parse, with a message, and a negative-case test must cover it (Security F1). Then:

Add the N-run regression test AC2 names (N stated, >= 50, KB-177 and the other curl write cases, no-jq fallback, both tools) to the test manifest, and re-verify when its count is in a main `keel/test` log. Run it on a linux worker, not this host.

## Correction

2026-11-18 03:13Z: the AC3 row was corrected from "met" to "partly met" after the independent Security review (Part B) of this PR. The helper-fault checks it cited hold; the parse-error half of the criterion is not implemented in the no-jq fallback (Security record F1, TheHub 62016). AC3 is now also a failed criterion and is in "To pass". The verdict stays fail. This corrects a row marked satisfied without being fully verified (POAM-018).
