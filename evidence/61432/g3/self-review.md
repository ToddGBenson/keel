# Self-review — TheHub #61432: a per-repository release floor

PR: #202 (binnacle pair: #95)   Author: Claude Opus 5.5 (AI-authored)   Date: 2026-11-18
Story: keel's `platform-release.sh` held every repository to `RELEASE_FLOOR`, keel's own commit
af878f1, so every release of a repository without keel's history (a template copy, binnacle) was
refused. Make the floor per repository, derived from a configured value, with a test that a fork
with no keel history passes and that keel's own floor still applies.

## The change

`release_floor()` in `scripts/platform-release.sh` decides the floor a tag's commit must descend
from:
1. **A shallow clone is refused.** Missing history is not the same as "no keel history".
2. **Keel's floor where it applies.** A repository that holds `RELEASE_FLOOR` (keel, or a GitHub
   fork with keel's history), or whose signer is `KEEL_UPSTREAM` (`ToddGBenson/keel`), is held to
   `RELEASE_FLOOR`. Upstream keel without that commit is refused.
3. **Otherwise, the repository's own floor:** the sha in `.github/release-floor` as committed on
   the trusted ref.
   - It is reviewed content, not a parameter, so whoever runs the verifier cannot lower it.
   - It must be a 40-hex commit in the repository and reachable from the trusted ref.
   - A configured floor can only move a keel floor forward, never back.
   - **With no such file, the release is refused**, naming the file to commit.

**Why there is no implicit default.** My first draft used the repository's single root commit as
the default floor. I dropped it on checking binnacle: its root commit (3f92a21) carries the
pre-gate release.yml, which has `id-token: write` and interpolates `inputs.change_record` into
`run:`. That is exactly what af878f1 closed. A root default would have accepted a tag on the
injectable workflow.

## Verified independently

- `test/platform-release.test.py`, in python:3.12-slim with git (this host has no `python`), all
  passed. The new cases:
  - upstream keel without its floor: refused;
  - a fork with no keel history and no floor file: refused, naming the file;
  - a fork with a configured floor: a tag at it passes, and a tag below it is refused;
  - a configured floor that is not in the repository: refused;
  - one that is not reachable from the trusted ref: refused;
  - one behind keel's floor: refused (forward only);
  - a shallow clone: refused.
- The existing cases are unchanged and pass: a tag below keel's floor, a tag not on the trusted
  ref, signature identity, tree verification.
- binnacle's `scripts/platform-release.sh` was byte-identical to keel's (blob 19f6727) before this
  change.

## Not verified

- No real cosign signature was verified; the test stubs cosign, as before.
- No real release was run. This changes release tooling, so it goes to Fable's review and the
  operator batch.

## For the operator

binnacle does not hold keel's floor and has no `.github/release-floor`, so with this change its
release is refused with that instruction. That is no worse than before, when it was refused for
lacking af878f1. Choosing binnacle's floor commit is the operator's decision. The candidate is
eca1114 ("pass workflow_dispatch inputs as data, not as program text", binnacle #9), the first
binnacle commit with af878f1's input fix. Check that its release.yml also carries the G5 gate
before naming it.

## Residual risk accepted

A configured floor is only as good as the review of the PR that sets it. This PR adds
`/.github/release-floor` to CODEOWNERS; in solo mode that routes the review request only
(POAM-008).
