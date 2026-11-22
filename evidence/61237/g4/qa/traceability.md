# G4 QA verification - TheHub #61237 (keel #182, merged as 9d9b5fb7)

key: 61237
gate: g4 (Verified), Part A (QA)
verdict: pass
date: 2026-11-17 (verification run 06:42Z to 07:00Z)
verified at: keel main c7ba09eccb363a4badb2ad80f5fbf01311440b8a (contains 9d9b5fb7)
recorded by: Verifier agent for the PO (Claude Opus 5.5, model claude-opus-5-5), session https://claude.ai/code/session_017AsgBjWY1XqoZ6sEHuwhc1
independence: did not build, review or merge #182 (built by a Claude Sonnet 5.5 builder; reviewed by Opus). Same vendor and model family as the reviewer, so this is not independent of the reviewer's blind spots (POAM-008, POAM-017).
story: "a missing gitleaks report fails instead of reading clean"
refs: TheHub #61006 (v0.1.0), POAM-018

## Real environment

keel ships no service. What #182 delivers is `scripts/test-gitleaks-allowlist.sh` and its test, which run in three places: the Concourse `keel/test` lane on main (linux workers), GitHub Actions `Unit results` on main, and a developer's `./keel check`. All three were read or run.

## Traceability (AC -> test -> result -> evidence)

| AC | Test / check | Type | Result | Evidence |
|---|---|---|---|---|
| AC1 comments name bash 5.3 / ubuntu-26.04 | `grep -n 'bash 5\|ubuntu-2'` on the two files at c7ba09e | inspection | met | scripts/test-gitleaks-allowlist.sh:24-25, test/gitleaks-allowlist.test.py:99-100 both say bash 5.3 / ubuntu-26.04 |
| AC2 count_findings fails on a missing or unparsable report | `test/gitleaks-allowlist.test.py` section "a report that is not there fails, never reads clean" (8 checks) | unit, stubbed scanner | met | local run exit 0, 21 ok / 0 FAIL; Concourse keel/test 168 (build 2434598, ref c7ba09e) same 8 [ok] |
| AC2, negative case run by hand (below) | stub `gitleaks` on PATH that writes NO report for the repository scan | integration, real script | met | c7ba09e: exit 1, "[FAIL] no usable report from the repository scan"; pre-fix 4b20f550: exit 0, "repository clean" |
| AC3 two consecutive green Unit results runs on main | GitHub Actions `Unit results` on main | CI | met (substance); see "Could not verify" | run 44025836799 on 9d9b5fb7 success; run 44028008524 on c7ba09ec success; consecutive, no main run between them. Concourse keel/test 167 (9d9b5fb7) and 168 (c7ba09ec) also succeeded |
| AC4 real-gitleaks --no-git path exercised | test section "the real scanner on a copy with no .git", runs only under CI=true | CI, real scanner | met | both Actions runs above print "[ok] real gitleaks, no .git: planted secrets found, allowlist verified"; Concourse keel/test 168 prints an honest [skip] (not opted in) |

No test without an AC: the "not opted in, the real section starts nothing" checks trace to the #182 review finding (no containers on a shared host), recorded on the story.

## What I ran

All plain processes; no container was started (the host runs production).

1. `git clone https://github.com/ToddGBenson/keel.git` -> HEAD c7ba09eccb36, and `git worktree add ... 4b20f55` (the parent of 9d9b5fb7, i.e. main before #182).
2. Two stub scanners named `gitleaks`, put first on PATH so the script takes its binary branch and never reaches docker. Both write two findings for the canary scan. For the repository scan, stub `missing` writes no report file and exits 1 (a failed invocation); stub `clean` writes `[]`.
3. `PATH=<stub>:$PATH bash scripts/test-gitleaks-allowlist.sh` in each tree:

```
=== c7ba09ec stub=missing
  [ok]   planted secrets still detected (2/2) — allowlist has not blinded the scanner
  [FAIL] no usable report from the repository scan — a failed scan is not a clean repository
  allowlist FAILED verification
exit=1
=== c7ba09ec stub=clean
  [ok]   planted secrets still detected (2/2) — allowlist has not blinded the scanner
  [ok]   repository clean — the selftest.sh fixture is correctly allowlisted
  allowlist verified in BOTH directions
exit=0
=== 4b20f550 (pre-fix) stub=missing
  [ok]   planted secrets still detected (2/2) — allowlist has not blinded the scanner
  [ok]   repository clean — the selftest.sh fixture is correctly allowlisted
  allowlist verified in BOTH directions
exit=0
```

   The pre-fix script reads a scan that wrote nothing as a clean repository; the delivered one refuses it, and still passes a genuine `[]`. This is the item-3 check (the behaviour goes away when the implementation is removed) done on the real script, not on the test's own stub.
4. `python test/gitleaks-allowlist.test.py` (CI and KEEL_REAL_GITLEAKS unset): exit 0, 21 [ok], 0 [FAIL], one honest [skip] for the real section.
5. Read Concourse anonymously: `GET /api/v1/teams/main/pipelines/keel/jobs/test/builds`, `/api/v1/builds/2434598/resources` (repo ref c7ba09ec) and `/events` (the build log), and the same for 2434113 (ref 9d9b5fb7). 0 [FAIL] lines in either log.
6. `gh run view 44025836799 --log` and `gh run view 44028008524 --log` (keel, Unit results, push to main): 0 [FAIL] lines; the real-scanner [ok] line is in both.

## Could not verify

- AC3 says the two green runs "are recorded on #61098". They are not: TheHub 61098's detail (read 2026-11-17 06:5xZ) ends with the 2026-11-02 reconciler note. The runs exist and are cited here; writing them onto 61098 is the PO's, not done by this record.
- The builder's open question (does real gitleaks write `[]` for a clean scan?) is answered only indirectly: the Actions real-scanner check passes with exit 0, and step 2 can only reach "repository clean" through a report that parses as a list, so real gitleaks v8.18.4 on ubuntu-26.04 did write a list. I did not open that report file myself.
- gitleaks's own exit status is still ignored by `run_gl`; a scan that writes `[]` and then fails would read clean. Pre-existing, noted in the #182 review, not a criterion of this story.

## Did not examine

- Part B (security verification) and Part C (AI, not AI-relevant) of G4: this record is the QA verdict only. G4 needs the Security verdict recorded separately.
- Part A items 4-10 (authorization, persistence, load, dependency failure, rollback, observability, accessibility) do not apply to a test script with no service, data store or UI; not assessed rather than claimed.
- No exploratory charter was run beyond the stub experiment above.
- Git Bash on Windows was the local shell; the linux lanes were read, not run by me.
