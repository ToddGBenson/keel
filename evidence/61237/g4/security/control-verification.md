# G4 Security verification - TheHub #61237 (keel #182, merged as 9d9b5fb7)

key: 61237
gate: g4 (Verified), Part B (Security)
verdict: pass
findings: 1 Low (F1, not in this story's criteria, needs a follow-up story); 0 Medium, 0 High, 0 Critical
date: 2026-11-18 (verification run about 02:25Z to 03:20Z)
verified at: keel main 7d4c7fb56cd640756efd49d4466b32ed768c23a4 (contains 9d9b5fb7). The script and its test are byte-identical to c7ba09ec, where the QA record was taken (`git diff c7ba09e 7d4c7fb` on both files is empty).
recorded by: independent security reviewer for the PO (Claude Fable 5.2, model claude-fable-5-2)
independence: did not build, review, merge or QA-verify #182 (built by Claude Sonnet, reviewed by Opus, QA by Opus). A different model from all three, but the same vendor, so this is not independent of the vendor's shared blind spots (POAM-008, POAM-017). An agent verdict is evidence; it is not the Delivery Lead's approval.
story: "a missing gitleaks report fails instead of reading clean"
refs: TheHub #61006 (v0.1.0), POAM-018; QA record evidence/61237/g4/qa/traceability.md

## What is being verified

keel ships no service. The deliverable is `scripts/test-gitleaks-allowlist.sh` (run by `./keel check` and the unit suites) and its test. The security property is one sentence: a scan that did not produce a usable report must never be read as "repository clean" (RA-5, IA-5, SI-7). No G2 control allocation exists for this story (keel has no G2 record at all, POAM-018), so the controls below are derived from the story's criteria and the script's own header.

## Verified

| # | Control | Code (keel main 7d4c7fb) | Negative-case test | Result |
|---|---|---|---|---|
| C1 | A report that is missing, empty or not a JSON list is an error, never 0 findings | scripts/test-gitleaks-allowlist.sh:81-90 (`count_findings`: `[ -s ]`, then a list check) | test/gitleaks-allowlist.test.py:148-185, section "a report that is not there fails, never reads clean" (8 checks) | denies |
| C2 | The repository scan refuses an unusable report instead of printing "repository clean" | scripts/test-gitleaks-allowlist.sh:104-111 | same section: "no report file at all", "an empty report file", "a report that is not JSON" each assert a non-zero exit and no "repository clean" | denies |
| C3 | The canary scan refuses an unusable report too, so "nothing detected" cannot come from a scanner that never ran | scripts/test-gitleaks-allowlist.sh:93-101 | same section: "no canary report: the script exits non-zero" | denies |

Item 13 (located in code): C1-C3 located, lines above. The caller, `./keel check` (keel:139-146), turns a non-zero exit into a failed check and a [skip] into a "NOT verified" warning. It predates #182 and was not changed by it; I read it and did not test it.

Item 14 (negative-case test, run as a plain process, no container):

- `python test/gitleaks-allowlist.test.py` on main 7d4c7fb, CI and KEEL_REAL_GITLEAKS unset: **exit 0**, 21 [ok], 0 [FAIL], one honest [skip] for the real-scanner section.
- The same test file against the pre-fix script (worktree at 4b20f550, the parent of 9d9b5fb7): **exit 1**, the six "not there / empty / not JSON" checks [FAIL]. So the test goes red when the control is removed (it is not decorative).
- Lanes on main 7d4c7fb: Concourse `keel/test` build 173 ran the same section, 21 [ok]; Actions `Unit results` run 44211091402 succeeded with 0 [FAIL] lines and the real-scanner line `[ok] real gitleaks, no .git: planted secrets found, allowlist verified`.

Item 15 (adversarial read). I drove the real script with a stub scanner first on PATH (so no container starts) and recorded classes of attempt, on main and on the pre-fix script:

| Class of attempt against the repository scan | main 7d4c7fb | pre-fix 4b20f550 |
|---|---|---|
| no report written, scanner exits non-zero | refused, exit 1 | read as clean, exit 0 |
| report present but empty, or whitespace only | refused | read as clean |
| report is valid JSON but not a list (null, an object, a number, a string) | refused | read as clean |
| report is a truncated list, or a list followed by trailing text | refused | read as clean |
| report starts with a byte-order mark | refused | read as clean |
| the report path is a directory | refused | read as clean |
| the JSON reader itself fails, or exits 0 printing nothing | refused, exit 1 | exit 1 on the canary step; the repository step still printed clean |
| canary scan: no report, a non-list report, or only one of the two planted secrets found | refused | already refused |
| a true empty list with a successful scanner (the honest clean case) | accepted, exit 0 | accepted |
| **an empty list written by a scanner that then exits non-zero** | **accepted as clean, exit 0 (F1)** | accepted as clean |

Other paths read: a stale report cannot be reused (the report directory is a fresh `mktemp -d` per run, :61); the no-scanner path prints [skip] and exits 0, and the caller reports it as NOT verified (keel:142-143), which is an honest skip, not a pass (test/test-manifest.test.py:241-255 exercises that branch; read, not run by me); the numeric tests on an empty count fall to the failing branch (verified by the "exits 0 printing nothing" class).

## Findings

**F1, Low. The scanner's exit status is not read (scripts/test-gitleaks-allowlist.sh:45, :51-53, :104).** `run_gl` discards the status, so a scan that writes an empty list and then fails is read as "repository clean". Reproduced with a stub (last row above). Severity reasoning (item 18): nobody can trigger it from outside; it needs the scanner to fail after writing an empty list, and the canary step, which shares the scanner, would usually fail in the same run. It weakens a self-test, not the secret-scan gate (the `secrets` lane is a separate job). Pre-existing, named in the #182 review and in the QA record's "Could not verify"; not one of this story's four criteria, so it does not fail the story. It needs a follow-up story (for step 2 a non-zero exit with zero findings is always a failed scan, so the fix is small). I did not file one: this record does not write to the tracker.

## Scan results read (items 16-18)

Read anonymously from Concourse, pipeline `keel`, all on main 7d4c7fb (each build's `repo` input ref checked):

| Lane (build) | What it scanned | Result read in the log |
|---|---|---|
| sast (171) | CodeQL: Python, 13 GitHub Actions files, 2 JS/TS files | "CodeQL findings: 0" |
| lint (175), shellcheck | 34 shell scripts, including this one | "clean (34 files, severity>=warning)"; 9 results below warning were uploaded to the platform |
| secrets (169) | gitleaks, 130 commits (main has 130) | "no leaks found" |
| sca (170) | grype over a 45-package SBOM | "grype findings: 0" |
| iac (168) | checkov, github_actions framework only | 644 passed, 0 failed, 0 skipped |
| mykronos-sast (94), mykronos-secrets (96), mykronos-sca (38), mykronos-atlas (97) | the same tools, uploaded to the platform | 0 findings uploaded by each |
| suppression-audit (168) | suppression comments | "No suppressions found." |
| container-scan (1) | nothing | not in service; the lane says itself that this is not a pass. N/A: keel ships no image |

Limits of what the scanners can say here: the deliverable is a bash script. CodeQL does not analyse bash, so shellcheck is the only static analysis that reaches it, and checkov reads workflows, not `ci/`. A green SAST lane says nothing about C1-C3; items 13-15 above do.

Item 17 (dispositions): the lanes report 0 results at their gates, so there is nothing to disposition at gate level. The 9 shellcheck results below warning are **unverified**: I could not read the platform's finding register (see below), so I did not see their dispositions or which files they are in. The script's in-file comments carry no scanner suppression.

## Other Part B items

- Item 19 (DAST): N/A, nothing is deployed.
- Item 20 (SBOM generated and diffed): the mykronos-atlas lane generated an SBOM (58 components) on 7d4c7fb but logged that it could not archive it (HTTP 422) and that the supply chain was "NOT ASSESSED" (the repository resolves no dependency set). I did not see a diff against the previous build. **Unverified**; this story adds no dependency.
- Item 21 (audit events): N/A, the criteria name none.
- Item 22 (threat model): N/A. No trust boundary, entry point or data flow changed; `.sdlc/threat-model.yaml` needs no new row for this story.
- Item 23 (no open Critical or High in scope): none found. How I checked: the scan lanes above on 7d4c7fb; GitHub's code-scanning, Dependabot and secret-scanning alert lists for this repository (each 0 open, read through the API); my own read (F1 is Low). **Not checked:** the platform's finding register, which I could not read with the access I had.

## QA record re-checked

I re-checked the QA record's key claims against the code and the cited runs and found no inaccuracy: the line references for AC1; 21 [ok] and the 8 checks in the "not there" section; the hand-run negative case (reproduced here: exit 1 on main, exit 0 on the pre-fix script); Actions `Unit results` runs 44025836799 (9d9b5fb7) and 44028008524 (c7ba09ec) are consecutive successes on main, each with 0 [FAIL] lines and the real-scanner [ok] line; Concourse `keel/test` builds 167 and 168 carry those two refs and succeeded. Not re-checked: its reading of TheHub 61098.

## Could not verify

- The platform's finding register (see items 17 and 23).
- That real gitleaks writes an empty list for a clean scan: I did not open a real report. The Actions real-scanner check passing on 7d4c7fb implies it (the "clean" branch is only reachable through a report that parses as a list).
- The container branch of `run_gl` (:46-54): no container was started (the host runs production). Its report handling is the same `count_findings`, exercised through the binary branch.

## Did not examine

- Part A (QA) beyond re-checking its key claims, and Part C (not AI-relevant).
- The `secrets` lane's own gate script (ci/scripts/gitleaks-gate.sh): a different control, not delivered by this story.
- Linux directly: my runs were on Git Bash on Windows (bash 5.2); the Linux lanes were read, not run by me.

## What I ran

1. Fresh clone; worktrees at main 7d4c7fb and at 4b20f550 (pre-fix). Nothing was merged or rebased.
2. `python test/gitleaks-allowlist.test.py` in each (results under item 14).
3. A scratch driver (not committed) that puts a stub `gitleaks` first on PATH and runs the real script once per class in the table above, in both trees.
4. Concourse anonymous API: the job list for pipeline `keel`, then each build's resources (input ref) and event stream (log) for the builds named above.
5. `gh run view 44211091402 --log`, and `gh api` reads of the three alert lists.
