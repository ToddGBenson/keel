# Change record — keel v0.1.0 (G5)

Produced by:   builder agent for the PO, per `.claude/commands/release.md`
Model version: claude-opus-5-5
Date:          2026-11-22 (Arizona and UTC). First written 2026-11-17 against `c7ba09e`,
               re-measured 2026-11-18 against `7d4c7fb`, 2026-11-22 04:15–04:45 UTC against `4c19aca`
               (after the review of `28a642c2` blocked it as stale), and 2026-11-22 from 16:30 UTC
               against `0f83e14` (this revision, after #212 merged)
Approved by:   <operator, at the `production` environment approval of the release run>
Issue:         TheHub #61006 · POAM-011

`verdict: <pending — the operator's G5 decision, not this record's>`

This record is the CM-3 artifact for keel's first release. It is written before the tag so the
record the approver reads is the one in the tagged tree (`release.yml` preflight). It does not
claim the release is ready: section 4 shows a G5 checklist item that fails as written, and the
approver decides on that basis. It carries no `release-run:` or `attestation:` line yet;
`/release` step 5 appends one after the run, citing only a run that has been opened.

Every number below was measured on `main` at `0f83e14e7f502a74d642f2d2c1e7114be29cadf7` unless
it names another sha. `0f83e14` is `4c19aca` plus #212, which changes three files: `.claude/hooks/guard-bash.sh`,
`.claude/hooks/selftest.sh` and `test/hook-bypass-corpus.test.py`. Concourse build numbers are pipeline `keel`, team `main`, and each one is
cited only for a build whose `repo` input is the sha given beside it.

## Risks and residual exposure — read first

1. **G4 is not cleared for the items in this release.** #188 merged as `4c19aca`: the first G4 records, for three stories, each with a QA
   (Part A) and a Security (Part B) record. `scripts/control-liveness.py` on `0f83e14` reports
   G4 Verified = **3** (Concourse `platform-integrity` build 189 on `0f83e14`, the same as build 187 on `4c19aca` and as run locally; G3: 50, G1: 1, G0/G2/G5: 0). The verdicts, as recorded (QA taken at `c7ba09e`,
   Security at `7d4c7fb`):
   - **61237** (#182, a missing gitleaks report fails): QA `pass`, Security `pass` (one Low
     outside the story's criteria: the scanner's exit status is not read).
   - **61778** (#178, Concourse judges PR heads): QA **`fail`**, Security **`fail`**.
   - **61794** (#179, guard-bash.sh fails closed): QA **`fail`**, Security **`fail`**.

   **What those findings are on `0f83e14`.** The records are point-in-time and their verdicts
   stand. Some findings they state have had fixes merged since. A fix is a new item that needs
   its own G4 record; none of these fixes has one, so none is G4-cleared.
   - 61778 Security F1 (a PR could get a green `Concourse / keel` with no suite run), F2 (no
     negative test for the moved-head refusal) and F4 (threat model not updated): **fix merged**,
     #208 (TheHub #62015, `3446761`): the picker's state moved out of the PR tree, the moved-head
     refusal is tested, `.sdlc/threat-model.yaml` gains `pr-code-on-workers`. F3 (token
     isolation from PR code assumed, not tested): #208's message says the trusted checkout is
     tested; **not re-verified here.**
   - 61778 QA AC4 (the check's link goes to a repository, not to the build): **still open.**
     On `4c19aca` and on `0f83e14` the `Concourse / keel` check run's `details_url` is a
     repository URL (measured 2026-11-22 04:20 and 16:50 UTC); #212 does not touch `ci/`. AC3 as written for keel: still not met as written.
   - 61794 Security F1 / QA AC3 parse-error half (the no-jq fallback allowed a payload it could
     not read): **fix merged**, #205 (TheHub #61978/#62016, `6c7af3b`). Security F2 (a helper
     that answers wrongly is believed): **fix merged**, #189 (TheHub #61843, `b587289`), helpers
     resolved only from system directories. F3 (Windows time margin): #205 (TheHub #61973) adds
     a 40 s supervisor deadline; not re-measured on Windows here.
   - 61794 QA AC2/AC5 (no regression test runs the no-jq fallback N ≥ 50 times): **still
     open**; no repeat-count test exists on `0f83e14` (#212 changes how the corpus runner
     prints and times its two modes, not how often it runs the fallback).

   That leaves 127 of the 130 PR-numbered commits with no G4 record, and two of the three that
   have one recorded a **fail**. G5 checklist item 2 says anything without G4 clearance is
   removed from the release, not waived. keel's release is the whole tree, so it cannot drop
   one item, and applying the rule literally removes everything. Releasing the un-cleared
   items, 61778 and 61794 included, is the operator's explicit call, not a waiver this record
   can grant (POAM-018). QA holds a veto at this review (`docs/07-release-and-change.md`), and
   has recorded two fails.
2. **Two POA&M items are overdue; four Highs were re-dated, not closed.** `scripts/poam.py
   --check --history --today 2026-11-22` on `0f83e14`: exit 0; POAM-011 (Medium) and POAM-013
   (Low), both due 2026-11-11, are **11 days past due** on 2026-11-22 (Arizona and UTC).
   Concourse `platform-integrity` build 189 on `0f83e14` prints the same "11 days" for both, and "ok: no open High/Critical POA&M item is past due". The check gates only High/Critical items, and the
   release preflight does not run it. POAM-017 and POAM-018 were re-dated to 2026-12-17 by #185
   (operator decision 2026-11-17); POAM-010 and POAM-014 were re-dated from 2026-11-21 to
   **2026-12-17** by #205 (operator decision 2026-11-18), each its second extension.
3. **Rollback is not rehearsed.** There is no rehearsal record (section 10).
4. **AI evals are unsatisfied** (section 6). `agent-assurance`'s replay step is an `ADAPT:`
   stub. Its last build, 16, ran on `c7ba09e` (2026-11-17), not on `0f83e14`, and printed
   "OVERDUE since 2026-11-12: the behavioral half of AIC-12 is not operating".
5. **Solo operation (POAM-008).** The one `production` reviewer (`ToddGBenson`) is also the
   dispatcher, and holds the repository admin role, which is the `keel-release-tags` ruleset's
   only bypass for creating a `v*` tag (a role, not a named identity: it is one person only
   while the repository has one admin). `authorize-release` will print the AC-5 warning. Recorded, not refused.
6. **Signature verification is not enforced where forks receive keel.**
   `scripts/sync-platform.sh` syncs from `upstream/main`, not from a tag, and does not call the
   verifier. Only Concourse `verify-artifact` verifies keel's own latest release. The tag
   therefore changes nothing a fork receives; it adds a signed, attested point.
7. **The guard hooks are best-effort guidance, by keel's own statement** (#191, TheHub #62000,
   `docs/11-ai-agent-controls.md`), until the allowlist rebuild. Eight of the fifteen commits
   added since `7d4c7fb` change `.claude/hooks/` (#189, #195, #205, #207, #192, #210, #211,
   #212).
8. **No previous release, so no SBOM diff** (section 8).

## Identifier and scope

- **Version:** `v0.1.0` — the first tag and first GitHub release of ToddGBenson/keel
  (measured 2026-11-22 16:40 UTC: `gh api repos/ToddGBenson/keel/tags` and `/releases` both empty;
  `verify-artifact` build 80 on `4c19aca`: "no release yet (HTTP 404)").
- **Commit range:** `3f92a21a0e4fc1b8f86ed571582f88bf07ab083d` (root, 2026-08-07,
  "feat: keel — a governed SDLC base repo") through
  `0f83e14e7f502a74d642f2d2c1e7114be29cadf7` (main, 2026-11-22, #212). **145 commits**
  (`git rev-list --count 0f83e14e`), 297 files changed, +37,619 / −1,139
  (`git diff --shortstat 3f92a21 0f83e14e`). The 2026-11-18 revision covered the 130 commits
  through `7d4c7fb`; the 15 since are #193, #191, #204, #189, #195, #205, #207, #208, #192,
  #209, #210, #211, #206, #188 and #212, in merge order.
- **The commit tagged** is the squash-merge of the PR that adds this record. Its sha does not
  exist until merge: `<merge commit of this PR>`. The appendix ends at `0f83e14`, and #188
  and #212 are already in it. The only commit after it in the tagged tree is this PR's own
  squash-merge, so the tagged tree is `0f83e14`'s tree plus this one file. The tag goes on
  that squash-merge commit, not on whatever `main`'s tip is when the tag is pushed. If anything else lands on `main`
  before this PR merges, the appendix is out of date and this record must be refreshed before
  the tag.
- **Items:** 130 commits carry a PR number; 15 commits (2026-08-07 to 2026-08-08, before
  branch protection) were pushed to main without a PR. 14 of the 145 are dependency bumps.
  The full list is the appendix, generated by `git log --reverse 0f83e14e`. Nothing outside it
  is included.
- **What a keel release is:** a tag. keel ships no artifact or service (ADR-0004). The release
  signs a manifest of the platform-owned files; `build-and-attest` build 85 on `0f83e14` measured **164 platform-owned files**.

## Change class

**Normal.** A first release of the whole tree is not pre-authorized, low-risk or repeatable.
It is not an Emergency. It is release evidence and is **not** low-risk; a human authorizes it.

## Impact analysis (CM-4)

- **Components:** everything platform-owned per the manifest (agents, commands, skills, hooks,
  gate definitions, platform docs, scripts, the Concourse pipeline forks inherit) plus
  project-owned files that the manifest does not deliver.
- **Interfaces:** the platform contract forks consume — `scripts/sync-platform.sh`, the
  manifest, `ci/` pipeline and vars, `.claude/` definitions, and the release verifier
  `scripts/platform-release.sh`. No interface changes *relative to a previous release*,
  because there is none.
- **Data migrations:** none. keel holds no data.
- **Backward compatibility:** not applicable to a first version. Forks already track
  `upstream/main`, so `v0.1.0` gives them no new content.
- **Downstream consumers:** repositories that run `scripts/sync-platform.sh` against keel.
  binnacle is named as one in G3 records (`evidence/148/g3/self-review.md`,
  `evidence/61360/g3/self-review.md`) and carries paired PRs for most hook changes below.
  GitHub lists no forks of ToddGBenson/keel (`gh api repos/ToddGBenson/keel/forks` is empty,
  2026-11-22 16:40 UTC); a sync-based consumer does not appear there, so the full list is
  **unverified**.
- **Changes since the 2026-11-18 revision (`7d4c7fb..0f83e14`), by what they touch:**
  - **Release path.** #205 (TheHub #61432) gives `scripts/platform-release.sh` a
    per-repository release floor: keel is held to `RELEASE_FLOOR` (`af878f1`), any other
    repository to a reviewed `.github/release-floor` on the trusted ref, a shallow clone is
    refused, and the trusted ref must be a branch, never a tag. #206 (TheHub #62072) adds
    `verify --key` (keyed cosign verification against `.github/cosign.pub` on the trusted ref);
    keyless stays the default and is what `release.yml` and `verify-artifact` run. Neither
    `.github/release-floor` nor `.github/cosign.pub` exists on `0f83e14`; both are now in
    CODEOWNERS. This is the verifier `release.yml`'s sign-and-attest step runs (section 8).
  - **Guard hooks.** `guard-bash.sh`: #189 (helpers from system directories only), #205
    (supervisor deadline and signal handling, TheHub #61973; no-jq parse refusal, #61978/#62016;
    `normalize()` and docker compose/run rules, #61987), #192 (refuses an agent pushing or
    creating a `v*` tag, TheHub #61972), #210 and #211 (follow-ups to #192), #212 (TheHub
    #62258: starts about half as many processes per run, with every verdict unchanged; it
    changes `guard-bash.sh`, `selftest.sh` and `test/hook-bypass-corpus.test.py`. Its PR
    reports the corpus's sorted per-entry verdicts identical in both modes and selftest
    unchanged; measured in Concourse, `test` build 192 on `0f83e14`: selftest **737 passed, 0 failed** (734 on `4c19aca`, build 190), corpus 1162 hook runs, 0 failed). `guard-write.sh`:
    #195 (NotebookEdit and MultiEdit, TheHub #61391), #205 (evidence path in any spelling,
    TheHub #62022), #207 (round-3 nits, TheHub #62037). `.claude/settings.json` changed in #195.
  - **CI.** #204 (`pr-pick` judges the longest-waiting head first), #208 (`pr-checks` cannot
    pass on a head whose tree carries the picker's marker, TheHub #62015), #209 and #210
    (`check-run.sh` retries an unreachable reporter and passes shellcheck), all in
    `ci/scripts/` and `ci/pipeline.yml`.
  - **Docs and records.** #193 (self-review wording), #191 (hooks are best-effort guidance),
    #205 (POA&M, `.sdlc/protection.yaml`, `.sdlc/process.yaml`, control maps), #188 (the six
    G4 records).
- **Security control impact:** SR-4(3)/CM-14 — the first signed and attested release is
  POAM-011's closure evidence, once `verify-artifact` verifies it. CM-3 — the first G5 record
  (POAM-018 counts it only after a `release-run:` line is appended). POAM-010 — the first run
  of `authorize-release` (its stated closure). CM-5/AC-5 — #192 moves the tag push from a
  convention to a hook refusal plus the `keel-release-tags` ruleset.
- **AI system impact:** yes. keel ships agent prompts: 15 agents, 17 commands, 18 skills (`platform-integrity` build 189 on `0f83e14`, "Agent / command / skill definitions"). No model is pinned or
  changed by this release; the prompts are what forks' agents run.

## Gate evidence (G4 clearance per item)

**Unsatisfied on `main`.** Measured, `platform-integrity` build 189 on `0f83e14` (control-liveness; build 187 on `4c19aca` and a local run give the same table):

| Gate | Records on `main` (`0f83e14`) | Ever fired? |
|---|---|---|
| G0 Intake | 0 | never |
| G1 Ready | 1 | yes |
| G2 Designed | 0 | never |
| G3 Code Complete | 50 | yes |
| G4 Verified | 3 (61237 pass/pass, 61778 fail/fail, 61794 fail/fail; QA/Security) | yes |
| G5 Release Authorized | 0 | never |

control-liveness reports **14** control claims that cite a gate that has never fired on `main` (17 before #188 merged; `platform-integrity` build 186 on `6e4a04f`). The G4 detail, and which recorded findings have fixes merged since, is risk 1.

What does exist per item: G3 self-review records under `evidence/<issue>/`, and since
TheHub #61778 (#178) the `Concourse / keel` check on PR heads. `main` requires
`Concourse / keel` and `library-allowlist` (both App-pinned, App 4551328), branches up to date
(`strict: true`), `enforce_admins: true`, linear history, conversation resolution and 0
approving reviews; the `keel-main` ruleset additionally requires a pull request with squash
merges only and `require_extra_approval_for_unattributed_changes: true`, with no bypass
(measured 2026-11-22 16:40 UTC, `gh api
repos/ToddGBenson/keel/branches/main/protection` and `/rulesets`). MyKronos
`independent-review` is **not** required. Since the 2026-11-18 operator decision (#205) it is
no longer POAM-014's closure condition; POAM-014 closes on the required `Concourse / keel`
check plus TheHub #62015 merged, and POAM-017 closes when `main` requires an approval recorded
outside the agents' prompt boundary (the `independent-review` check, or an approving review by
another identity, TheHub #61039). 15 early commits had no PR and no check.

## Security posture

- **GitHub code scanning, open:** 0. **Dependabot, open:** 0. **Secret scanning, open:** 0
  (measured 2026-11-22 16:40 UTC via `gh api`).
- **MyKronos findings register for keel:** not read for this record — **unverified**. The
  MyKronos lanes are listed in section 7; a green lane is not a count of open findings.
- **Open POA&M entries** (`docs/compliance/poam.md` at `0f83e14`, unchanged since `4c19aca`; `scripts/poam.py --list`):

| Entry | Risk | Due | State |
|---|---|---|---|
| POAM-001 agent write-scope prompt-enforced | Low | review quarterly | Open, compensating controls |
| POAM-008 solo operation, AC-5 | **High** | on 2nd team member | Open, accepted |
| POAM-010 G5 authorization has never run | **High** | 2026-12-17 (was 2026-11-21; re-dated by #205, second extension) | In progress — closes when `authorize-release` runs with a recorded approval at v0.1.0, this release |
| POAM-011 no provenance for what forks receive | Medium | 2026-11-11 | **Overdue** (11 days on 2026-11-22) — closes on this release's evidence |
| POAM-013 monthly cadence approximated | Low | 2026-11-11 | **Overdue** (11 days on 2026-11-22) |
| POAM-014 merge gate verifies process, not code | **High** (gated as Critical by `--history`) | 2026-12-17 (was 2026-11-21; re-dated by #205, second extension) | Open in the register. Closure re-scoped by #205 to the required `Concourse / keel` + `library-allowlist` checks with `enforce_admins` true (all live, above) **and** TheHub #62015 merged. #62015 merged as #208 (`3446761`, 2026-11-21), so the stated condition now reads as met; the register has not been updated and this record does not close it |
| POAM-017 separation of duties agent-enforced | **High** | 2026-12-17 (re-dated by #185) | Open, accepted (ADR-0005). Closure restated by #205: an approval recorded outside the agents' prompt boundary on the exact head, required on `main`; not met (0 reviews, `independent-review` not required) |
| POAM-018 controls on gates that never ran | **High** | 2026-12-17 (re-dated by #185) | Open. Its register row still says G3 16 and no G4 record; control-liveness on `0f83e14` counts G3 50 and G4 3 |

- **Measured drift (2026-11-22 16:40 UTC), live against `.sdlc/protection.yaml` and the register:**
  - Branch protection on `main`: `enforce_admins` **true**, required checks `Concourse / keel`
    and `library-allowlist` (App 4551328), `strict` true, 0 approving reviews,
    `dismiss_stale_reviews` true, `required_signatures` **false**, linear history true, force
    pushes and deletions false, conversation resolution true. Every field
    `.sdlc/protection.yaml` declares matches live.
  - Ruleset `keel-main` (27545123, branch `refs/heads/main`, active, no bypass actors):
    deletion, non-fast-forward, pull request (squash only, 0 approvals,
    `require_extra_approval_for_unattributed_changes: true`). It has **no**
    signed-commit rule: that rule was live from about 11:58Z to about 14:36Z on 2026-11-18 and
    was dropped by the operator (TheHub #62001), as POAM-009 and `.sdlc/protection.yaml`'s
    `required_signatures` reason record. **Drift in the declaration's own header:** its comment
    still says "Signed commits are required on main since 2026-11-18 by the keel-main ruleset",
    which is not true live.
  - Ruleset `keel-release-tags` (27545130, tag `refs/tags/v*`, active): creation, update,
    deletion and non-fast-forward are restricted, with one bypass actor, the repository admin
    role (`RepositoryRole`, always). Only a holder of the admin role can create, move or delete
    `v0.1.0`.
  - POAM-009 is closed and records the signing history above as a CIS 1.1.9 deviation, not
    reopened. The last 100 commits on `main` are GitHub-verified (`gh api .../commits`, 0
    unverified), including `0f83e14`.
  - The daily `protection-drift` job does not run: builds 6 (on `6c7af3b`) and 7 (on
    `a2907fb`) **errored**, "undefined vars: github_protection_token". The comparison above
    was made by hand for this record.

## AI assurance

- **Evals vs. baseline:** **unsatisfied.** Concourse `agent-assurance` build 16 succeeded on
  `c7ba09e` (2026-11-17), not on `0f83e14`; the job has not run since. Its replay step prints
  `ADAPT:` and evaluates nothing. Its behavioral section prints "no behavioral run recorded
  yet" and "OVERDUE since 2026-11-12".
- **Red-team status:** no red-team record exists for this range — unsatisfied.
- **Guardrail verification:** Concourse `test` build 192 on `0f83e14` ran the guard-hook corpus and the unit suites: guard selftest **737 passed, 0 failed** (734 in build 190 on `4c19aca`; #212 adds 3); hook bypass corpus 318 entries, 1162 hook runs, 0 failed, 44 open (known gaps); **26 of 27** test files passed, 1 not run there (`test/selfreview-check.test.js`, no node on the worker). That file runs in the Actions `unit-suites` check (section 7).

## Test evidence

Concourse, pipeline `keel` (team `main`). The table lists, per job, a build whose `repo`
input is the sha in its row, measured 2026-11-22 UTC. Where no build on `0f83e14` had finished
at measurement, the row gives the build on `4c19aca`, whose tree differs only by #212's three
files:

| Job | Build | `repo` input | Result |
|---|---|---|---|
| set-pipeline | 98 | `0f83e14` | succeeded |
| lint | 194 | `0f83e14` | succeeded (was **failed**, build 188 on `98a0bbb`) |
| test | 192 | `0f83e14` | succeeded (26 of 27 test files passed, 1 not run; guard selftest 737 passed, 0 failed) |
| build | 190 | `0f83e14` | succeeded |
| sast | 190 | `0f83e14` | succeeded |
| secrets | 188 | `0f83e14` | succeeded |
| sca | 189 | `0f83e14` | succeeded |
| iac | 187 | `0f83e14` | succeeded |
| suppression-audit | 189 | `0f83e14` | succeeded |
| mykronos-secrets | 111 | `0f83e14` | succeeded |
| build-and-attest | 85 | `0f83e14` | succeeded |
| platform-integrity | 189 | `0f83e14` | succeeded |
| mykronos-sast | 108 | `4c19aca` | succeeded (build 109 on `0f83e14` still running when measured (16:55 UTC); row gives `4c19aca`) |
| mykronos-atlas | 111.1 | `4c19aca` | succeeded (no build on `0f83e14` had started when measured) |
| mykronos-sca | 52 | `4c19aca` | succeeded (build 53 on `0f83e14` still running when measured (16:55 UTC); row gives `4c19aca`) |
| verify-artifact | 80 | `4c19aca` | succeeded, advisory: no release to verify (build 81 on `0f83e14` still running when measured (16:55 UTC); row gives `4c19aca`) |

The `Concourse / keel` check run on `0f83e14` was still in progress when measured (16:50 UTC).
On `4c19aca` it completed **success** at 04:34:20 UTC (`gh api .../commits/<sha>/check-runs`).
`main` was red at the review of `28a642c2` (`98a0bbb`: lint build 188 failed); #210 fixed it.

`pr-checks` judges open PR heads on a ten-minute timer; build 696 ran on `4c19aca` (04:32 UTC) and found no head needing a verdict, so it posted nothing. This PR's new head is judged by a later `pr-checks` build.

Not on `0f83e14` or `4c19aca`: `agent-assurance` 16 and `compliance-monthly` 16 (both on `c7ba09e`;
`compliance-monthly` 16 is a scheduling no-op, "MONTHLY BUNDLE NOT DUE", and is not CA-7
evidence), `container-scan` 1 (on `114c621`, 2026-10-12), and `protection-drift` 7
**errored** on `a2907fb` ("undefined vars: github_protection_token", as build 6 did on
`6c7af3b`).

GitHub Actions run ids are not cited as evidence in this record: Actions has been unreliable on
this account at times. It is running jobs on this repository now: on `4c19aca` and on
`0f83e14`, the Actions checks `unit-suites` (which runs `test/selfreview-check.test.js`),
CodeQL, Checkov, Gitleaks and Supply chain completed success (check runs read 2026-11-22
16:40 UTC). The release itself runs on Actions (deployment plan).

**Staging, DAST, performance vs. NFR:** not applicable — keel has no service or environment
to stage, scan or load (ADR-0004). Stated, not passed.

## Supply chain

- **SBOM:** `build-and-attest` build 85 on `0f83e14` generated an SBOM of **58 components**. **No diff:** there is no previous release, and that job's diff step is
  an `ADAPT:` stub.
- **Signature and provenance:** not produced yet — `release.yml` `sign-and-attest` produces
  them after authorization: keyless `cosign sign-blob` of `platform-manifest.txt` (cosign
  3.1.3, sha256-pinned), SLSA provenance via `actions/attest-build-provenance`, and the
  verifier `scripts/platform-release.sh verify --trusted-ref origin/main` run positive plus
  three refusals before `gh release create`. Until then:
  `<attestation URL, appended after the run>`.
- **The verifier changed since the previous revision.** #205 (TheHub #61432): the tag's commit
  must descend from keel's `RELEASE_FLOOR` (`af878f1`, "fix(release): close
  POAM-010/014/016…", #143); a shallow clone is refused; the trusted ref is looked up only
  among branches, so a tag cannot stand in for `origin/main`. `release.yml` checks out with
  `fetch-depth: 0` and passes `--trusted-ref origin/main`, and the release commit will
  descend from `af878f1`, so none of these refuses v0.1.0 as planned. #206 (TheHub #62072):
  `verify --key` exists but is not used by `release.yml` or `verify-artifact`, and there is no
  `.github/cosign.pub` on `0f83e14`; the release is keyless. `test/platform-release.test.py`
  covers both changes (`test` build 192 on `0f83e14`: `test/platform-release.test.py` all passed, including the `verify --key` and release-floor cases). No real cosign signature has been verified by either
  change (their self-reviews say the test stubs cosign).

## Deployment plan

1. #188 (`4c19aca`) and #212 (`0f83e14`) are already merged. Merge this PR (squash; the repository allows squash
   merges only). `main` requires a branch to be up to date (`strict: true`) and a green
   `Concourse / keel` and `library-allowlist` on its head. If anything merges first, this
   branch must be updated again, which moves its head and makes this record stale (section 2).
   Approve this PR at the head that results, not before. Its squash-merge commit is the
   release commit.
2. **The operator** creates and pushes tag `v0.1.0` on this PR's squash-merge commit, not on
   whatever `main`'s tip is by then. An agent cannot:
   `guard-bash.sh` refuses an agent pushing or creating a `v*` tag (#192, TheHub #61972), and
   names this path: "Push your branch and open a PR; after merge the operator creates the tag
   and dispatches release.yml." The `keel-release-tags` ruleset also lets only the repository admin role
   create a `v*` tag. POAM-010 records this as the operator's Keel-Rulesets-Release step 4.
   The preflight refuses a commit not on `origin/main`.
3. The operator: Actions → Release → Run workflow with the **tag** as the ref.
4. `preflight`: tag check, on-main check, `validate-manifest.py`, `validate-platform.py`,
   `validate-pipeline.py`, this record's 13 sections.
5. `authorize-release` waits for a `production` reviewer (measured 2026-11-22 16:40 UTC:
   `required_reviewers` `ToddGBenson`; custom deployment policies, branch `main` and tag `v*`).
6. `sign-and-attest` signs, attests, verifies (with #205's floor and trusted-ref checks) and
   publishes the release with `platform-manifest.txt` and `platform-manifest.sigstore.json`.

Timing: when the operator is available to approve and to watch step 6. All three jobs are
GitHub Actions jobs. Actions is running jobs on this repository today (section 7), so it does
not block the release now; if Actions does not start them at dispatch, the release waits for
it. No feature flags. Before step 3: Release run **31770313398**
(dispatched from `main`, 2026-08-14) is still `queued` (measured 2026-11-22 16:40 UTC); if it
starts it fails at the tag check. Cancelling it is the operator's call.

## Rollback plan

- **Trigger:** `sign-and-attest` fails after publishing, `verify-artifact` fails on the new
  release, or the manifest or signature is found wrong.
- **Path:** the operator deletes the GitHub release and the `v0.1.0` tag (the
  `keel-release-tags` ruleset restricts tag deletion to the admin role, and `guard-bash.sh`
  refuses an agent's tag writes), or publishes `v0.1.1` from a fixed commit. Content needs no
  rollback: forks sync from `upstream/main`, not from the tag, so the tag changes no fork. A
  defect in `main` itself is reverted on `main`, which is the existing path for every merged
  PR.
- **Data path:** none. keel holds no data.
- **Window:** none set by this record.
- **Rehearsal evidence:** **unsatisfied — no rehearsal performed.** One consequence the
  verifier's own advisory states: once a release exists, an unsigned or unverifiable *latest*
  release fails `verify-artifact`, so deleting the release returns it to advisory.

## Verification plan

After the run, by the operator or an agent on the operator's instruction:

1. Open the run; confirm all three jobs succeeded and the summary names the approver.
2. `gh release view v0.1.0 -R ToddGBenson/keel` lists both assets.
3. `gh attestation verify platform-manifest.txt --repo ToddGBenson/keel --signer-workflow
   ToddGBenson/keel/.github/workflows/release.yml`.
4. Concourse `verify-artifact` verifies the release, not the advisory.
5. Append the `release-run:` URL here (append, never rewrite), then close POAM-011 on that
   evidence and record POAM-010's first run.

## Communication

- This PR and TheHub #61006 carry the record and the decision.
- After the release: the release notes on the GitHub release (written by `release.yml`), and
  a TheHub update on #61006 with the run URL.
- Forks: no notice is required for content (they track `main`). Telling fork owners that a
  signed release exists is not planned in this record.

## Authorization

**Pending — to be completed by the human approver at G5.** Approval is the `production`
environment approval on the release run; `authorize-release` records it.

| | |
|---|---|
| Approver | `<operator — production environment reviewer>` |
| Approved at | `<timestamp from the run's approval record>` |
| Approval link | `<https://github.com/ToddGBenson/keel/actions/runs/<id>>` |
| Decision on risk 1 (G4 not cleared; 61778 and 61794 recorded fail) | `<operator>` |

No agent authorizes this release.

## Appendix — every commit in scope (`git log --reverse 0f83e14e`)

| Commit | Date | Subject |
|---|---|---|
| `3f92a21` | 2026-08-07 | feat: keel — a governed SDLC base repo |
| `41ab8fa` | 2026-08-07 | chore(compliance): post-publication hardening and honest ledger update |
| `79f6819` | 2026-08-07 | fix(scripts): nine defects found on first end-to-end run of bootstrap and sync |
| `738fdfd` | 2026-08-07 | feat(dx): the efficiency layer — keel dispatcher, fast lane, runnable AIC-12 |
| `a0dd620` | 2026-08-07 | fix(keel): fast lane operates on staged changes only; fix reason display |
| `cf6bbc8` | 2026-08-07 | docs(evidence): self-review for the efficiency layer (POAM-008) |
| `42b1552` | 2026-08-08 | refactor(docs): consolidate phase docs — 50% off, zero controls lost |
| `d187f78` | 2026-08-08 | fix(ci): exempt bot dependency PRs from human governance; ignore action majors |
| `f5c92ad` | 2026-08-08 | chore(deps): bump the actions-minor-patch group across 1 directory with 3 updates |
| `66334ca` | 2026-08-08 | chore(deps): bump the actions-minor-patch group across 1 directory with 16 updates |
| `dde1e84` | 2026-08-08 | feat(intake): artifact intake — specs, wireframes, mockups, schemas |
| `0b1b2f4` | 2026-08-08 | docs(lessons): L0012 — a spec is silent about the parts that break |
| `f8effed` | 2026-08-08 | feat(dash): visual dashboard for backlog, CI health, and controls |
| `ccdfdb5` | 2026-08-08 | fix(dash): declare truncation; test volume, degraded, and escaping paths |
| `6496a98` | 2026-08-08 | fix(dash): strip markdown from POA&M fields |
| `1a1185c` | 2026-08-08 | fix(setup): idempotent configure-github; close POAM-009 (signing live) (#22) |
| `0b675d6` | 2026-08-08 | docs: record squash-only merge strategy after enabling signed commits (#23) |
| `a64ef40` | 2026-08-09 | feat(sprint): describe an idea, get a tested PR — with the first use case (#24) |
| `8d4ad61` | 2026-08-09 | revert: sprint automation and dailycheck (#24) (#25) |
| `c7a51ec` | 2026-08-09 | feat(sprint): restore the sprint runner, without the daily-checks example (#26) |
| `e6285ed` | 2026-08-10 | chore(deps): bump the actions-minor-patch group with 3 updates (#27) |
| `1040be4` | 2026-08-10 | feat(sprint): agree and enforce the parameters for automated runs (#29) |
| `e1e0e9e` | 2026-08-10 | sec(workflows): enable Mykronos scanning, pinned to full SHAs (#28) |
| `73dae62` | 2026-08-10 | sec(scanning): allowlist the guard self-test fixture, and prove the scanner still works (#33) |
| `769645e` | 2026-08-10 | feat(process): group work into epics and verify per epic, not per story (#36) |
| `ae56e63` | 2026-08-11 | sec(workflows): Mykronos resync — blocked on upstream pin (mykronos#7) (#40) |
| `f9ebe39` | 2026-08-11 | Mykronos: update atlas, sast, secrets (#41) |
| `e31e701` | 2026-08-13 | ci(pipeline): port CI/CD from GitHub Actions to Concourse (#43) |
| `092e3bd` | 2026-08-13 | fix(governance): require a self-review record, not a heading (#46) |
| `efbaeaf` | 2026-08-13 | fix(ci): syft lives at /syft, not on PATH (#49) |
| `963b30c` | 2026-08-13 | ci: let the pipeline update itself from main (#51) |
| `ed629e5` | 2026-08-13 | chore(mykronos): resync workflow templates (#45) |
| `de12337` | 2026-08-14 | ci: finish the move to Concourse — SAST gate, release lane, deploy key, groups (#53) |
| `d35a85d` | 2026-08-14 | Fix/55 atlas GitHub release blocker (#54) |
| `72909e5` | 2026-08-14 | sec(compliance): POA&M review — every row measured, nothing closed (#55) |
| `3b44cf6` | 2026-08-14 | chore: govern keel as a template, not as a deployable service (#57) |
| `4a3e4b6` | 2026-08-14 | ci: restore the merge gate on a self-hosted runner (#59) |
| `ef3b0d9` | 2026-08-14 | docs(compliance): close POAM-005/006 after going public, refuse to close POAM-010 (#62) |
| `344e598` | 2026-08-14 | docs: retire the self-hosted runner, and record why it failed (#64) |
| `b2b66e9` | 2026-08-14 | feat(process): adopt the agentic-SDLC spec — UX, RACI, dev pool, and agent gate authority (#66) |
| `87529ce` | 2026-08-14 | sec(compliance): land the control-liveness work that a squash merge stranded (#69) |
| `2d8a22f` | 2026-08-15 | fix(bootstrap): a new fork must not inherit keel's evidence (#71) |
| `fe10642` | 2026-08-15 | fix(sync): stop sync-platform.sh hanging, and prove the ownership contract (#73) |
| `1bb585b` | 2026-08-29 | chore(mykronos): resync workflow templates (#75) |
| `354c16b` | 2026-09-02 | chore(deps): bump the actions-minor-patch group across 1 directory with 6 updates (#76) |
| `b864786` | 2026-09-04 | Mykronos: enable iac; update atlas, sast (#77) |
| `0f14d71` | 2026-09-04 | Mykronos: enable oracle (#78) |
| `6b1eff0` | 2026-09-07 | chore(deps): bump the actions-minor-patch group with 4 updates (#81) |
| `7009700` | 2026-09-11 | fix(release): pass workflow_dispatch inputs as data, not as program text (#84) |
| `e7a6b52` | 2026-09-12 | fix(keel): a failed cd must not leave every check running against the wrong tree (#85) |
| `ce3df6e` | 2026-09-12 | docs(ci): the Mykronos ingestion group is not paused and has a token (#86) |
| `e49ed58` | 2026-09-14 | Mykronos: update atlas, iac, sast, secrets (#88) |
| `e244426` | 2026-09-14 | chore(deps): bump the actions-minor-patch group with 5 updates (#87) |
| `f8fe096` | 2026-09-17 | fix(ci): pin and hash the one Python dependency CI installs (#90) |
| `66b8d90` | 2026-09-17 | sec(deps): a version update waits seven days, a security update does not (mykronos#270) (#91) |
| `6f6210b` | 2026-09-17 | chore(deps): bump the actions-minor-patch group with 3 updates (#92) |
| `7e660b7` | 2026-09-18 | fix(guard): gh api reached every endpoint the blocked subcommands do (#89) (#93) |
| `a27c38f` | 2026-09-18 | harden(release): the version comes from the ref, not from a text box (#79) (#94) |
| `06566d1` | 2026-09-24 | fix(ci): the iac lane reached nothing, and ten jobs started in the same second (#96) |
| `56b67f7` | 2026-09-24 | fix(iac): the presence test declared "nothing to scan" over an open HIGH finding (#97) |
| `29c8bb4` | 2026-09-28 | chore(deps): bump the actions-minor-patch group with 5 updates (#98) |
| `3d1169a` | 2026-10-01 | fix(iac): CKV_GHA_7 on change_record is skipped as the accepted risk it is (#99) (#100) |
| `5f23aa8` | 2026-10-08 | chore(deps): bump the actions-minor-patch group with 5 updates (#101) |
| `b354672` | 2026-10-10 | feat/60013 59989 60071 keel coverage (#102) |
| `c32f73f` | 2026-10-10 | docs(process): declare keel's process in .sdlc/process.yaml (#104) |
| `9296113` | 2026-10-11 | feat(ci): upload ShellCheck results to MyKronos as sast from lint (#106) |
| `a7fd845` | 2026-10-11 | feat(ci): post the commit chain's verdict as the Concourse / keel check run (#108) |
| `114c621` | 2026-10-11 | docs(process): read keel's backlog from its GitHub issues (#110) |
| `1be9fe3` | 2026-10-11 | fix(ci): run release preflight from repo/ and validate script paths (#112) |
| `acd3ce6` | 2026-10-13 | fix(ci): suppression-audit failed on the gate test's own docstring (#113) |
| `ae4893f` | 2026-10-14 | chore(deps): bump the actions-minor-patch group with 2 updates (#114) |
| `64565ff` | 2026-10-14 | fix(guard): gh api with a body and no method is a POST (#115) (#116) |
| `0fdb463` | 2026-10-15 | fix(guard): a command inside $(...), backticks or sh -c no longer skips every rule (#119) |
| `a1be9b1` | 2026-10-15 | ci(unit): upload the repository's own test results to MyKronos (#121) (#122) |
| `b1686cc` | 2026-10-15 | fix(guard): a force flag straight after push is blocked (#120) (#123) |
| `76a1269` | 2026-10-15 | fix(guard): GraphQL mutations that merge, review or loosen protection are blocked (#118) (#126) |
| `d382c69` | 2026-10-15 | fix(unit): XML-illegal characters via a translate table, not a regex range (#124) (#125) |
| `9b33c80` | 2026-10-15 | fix(guard): a commit to main through the API is blocked (#127) (#128) |
| `90bdec1` | 2026-10-15 | fix(ci): the Mykronos preflight retries a timeout, never a 401 (#129) (#130) |
| `38552f5` | 2026-10-17 | docs(plan): rank defects on recorded severity, never a back-filled RICE (#131) |
| `cfb9ab3` | 2026-10-17 | fix(shell): clear the 44 ShellCheck style findings Mykronos holds open (#132) |
| `e8cc520` | 2026-10-17 | feat(ci): a mykronos-sca lane uploads grype results as atlas/grype (#133) (#134) |
| `1afb85f` | 2026-10-18 | sec(sdlc): declare keel's threat model in .sdlc/threat-model.yaml (#136) |
| `6c415b0` | 2026-10-19 | chore(deps): bump the actions-minor-patch group with 5 updates (#137) |
| `47fc9c7` | 2026-10-20 | fix(ci): move mykronos_ref to v15 so mykronos-sca's grype results ingest (#138) |
| `d5db77b` | 2026-10-20 | fix(shell): bootstrap.sh SC2015, the one finding ShellCheck <0.11 still reports (#139) |
| `0e1dff6` | 2026-10-21 | fix(ci): delete the ADAPT stub lanes from keel's own pipeline (TheHub #60850) (#140) |
| `38fdd5d` | 2026-10-21 | docs(ci): the Concourse check run is the merge gate; retire PR Governance (TheHub #60849) (#141) |
| `ef253f1` | 2026-10-22 | test(hooks): a shared bypass corpus fails CI on any known bypass (TheHub #60818) (#142) |
| `af878f1` | 2026-10-22 | fix(release): close POAM-010/014/016 and fail sca/container-scan on empty input (TheHub #60935) (#143) |
| `df4c1c1` | 2026-10-26 | feat(supply-chain): sign and attest the platform release; verify-artifact refuses an unsigned one (TheHub #60936) (#145) |
| `d8b25c7` | 2026-10-26 | feat(poam): POA&M due dates enforced in keel status, the session brief and platform-integrity (TheHub #60977) (#146) |
| `28e00e4` | 2026-10-26 | feat(ci): test/manifest.txt is the one list of tests; ./keel check runs all of it (TheHub #60980) (#147) |
| `1d73f21` | 2026-10-26 | chore(deps): bump the actions-minor-patch group with 5 updates (#149) |
| `c23faad` | 2026-10-26 | feat(gates): every gate command writes an evidence record control-liveness can count, so G0, G1 and G5 can register (TheHub #60981) (#148) |
| `290940a` | 2026-10-27 | fix(ci): list #145/#146/#148's test files in test/manifest.txt; ci-stage.sh names none (#151) |
| `74f20a0` | 2026-10-27 | fix(liveness): legacy G3 keys in a project-owned file, G5 cites a release run or attestation, POAM-018 states its baseline (keel #148 review, TheHub #60981) (#154) |
| `36445e5` | 2026-10-27 | fix(guard): agents never approve an environment deployment (TheHub #61038) (#150) |
| `4fc3884` | 2026-10-27 | fix(ci): list the six tests merged outside test/manifest.txt; main's lint stage is red (keel #147 rework) (#152) |
| `de7e36b` | 2026-10-27 | fix(poam): empty register is 0 open, poam.md's status vocabulary, Risk downgrade cannot dodge --check (keel #146 review, TheHub #60977) (#153) |
| `aa6261f` | 2026-10-29 | fix(test): list test/poam-wiring.test.py in the manifest, so lint is green again (#153) (#155) |
| `e35ca5b` | 2026-10-29 | fix(concourse): keel runs at most 3 heavy jobs at once and its tasks yield CPU (TheHub #61062, D-172, D-174) (#156) |
| `9699ecb` | 2026-10-30 | fix(test): the poam gh stub is owner-only, so CodeQL stops failing sast (TheHub #61097) (#157) |
| `8659518` | 2026-11-03 | fix(gitleaks): keel check's allowlist step works in a copy with no .git, so Unit results is green (TheHub #61098) (#158) |
| `5b5754a` | 2026-11-03 | fix(concourse): keel's CodeQL is held to --ram=1024 --threads=2, and every task step times out within 3h, every get within 15m (TheHub #61062, #61238) (#159) |
| `93e054f` | 2026-11-03 | chore(deps): bump the actions-minor-patch group with 5 updates (#160) |
| `e691751` | 2026-11-05 | fix(atlas): no osv.json posts an empty ecosystems list, and the OSV download retries (#167) (#168) |
| `5bf16e1` | 2026-11-05 | fix(sast): run CodeQL one language at a time and pass the 2048 MB it really uses (#169) (#170) |
| `ca6c0ee` | 2026-11-13 | docs(aic-12): the behavioral agent-eval record exists and says no run has been recorded yet (TheHub #61208) (#161) |
| `2bee373` | 2026-11-14 | fix(workflows): MyKronos pins move from v8 to v17 so atlas findings carry #1036's fixed versions (TheHub #61212) (#162) |
| `a59c75c` | 2026-11-14 | feat(configure-github): keel's merge gate is MyKronos independent-review, App-pinned (TheHub #60978) (#163) |
| `1f471f7` | 2026-11-14 | feat(protection): live branch protection is compared daily with .sdlc/protection.yaml (TheHub #60979) (#164) |
| `5502cc1` | 2026-11-14 | fix(hooks): curl is refused on every endpoint the gh api rules guard (TheHub #61048) (#165) |
| `71850a7` | 2026-11-14 | fix(hooks): the guard runs for the PowerShell tool and reads PowerShell (TheHub #61064) (#166) |
| `2a63c69` | 2026-11-15 | fix(test): the manifest lists the four test files #162-#164 added (#172) |
| `bce7caf` | 2026-11-15 | fix(hooks): the curl loop decides on http_write and reads the whole command (TheHub #61064) (#173) |
| `54db881` | 2026-11-15 | chore(deps): bump bridgecrewio/checkov-action (#171) |
| `7b58c21` | 2026-11-15 | fix(ci): the protection-drift job declares timeouts, so main's unit suites go green (TheHub #61729) (#175) |
| `a5466d1` | 2026-11-15 | docs(ci): ci/README.md says keel is public and Actions runs (TheHub #61741) (#174) |
| `279f331` | 2026-11-15 | fix(ci): ci/vars.example.yml pins MyKronos v17 like every workflow, and the pins test reads it (TheHub #61359) (#177) |
| `0e0b293` | 2026-11-15 | ci(unit): the unit check is named unit-suites, plain ASCII, before anything requires it (TheHub #61737) (#176) |
| `3373c61` | 2026-11-15 | feat(ci): Concourse judges pull request heads and posts Concourse / keel on them (TheHub #61778) (#178) |
| `af0607e` | 2026-11-15 | fix(hooks): guard-bash.sh fails closed when one of its own helpers fails (TheHub #61794) (#179) |
| `4b20f55` | 2026-11-15 | ci: every resource, get, put and task runs on a linux-tagged worker (TheHub #61830) (#180) |
| `9d9b5fb` | 2026-11-16 | fix(gitleaks): a missing report fails instead of reading clean (TheHub #61237) (#182) |
| `c7ba09e` | 2026-11-16 | docs(self-review): the building agent writes the record; the operator does not run /self-review (TheHub #61360) (#183) |
| `8338954` | 2026-11-17 | docs(poam): re-date POAM-017 and POAM-018 to 2026-12-17 with closure conditions (TheHub #61773) (#185) |
| `9dcbdfc` | 2026-11-17 | fix(hooks): guard-bash.sh decides a large command in linear time (TheHub #61939) (#184) |
| `5ee24ea` | 2026-11-17 | fix(hooks): guard-write.sh fails closed when a helper fails, and reads large content whole (TheHub #61844) (#186) |
| `7d4c7fb` | 2026-11-17 | feat(hooks): guard-bash.sh refuses a test suite run inside a production container (TheHub #61385) (#190) |
| `3e12e04` | 2026-11-17 | docs(self-review): tell the building agent to run /self-review, stop calling the record CI-required (TheHub #61968) (#193) |
| `bd2ef2f` | 2026-11-17 | docs(agent-controls): the hooks are best-effort guidance until the allowlist rebuild (TheHub #62000) (#191) |
| `1e9f1d9` | 2026-11-18 | fix(ci): pr-pick judges the head that has waited longest first, not the newest PR (TheHub #62064) (#204) |
| `b587289` | 2026-11-18 | fix(hooks): guard-bash.sh finds its helpers only in system directories (TheHub #61843) (#189) |
| `6e14459` | 2026-11-18 | fix(hooks): guard-write.sh guards every write tool, NotebookEdit and MultiEdit too (TheHub #61391) (#195) |
| `6c7af3b` | 2026-11-19 | train(hooks): 2026-11-18 combined hook train (61973, 62031, 62022, 61978, 61987, 61432, 62000, 62001, POAM-010/014) (#205) |
| `a2907fb` | 2026-11-21 | fix(hooks): guard-write.sh round-3 nits: the kept segment's trailing dot, .. pops the cut reading, no raw control characters (TheHub #62037) (#207) |
| `3446761` | 2026-11-21 | fix(ci): pr-checks cannot pass without running on a head whose tree carries .none (TheHub #62015) (#208) |
| `62f0c73` | 2026-11-21 | feat(hooks): guard-bash.sh refuses an agent pushing a release tag (TheHub #61972) (#192) |
| `98a0bbb` | 2026-11-21 | fix(ci): an unreachable check-run reporter retries and never turns a passing suite red (TheHub #62097) (#209) |
| `f0fd92e` | 2026-11-21 | fix(ci): main is green again: check-run.sh passes shellcheck, a branch push with -o is allowed (TheHub #62097, #61972) (#210) |
| `162ccda` | 2026-11-21 | fix(hooks): ctr_guard sanitises marks before tokenizing (TheHub #61972) (#211) |
| `6e4a04f` | 2026-11-21 | feat(release): platform-release.sh verify --key, keyed cosign verification against the trusted ref's public key (TheHub #62072) (#206) |
| `4c19aca` | 2026-11-21 | evidence(g4): first G4 verification record (TheHub #61006, POAM-018) (#188) |
| `0f83e14` | 2026-11-22 | perf(hooks): guard-bash.sh starts half as many processes, with every verdict unchanged (TheHub #62258) (#212) |
