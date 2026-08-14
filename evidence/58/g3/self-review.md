# Self-review — #58

Mode: solo (POAM-008)
PR: #59   Author: Todd Benson (claude-opus-5, AI-authored)   Date: 2026-08-14

Restoring the merge gate on a self-hosted Actions runner, after the hosted ones stopped
starting jobs at all.

## Verified independently

- **The premise was tested before anything was built on it.** "Self-hosted runners are free,
  so they will run under the billing block" is a claim about GitHub's billing internals that I
  could not verify by reading. Run **31828759203** executed to success on `keel-local` while
  hosted jobs were refusing in about three seconds. The smoke workflow existed only to answer
  that and is deleted in the same commit.
- **The gate blocked this PR, and blocked it for the right reason.** First run on #59:
  `1 governance failure(s)` — the missing self-review record, which is this file. That is the
  compensating control for POAM-008 executing against its own author, and it is the first time
  it has run since 2026-08-13.
- **My own earlier claim was falsified by measurement, not by reflection.** I told the system
  owner twice that a self-hosted runner would close POAM-005/006/010/014 together. The
  `production` environment's only protection rule is `branch_policy`, not `required_reviewers`;
  the repository returns no `security_and_analysis` block. Both need a paid plan or a public
  repo. Corrected in `poam.md`, where the wrong claim lives, and not only in the PR.
- **The strengthened manifest check was run in both directions.** Removed
  `docs/13-solo-operation.md` from the manifest → 1 error naming that file, exit 1. Restored →
  exit 0. A check I have not seen fail is a check I have not seen.
- **Both host defects were reproduced and then re-run to confirm the fix**, rather than fixed
  by inference: the WSL `bash` shadowing, and `NoDefaultCurrentDirectoryInExePath` breaking
  `actions/setup-python` at `'python-3.12.10-amd64.exe' is not recognized`.

## Agent findings

**None — no three-pass agent review.** Same as #48, #50, #52 and #56.

**If one thing gets an independent read, make it the decision to keep POAM-014 open at High
rather than close it.** A merge gate exists, is required, and demonstrably blocks. Calling that
done is defensible. I think it is wrong, because nothing verifies *code* before merge, and an
entry that reads "closed" invites exactly the assumption the entry was written to prevent.

## Not verified

- **The runner is not durable.** `Register-ScheduledTask` was blocked, so it runs from this
  session. **If it stops, every PR blocks on a check that never reports** — the safe direction,
  but it presents as a hung PR rather than a stopped runner. The command is in the runbook and
  has **not been executed**. This is the single most likely way this work quietly stops working.
- **The runbook has never been followed end to end by anyone but me, on the one host it
  describes.** The hash-verification snippet in it is a cleaned-up version of what I ran, not a
  transcript of it — I verified the hash, but not by executing that exact block.
- **`sync-platform.sh` is still unexercised** (carried forward from #56). Six more documents
  are now classified; whether sync actually delivers them is still unproven.
- **Two of the three required checks have not yet passed on this runner.** `Platform integrity`
  failed on `setup-python` and is being re-run after the environment fix; `Dependency review`
  had not completed when this was written. I am claiming they are *fixed*, not that I have
  watched them go green — if they have not by the time this merges, that is a live failure and
  not a formality.
- **Concourse ran none of this.** Its jobs track `main`, so everything here has been validated
  locally and by the Actions gate only.

## Cold-read notes

- **What I did not want to look at:** I have now shipped the same defect class twice in two
  days. Yesterday's manifest validator printed "every tracked path is governed" while looping
  over top-level directories. I wrote that summary line myself, one day after writing a lesson
  about fixing the class rather than the instance, and it took stumbling over an unrelated file
  to notice. L0016 is written from that, but the lesson exists because the guard did not.
- **The duplication I argued against a day ago, I have now introduced.** `platform-integrity`
  runs in Concourse *and* in this gate. I still think prevention-versus-detection justifies it,
  and I notice that it is the kind of justification that reads well and could cover almost any
  duplication. Worth someone else's eye.
- **The blast radius of one Windows box went up today.** It runs Concourse, Vault, and now
  three required status checks. The mitigations are real — fork PRs refused, no Vault or
  Concourse credentials in Actions secrets, repository-scoped runner — but the concentration is
  a fact, and `docs/06-cicd.md` now says so where it previously recommended ephemeral runners
  without qualification.
- **The most useful thing here is not the runner.** It is that POAM-008's compensating control
  executes again. Solo operation had been accepted for two days on the strength of a check that
  could not run, which is documented false assurance — the exact failure mode the register is
  meant to catch, sitting inside the register.

## Residual risk accepted

- Single-identity review, no agent passes, on a change that alters what can reach `main`.
- The gate verifies process, not code. POAM-014 stays open at High.
- The runner's persistence depends on a manual step that has not been taken.
- Next external sample review due: 2026-10-01.
