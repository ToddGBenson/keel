# G4 Security verification - TheHub #61778, keel half (keel #178, merged as 3373c614)

key: 61778
gate: g4 (Verified), Part B (Security)
verdict: fail
failed criterion: item 15 (one check can be reached past: F1); item 14 (three controls have no negative-case test: F1, F2, F3); item 22 (the declared threat model was not updated for the new trust boundary: F4)
findings: 2 Medium (F1, F4), 1 Low (F2), 1 unverified (F3); 0 High, 0 Critical
date: 2026-11-18 (verification run about 02:25Z to 03:20Z)
verified at: keel main 7d4c7fb56cd640756efd49d4466b32ed768c23a4 (contains 3373c614). `ci/`, test/pr-pick.test.py and test/check-run.test.py are unchanged since c7ba09ec, where the QA record was taken. Live: Concourse pipeline `keel`, job `pr-checks`, build 249 (repo input 7d4c7fb).
recorded by: independent security reviewer for the PO (Claude Fable 5.2, model claude-fable-5-2)
independence: did not build, review, merge or QA-verify #178 (built and reviewed by Claude Opus 5.5, QA by Opus). A different model, the same vendor (POAM-008, POAM-017). An agent verdict is evidence; it is not the Delivery Lead's approval.
story: "Concourse posts PR-head checks for keel and binnacle (the pr-gates pattern), so their PRs are judged without GitHub Actions"
scope: keel only. binnacle carries the same files and was not examined; F1 and F2 should be assumed to apply there until someone looks.
refs: TheHub #61006 (v0.1.0), POAM-018; QA record evidence/61778/g4/qa/traceability.md

## What is being verified

The `pr-checks` job runs a pull request head's unit suites on a Concourse worker and reports the result as the `Concourse / keel` check on that head. That is a new trust boundary: code from a branch runs on a worker before anyone has reviewed it, in a job whose other steps hold the repository's deploy key and the platform ingestion token. No G2 control allocation exists (keel has no G2 record, POAM-018), so the controls below are derived from the design stated in ci/scripts/pr-pick.sh, ci/scripts/pr-checks.sh, ci/pipeline.yml and the #178 review.

The check matters more than the design assumed: `Concourse / keel` is one of two required status checks on `main`, with no required approving review (live branch protection, read through the API on 2026-11-18).

## Verified

| # | Control | Code (keel main 7d4c7fb) | Negative-case test | Result |
|---|---|---|---|---|
| C1 | A fork's head is never judged: only a head that is the tip of a branch in this repository, open (it has a merge ref), and not the base branch | ci/scripts/pr-pick.sh:83-92 | test/pr-pick.test.py:151-153 | denies; red when the filter is removed |
| C2 | The task that runs pull request code gets no credential at all | ci/tasks/pr-checks.yml:17-23 (no `params`), ci/pipeline.yml:1264-1269 | test/check-run.test.py:233 | denies; red when a token is added |
| C3 | Every step that holds a credential runs main's task file and script and takes no pull request code as an input; the end report reads only the head's sha from its own output | ci/pipeline.yml:1229-1247, ci/scripts/check-run.sh:33-51, ci/scripts/pr-pick.sh:156-159 | test/check-run.test.py:147-179 (structural rule, with bad fixtures), :336-352 | denies |
| C4 | Anything but a 40-character hex sha is refused, not guessed | ci/scripts/check-run.sh:36-51, ci/scripts/pr-pick.sh:87 | test/check-run.test.py:336 | denies |
| C5 | An answer from the platform that is not created/updated/unchanged, or a failed request, fails the pick | ci/scripts/pr-pick.sh:106-131 | test/pr-pick.test.py:185-189 | denies |
| C6 | The git host key is pinned and an SSH uri without a key is refused | ci/scripts/pr-pick.sh:56-65 | test/pr-pick.test.py:191-196 | denies (text check for the pin) |
| C7 | A head that moved between listing and fetch is never reported on | ci/scripts/pr-pick.sh:143-155 | **none in the repository (F2)** | denies when I exercised it by hand |
| C8 | "Nothing to judge" is a pass only when the pick really picked nothing | ci/scripts/pr-checks.sh:16-20, ci/scripts/pr-pick.sh:134-138 | test/pr-pick.test.py:206-210 covers the honest cases only | **can be reached past (F1)** |
| C9 | Pull request code cannot change the `repo/` that the later credentialed hooks run from | Concourse's input-volume semantics; nothing in this repository | **none (F3)** | **unverified** |

Item 13: C1-C8 located, lines above. C9 has no implementation in this repository; it rests on the CI system.

Item 14 (run as plain processes, no container):

- `python test/check-run.test.py` on main 7d4c7fb: **exit 0**, 65 [ok], 0 [FAIL].
- `python test/pr-pick.test.py` on main 7d4c7fb: on this Windows host it stops with **exit 1** after 9 [ok], on a Python FileExistsError in the test's own cleanup (read-only git objects cannot be removed, so its next `mkdir` fails). That is the harness, not a control. Run unmodified through a wrapper that only makes the cleanup remove read-only files: **exit 0**, 22 [ok], 0 [FAIL]. Concourse `keel/test` build 173 (linux, main 7d4c7fb) ran it natively: 22 [ok], "all passed".
- Would the tests fail if the controls were removed? In a scratch worktree (never committed): with the fork filter deleted from pr-pick.sh the test exits 1 and "a fork's head is never asked about" is among the [FAIL]s; with the ingestion token added to the pr-checks task in ci/pipeline.yml, check-run.test.py exits 1 on "the task that runs pull-request code gets no params" and on the structural rule.

Item 15 (adversarial read). Classes of attempt, each run against the real scripts with a local bare repository standing in for the remote and a stub in place of the platform (the test's own harness):

| Class of attempt | Outcome |
|---|---|
| A fork's head (no branch here points at it) | never asked about, never checked out |
| A head that is an older commit of a branch here, not its tip | never asked about |
| A fork's head that equals a branch tip here | judged. By design: that commit was pushed here by someone with write access |
| A branch name carrying shell metacharacters | no execution; the name is only printed and written to a file |
| The pull request's tree carries its own forged picked-head record | overwritten by the pick after checkout; the judge reads the real one |
| A pull request with no pins file | the judge fails; the end report is failure |
| The head moves between listing and fetch | the pick fails; no sha is written, so nothing is reported (C7 holds, untested: F2) |
| **The pull request's tree carries the judge's own "nothing was picked" marker** | **the judge prints "No pull request head to judge this run", runs no suite, exits 0, and the end report posts `success` on that head (F1)** |
| A pull request weakens or deletes its own suites | passes. Inherent: the suites are the pull request's. Only the judging script is main's |
| Pull request code writes into `repo/` to change what the credentialed hooks run | not tested; no container was started and no job was triggered (F3) |

## Findings

**F1, Medium. A pull request can make the check green without any suite running (ci/scripts/pr-checks.sh:16-19, ci/scripts/pr-pick.sh:154-156).** The judge's "nothing was picked" marker lives in the same directory the pick checks the pull request out into, and the pick does not clear it after checkout, so a tree that carries the marker is read as "nothing to judge" while its sha is still reported. Reproduced end to end with the real pr-pick.sh, pr-checks.sh and check-run.sh: pick exit 0 with the head's sha written; judge exit 0 with no suite started; the end report's body carries `"conclusion":"success"` for that sha. The exact input is not written here (public repository); the PO has it. Severity reasoning (item 18): it needs write access to this repository (a fork is never judged), the added file is visible in the diff, and a writer can already weaken the suites the judge runs. It is still more than a nit: the log claims nothing was judged while a success is posted on a named head, `Concourse / keel` is required on `main`, and no approving review is. No negative-case test exists. Fix direction: keep the pick's markers outside the checkout (the sha already goes to its own output), or clear them after checkout; add the test.

**F2, Low. The moved-head refusal has no negative-case test (ci/scripts/pr-pick.sh:143-155).** The control works (exercised by hand with a wrapper that moves the ref between listing and fetch: the pick exits 1 and writes neither the sha nor the picked-head record), but "any control without a negative-case test" is a G4 fail condition.

**F3, unverified. The isolation that keeps the ingestion token away from pull request code is assumed, not tested.** The pr-checks task gets `repo/` (main's checkout) as an input beside the pull request's code, and the end hooks then run `repo/ci/scripts/check-run.sh` with the token. That is safe only if a task's writes to an input do not reach later steps. Concourse documents that they do not (only declared outputs propagate, and this task declares none, which test/check-run.test.py enforces), and the #178 self-review says the same and marks it "not tested". I did not test it either. If it were false this would be High (any branch could read or use the token). Verify once on a worker with a harmless write.

**F4, Medium (gate item 22, not a vulnerability). The declared threat model was not updated.** `.sdlc/threat-model.yaml` was last changed on 2026-11-14 (#164), two days before #178 merged. Its `concourse-pipeline` entry point says nothing about pull request code running on the workers, and its `github-repository` boundary still describes a protection (one approving review, no required checks) that the live settings no longer match (two required checks, no required review). The reasoning exists, in ci/README.md and the self-review, but the file the platform loads does not carry it. The note below is the missing content, written as the reviewer's reading, not as an approved model.

**Observation, no severity assigned. Who can put code on the worker is wider than "writers".** A branch pushed by the dependency-update bot is a same-repository branch, so its head is judged: `pr-checks` build 86 judged pull request #181, a bot branch. The judge then installs that head's own pins (`pip install --require-hashes -r` from the pull request, ci/scripts/pr-checks.sh:25-26). So a compromised upstream release proposed by the bot would execute on a worker inside the network, with no credential but with the network, before a human has looked. The self-review's "Residual risk accepted" paragraph covers writers only and was written by the building agent; I found no human-approved acceptance (a POA&M row or a security exception). That needs the operator's decision; it is not mine to accept.

## Threat model note for the new boundary (item 22)

Boundary: a pull request head's code -> a Concourse worker (task container, network, no params), inside a job whose other steps hold the deploy key and the ingestion token.

| STRIDE | Threat | Control | State |
|---|---|---|---|
| Spoofing | A fork passes as a branch of this repository | C1 | verified |
| Spoofing | A pull request verdict is mistaken for the main chain's verdict (same check name) | squash-only merges keep a head's sha out of main's history (live setting read: squash only) | verified by reading the setting; not tested |
| Tampering | The pull request changes how it is judged | the judging script is main's; the suites and the in-band marker are the pull request's | **F1** |
| Tampering | Pull request code alters what the credentialed hooks run | C9 | **F3, unverified** |
| Repudiation | A verdict cannot be traced to a run | the build log is public; the check names the sha, but its link does not lead to the build (QA record, AC4) | weak |
| Information disclosure | The deploy key or the token reaches pull request code | C2, C3 | verified, subject to F3 |
| Information disclosure | A credential in the public build log | I counted credential-shaped strings in the logs of builds 86 and 249: 0 | read for two builds only |
| Denial of service | A pull request holds the verdict lane | 20-minute task timeout, serial job (ci/pipeline.yml:1221, :1269) | read, not tested |
| Elevation of privilege | Unreviewed code runs with network access inside the network | none beyond "no credential"; accepted in the builder's self-review only | **open, see the observation** |

## Scan results read (items 16-18)

Read anonymously from Concourse, pipeline `keel`, all on main 7d4c7fb (each build's `repo` input ref checked): sast 171 (CodeQL over Python, 13 Actions files, 2 JS/TS files: 0 findings), lint 175 (shellcheck over 34 shell scripts including the three delivered here: clean at warning and above; 9 results below warning uploaded), secrets 169 (gitleaks, 130 commits: no leaks), sca 170 (grype, 45 packages: 0), iac 168 (checkov, github_actions framework only: 644 passed, 0 failed), mykronos-sast 94, mykronos-secrets 96, mykronos-sca 38, mykronos-atlas 97 (0 findings uploaded by each), suppression-audit 168 ("No suppressions found."), container-scan 1 (not in service, and says it is not a pass; N/A, keel ships no image).

What the scanners cannot say here: CodeQL does not analyse bash or Concourse YAML, and checkov ran the github_actions framework only, so no scanner reads `ci/pipeline.yml`'s credential flow. The repository's own structural test (C3) is the only automated check on it; F1, F3 and F4 are invisible to every lane above.

Item 17: 0 results at the lanes' gates, so nothing to disposition there. The 9 shellcheck results below warning: **unverified** (the platform's finding register was not readable with the access I had). One tracked exception was read: the python:3.13 task image is pinned by tag, not digest, with the reason recorded in scripts/validate-pipeline.py (review finding #7 of #178).

## Other Part B items

- Item 19 (DAST): N/A, nothing is deployed.
- Item 20 (SBOM diff): **unverified** (the atlas lane generated an SBOM on 7d4c7fb, could not archive it, and I saw no diff). #178 adds no dependency.
- Item 21 (audit events): N/A as written. The check run on the head is the record the story asks for; QA's AC4 finding (its link is not the build) stands.
- Item 22: **not met**, F4.
- Item 23 (no open Critical or High in scope): none found. How I checked: the lanes above; GitHub's code-scanning, Dependabot and secret-scanning alert lists (0 open each); my own read (F1 and F4 Medium, F2 Low). F3 would be High if the assumption were false and is unverified, not open. **Not checked:** the platform's finding register.

## QA record re-checked

I re-checked the QA record's key claims against the cited runs and found no inaccuracy: on pull request #187's first head (df7f7c4d, committed 06:38:59Z) the `Concourse / keel` check started at 06:41:31Z and concluded success, and its details link is the platform's repository page, not the build (AC4); the Actions run list for that head is not empty (AC3); on #181's head 5c7c7b6a the check concluded failure with the title "Not verified: pr-checks did not pass", and `pr-checks` build 86 judged that head and failed on hook-fail-closed.test (AC2). Not re-checked: builds 137 to 140.

## Could not verify

- F3 (input isolation), as above.
- That the pinned host key is the git host's current key: a mismatch fails the pick loudly, it does not fail open (StrictHostKeyChecking=yes); not compared by me.
- The platform side: that it keeps one check run per commit and never reopens a verdict on a `start`. Read from the script's contract and the build logs only.

## Did not examine

- binnacle's half, and its `Concourse / binnacle` check (required on its `main`).
- The platform's check-run poster and its GitHub App credential handling (another repository).
- Part A beyond re-checking its key claims; Part C (not AI-relevant).

## To pass

1. F1: move or clear the markers and add the negative-case test (a tree that carries the marker is judged, and fails or passes on its suites).
2. F2: add the moved-head test.
3. F3: one recorded run on a worker showing a task's write to `repo/` is not seen by the hook.
4. F4: add the boundary to `.sdlc/threat-model.yaml` and correct the `github-repository` description; bring the bot-branch exposure to the operator as a risk decision.

## What I ran

1. Fresh clone; a worktree at main 7d4c7fb and a scratch worktree for the two mutations. Nothing was merged or rebased, and nothing from the scratch worktrees was committed.
2. The two tests above; a scratch driver (not committed) that reuses the test's own local-origin harness for the classes in the item 15 table, then runs the real pr-checks.sh and check-run.sh on what the pick produced.
3. Concourse anonymous API: job list, build resources and event streams for the builds named above, and for `pr-checks` builds 86 and 249.
4. `gh api` reads: the repository's merge settings, `main`'s protection, the check runs on pull requests #181 and #187, and the three alert lists.
