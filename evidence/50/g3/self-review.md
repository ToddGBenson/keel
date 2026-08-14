# Self-review — #50

Mode: solo (POAM-008)
PR: #51   Author: Todd Benson (claude-opus-5, AI-authored)   Date: 2026-08-13

One new job and one validator rule.

## Verified independently

- **`fly validate-pipeline` accepts the new job** against the real Concourse 7.14.3 CLI.
- **The validator rule fires.** Copied the tree, pointed `var_files` at a file that does not
  exist, ran `scripts/validate-pipeline.py`: one error naming the missing path, exit 1. A
  rule that cannot fail is not a rule, so this was run rather than reasoned about.
- **`var_files` points at a file that is actually committed.** `ci/vars.yml` is gitignored, so
  naming it would have produced a `set_pipeline` step that works on my machine and fails in
  Concourse. `ci/vars.example.yml` is tracked and holds this repository's real non-secret
  configuration.
- **No secret is in that file.** Re-read it: tool pins, versions, URLs, and empty deploy
  targets. Every credential is a `((var))` resolved from Vault — confirmed by the running
  pipeline, where the `repo` resource authenticates with `((github_user))`/`((github_token))`
  and its check succeeds.
- The pipeline is live on this Concourse with 17/17 unpaused jobs green, so the file this job
  will apply is a file already known to work.

## Agent findings

**None — I did not run the three-pass agent review**, for the same proportionality reason as
#48: one job definition and one validator branch, both exercised directly. Recorded as a
departure rather than sizing the process down quietly.

## Not verified

- **The job has never run.** `set_pipeline: self` is applied by Concourse, and this change is
  on a branch; the pipeline points at `main`. So the mechanism that makes the pipeline
  self-updating has itself only been validated statically. It proves itself on the first
  merge to main — and if it is wrong, the failure mode is that it does not self-update, which
  is exactly the silent drift it exists to prevent. **That is an uncomfortable bootstrap and
  it should be watched on the first run, not assumed.**
- **Concourse's behaviour when `set_pipeline: self` changes the job that is running it** is
  untested here. It is the documented pattern and 7.14 supports it, but I have not seen this
  pipeline rewrite itself.
- **A fork's values.** `var_files` naming `vars.example.yml` means a fork that edits the
  example gets its edits applied, and a fork that does not gets this repository's URLs. That
  is defensible for a template and I have not tested what a fork actually experiences.

## Cold-read notes

- **What I did not want to look at:** whether pointing `var_files` at `vars.example.yml`
  conflates "template" with "live config". It does, somewhat. The alternative — committing
  `ci/vars.yml` — was rejected because the gitignore on it is a deliberate defence, and I did
  not want to weaken a secrets-adjacent rule for tidiness. Worth revisiting if a fork trips
  on it.
- **The bootstrap asymmetry is the real risk here** and it is easy to wave past: every other
  job in this pipeline is verified by running it, and this one cannot be until it is merged.
  I have said so above rather than let "validates cleanly" stand in for "works".
- Noticed while committing that the mykronos Vault work had already been committed and merged
  by the operator on a parallel branch. Deleted my redundant branch rather than opening a
  duplicate PR — and checked that their in-progress `capabilities.py` was untouched, because
  the near-miss was committing someone else's work-in-progress alongside mine.

## Residual risk accepted

- Single-identity review, and a reduced one: no agent passes.
- The central mechanism is unverified until merge, by construction.
- Next external sample review due: 2026-10-01.
