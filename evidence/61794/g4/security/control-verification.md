# G4 Security verification - TheHub #61794, keel half (keel #179, merged as af0607e5)

key: 61794
gate: g4 (Verified), Part B (Security)
verdict: fail
failed criterion: item 13 and item 14 (the story's third criterion, "any parse error or ambiguity blocks with a clear message (test)", has no implementation and no negative-case test for a payload the no-jq fallback cannot read: F1); item 15 (two classes reach past the fail-closed check: F1, F2); item 14 also for the missing N-run test the QA record names
findings: 2 Medium (F1; F2 known and tracked), 1 Low (F3), 1 nit (F4); 0 High, 0 Critical
date: 2026-11-18 (verification run about 02:25Z to 03:20Z)
verified at: keel main 7d4c7fb56cd640756efd49d4466b32ed768c23a4 (contains af0607e5). The hook has changed since c7ba09ec, where the QA record was taken (#184 linear-time views, #190 a new rule); the line numbers below are main's.
recorded by: independent security reviewer for the PO (Claude Fable 5.2, model claude-fable-5-2)
independence: did not build, review, merge or QA-verify #179 (built, reviewed and QA-verified by Claude Opus 5.5). A different model, the same vendor (POAM-008, POAM-017). An agent verdict is evidence; it is not the Delivery Lead's approval.
story: "guard-bash.sh: KB-177 allowed once in the no-jq PowerShell fallback (possible intermittent fail-open)"
scope: keel only. binnacle carries the same hook and was not examined; F1 and F2 should be assumed to apply there.
refs: TheHub #61006 (v0.1.0), POAM-018; QA record evidence/61794/g4/qa/traceability.md

## What is being verified

`.claude/hooks/guard-bash.sh` is the PreToolUse hook that refuses agent shell calls the agent constraints forbid (AIC-3, AIC-5, AIC-11). The harness runs the call unless the hook exits 2, so every way the hook can end without a verdict is a way a forbidden call runs. The story's security criteria are that the hook fails closed: when one of its own helpers fails, and on "any parse error or ambiguity". No G2 control allocation exists (keel has no G2 record, POAM-018); the controls below come from the story's criteria and the hook's header.

## Verified

| # | Control | Code (keel main 7d4c7fb) | Negative-case test | Result |
|---|---|---|---|---|
| C1 | Every text helper runs through a wrapper that records a real error | .claude/hooks/guard-bash.sh:41-85 (`guard_run`, the wrappers) | test/hook-fail-closed.test.py:133-151, "one helper fails: the hook refuses" | denies |
| C2 | An allow becomes a block when a fault was recorded, when the fault record was emptied or removed, or when the hook ends with any code but 0 and 2 | .claude/hooks/guard-bash.sh:87-111 (`guard_exit`, the EXIT trap) | test/hook-fail-closed.test.py:156-172 | denies |
| C3 | No early exit can turn a match into "no match" on a large command | .claude/hooks/guard-bash.sh:57-74 (grep and head wrappers) | test/hook-fail-closed.test.py:120-131 | denies |
| C4 | The hook cannot start without its fault record | .claude/hooks/guard-bash.sh:42-46 | none found; read only | read, not tested |
| C5 | A payload the hook cannot read is refused ("any parse error or ambiguity blocks with a clear message") | **not found.** .claude/hooks/guard-bash.sh:150 does the opposite: an empty extracted command exits 0 | **none** | **not implemented in the no-jq fallback (F1)** |

Item 13: C1-C4 located. C5 could not be found, and by the gate's rule a control that cannot be found is not implemented.

Item 14 (run as plain processes, no container):

- `python test/hook-fail-closed.test.py` on main 7d4c7fb, on this Windows host (Git Bash 5.2, no jq installed, so the no-jq fallback is the real one). The test builds its tool directory with symlinks, which this host refuses, so I ran it unmodified through a wrapper that replaces each link with a one-line script that execs the same tool. Result: **exit 1**, 100 [ok], 8 [FAIL]. Every verdict check passed: all 87 fault and injected-exit cases still blocked, and all 8 large commands blocked. The 8 failures are the test's time budget only: the large commands were decided in 11.8 to 34.4 s against a 5 s budget (see F3). This is the first run of this test on Windows that I know of; the QA record lists it as not run.
- Linux lanes on main 7d4c7fb: Concourse `keel/test` build 173 ran the section natively, 108 [ok], "all passed"; the corpus line reads "224 corpus entries, 804 hook runs, 0 failed, 32 open (known gaps)" and the hook self-test "330 passed, 0 failed". Actions `Unit results` run 44211091402 succeeded with 0 [FAIL] lines.
- Red when the control is removed: not re-run by me. The #179 self-review records 128 failures against the pre-fix hook; I read that claim and did not reproduce it.

Item 15 (adversarial read). Classes of attempt against the fail-closed check, run on main in the real no-jq fallback. Inputs were must-block commands from the repository's own public test; no new bypass text is written here.

| Class of attempt | Outcome |
|---|---|
| One helper exits with an error, or is killed, in turn: grep, sed, awk, tr, cat, jq | blocked, as an internal error (the test above) |
| The hook ends with an unexpected code, or its fault record is emptied or removed while it runs | blocked |
| A command padded past the pipe buffer, or made of very many short lines | blocked (slowly on this host: F3) |
| A helper outside the wrappers | none found by reading: the hook's external tools are the wrapped ones plus the two it calls for its fault record |
| **The payload cannot be read at all: empty input, input cut off inside the command, input that is not JSON, a command that is not a string, the value on a different line from its key** | **allowed, exit 0, no message (F1)** |
| **The payload has more than one candidate for the command (a second key later in the payload)** | **the fallback takes the last one; when that one is harmless the call is allowed (F1)** |
| **A helper that answers wrongly but exits 0 (found earlier on the search path): "no match", empty output, or reads nothing** | **allowed for all three must-block commands (F2)** |
| The hook itself is killed, or runs past the harness's time limit | outside the hook: the harness runs the call. Not tested; see F3 for the margin measured here |
| Another local process rewrites the fault record to look untouched while a helper fails | not tested. It needs code already running on the host, which could do the forbidden thing itself |

## Findings

**F1, Medium. In the no-jq fallback, a payload the hook cannot read is allowed (.claude/hooks/guard-bash.sh:145-150).** The fallback extracts the command with one pattern, and an empty result ends the hook with exit 0. I ran eleven payload shapes: the well-formed ones were blocked by their rule; empty input, a payload cut off inside the command string, bare text, a non-string command, a value on the next line, and a payload with a second, harmless command key were all allowed, silently. This is the story's third criterion, and the hook's own test says "a guard that cannot read the command must refuse it". Severity reasoning (item 18): I found no way to produce these shapes from the fields the model controls, because the harness writes one well-formed line and a quote inside a string value is always escaped; reaching them takes a fault in how the payload is delivered or a change in the payload's shape. That is exactly the family of the original incident (a fault, then a silent allow), and one member is confirmed: a payload read that returns nothing with a success status allows every must-block command (third row from the bottom of the table; the #179 self-review lists it as "still not caught. Unverified"). So Medium, not High. No negative-case test exists. The jq path was not run (no jq on this host); by reading, invalid JSON fails there and is blocked, and empty input is allowed there too. Fix direction: for the two tools this hook is registered on, no readable command is a block with a message, not an allow.

**F2, Medium, known and tracked. A helper that lies is believed.** The wrappers catch a helper that fails; one that exits 0 with a wrong answer is not caught, and the search path is not pinned. Reproduced on main for three helpers. This is review finding #3 of #179, tracked as TheHub 61843 (open, not started). I agree with Medium: it takes a write to a directory on the hook's search path first, and the corpus already lists 32 open known gaps of similar effort. It stays in this record because it is a way past the check this story delivered, and it is still open on main.

**F3, Low. On Windows the time margin is thin and unmeasured under load.** A hook that runs past the harness's limit lets the call proceed (60 s, per the comment at test/hook-fail-closed.test.py:50; .claude/settings.json sets no other limit). #184 made the hook linear and the test holds a 5 s budget on Linux. On this Windows host a short command took 8 to 12.5 s and the test's large commands 8 to 24 s (11.8 to 34.4 s inside the link-replacing wrapper), all blocked and all inside 60 s, with the host under memory pressure at the time. The budget check therefore fails on Windows, and nothing measures how close a loaded host gets to the limit. Not a bypass today; **unverified** beyond these measurements.

**F4, nit (item 22).** The design of the control changed (wrappers, an exit trap), but no trust boundary did. `.sdlc/threat-model.yaml`'s `agent-guard-hooks` control still describes the hook correctly; its `reviewed_at` is 2026-10-17 and was not re-confirmed after #179, #184 and #190.

**The N-run gap (QA's finding, restated for item 14).** The observed failure was intermittent. The fault-injection test proves the hook blocks when a helper fails; no test runs the fallback N >= 50 times, so nothing shows the intermittent allow is gone, and its root cause is unproven (the self-review says so). I did not attempt an N-run here: at 8 to 12.5 s per hook run on this host, 3,500 runs is most of a working day, and the QA attempt was killed for memory. It belongs on a linux worker.

## Where this record disagrees with the QA record

The QA record marks the third criterion "met", citing the helper-fault checks in test/hook-fail-closed.test.py. Those checks do show what they say: the hook blocks when a helper fails. They do not cover the other half of the criterion as written ("any parse error or ambiguity blocks with a clear message"), and F1 shows a payload the fallback cannot read is allowed without a message. On this evidence the criterion is partly met, not met, and it belongs in the QA record's failed criteria and "To pass" list. Correcting that record is its author's, not mine; this section is the cross-reference until it is.

The QA record's other key claims, re-checked, hold: no test repeats the fallback N times (the only `range(5000)` builds padding); the corpus line "224 corpus entries, 804 hook runs, 0 failed, 32 open"; 35 `curl-route` entries; Actions `Unit results` run 43807902062 on af0607e5 succeeded; Concourse `keel/test` build 168 ran on c7ba09ec with 0 [FAIL]. Its "could not verify" item for Git Bash on Windows is now covered by the run under item 14.

## Scan results read (items 16-18)

Read anonymously from Concourse, pipeline `keel`, all on main 7d4c7fb (each build's `repo` input ref checked): sast 171 (CodeQL over Python, 13 Actions files, 2 JS/TS files: 0 findings), lint 175 (shellcheck over 34 shell scripts including this hook: clean at warning and above; 9 results below warning uploaded), secrets 169 (gitleaks, 130 commits: no leaks), sca 170 (grype, 45 packages: 0), iac 168 (checkov, github_actions framework only: 644 passed, 0 failed), mykronos-sast 94, mykronos-secrets 96, mykronos-sca 38, mykronos-atlas 97 (0 findings uploaded by each), suppression-audit 168 ("No suppressions found."), container-scan 1 (not in service, and says it is not a pass; N/A, keel ships no image).

What the scanners cannot say here: the deliverable is a 921-line bash hook. CodeQL does not analyse bash; shellcheck checks syntax and quoting, not whether a guard fails closed. F1 and F2 are invisible to every lane above. The corpus test's "32 open (known gaps)" is the repository's own register of ways past the rules; I read the count and did not re-triage the 32.

Item 17: 0 results at the lanes' gates. The hook's in-file `shellcheck disable=SC2317` comments each carry a reason (read at :48, :79, :82, :84, :86; there are no others). The 9 shellcheck results below warning: **unverified** (the platform's finding register was not readable with the access I had).

## Other Part B items

- Item 19 (DAST): N/A, nothing is deployed.
- Item 20 (SBOM diff): **unverified**; #179 adds no dependency.
- Item 21 (audit events): N/A as written. The hook's only record of a block is its stderr message; the criteria name no audit event.
- Item 22: no new boundary; F4.
- Item 23 (no open Critical or High in scope): none found. How I checked: the lanes above; GitHub's code-scanning, Dependabot and secret-scanning alert lists (0 open each); my own read (F1 and F2 Medium). **Not checked:** the platform's finding register.

## Could not verify

- That the intermittent allow is gone (no N-run evidence exists, here or in the QA record).
- The jq path: no jq on this host, so only the no-jq fallback ran here. The Linux lanes ran both.
- The harness's behaviour when a hook is killed or times out: taken from the hook's header and the test's comments, not tested.

## Did not examine

- binnacle #79 and the binnacle hook.
- guard-write.sh (its own story, 61844, merged as #186) and the rules themselves: this record is about failing closed, not about whether each rule is complete.
- Part A beyond re-checking its key claims; Part C (not AI-relevant).

## To pass

1. F1: refuse a payload with no readable command (both tools the hook is registered on), with a message, and add the negative-case test for each shape in the item 15 table.
2. The N-run regression test the QA record names, run on a linux worker.
3. F2 is 61843's; this story need not wait for it, but the verdict should be re-read when it lands.
4. F3: decide what budget the test should hold on Windows, or record that Windows is out of the measured envelope.

## What I ran

1. Fresh clone; a worktree at main 7d4c7fb. Nothing was merged or rebased.
2. `test/hook-fail-closed.test.py` through the link-replacing wrapper (19.5 minutes, one hook at a time).
3. Three scratch drivers (not committed), all reusing the test's own payload builder and its must-block commands: the eleven payload shapes; the three wrong-answer helpers; one timing pass over the large commands.
4. Concourse anonymous API: job list, build resources and event streams for the builds named above.
5. `gh run view 44211091402 --log`; `gh api` reads of the three alert lists.
