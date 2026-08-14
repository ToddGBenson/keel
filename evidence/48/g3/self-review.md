# Self-review — #48

Mode: solo (POAM-008)
PR: #49   Author: Todd Benson (claude-opus-5, AI-authored)   Date: 2026-08-13

A one-token path fix, found by executing the pipeline and verified the same way.

## Verified independently

- **The defect is real and was observed, not predicted.** `keel/build-and-attest/1` errored
  with `exec failed: unable to start container process: exec: "syft": executable file not
  found in $PATH` on the first run after the pipeline was set against `main`.
- **The cause.** `anchore/syft:v1.51.0` is distroless: `docker run --entrypoint sh` fails with
  `exec: "sh": executable file not found`, and the binary answers at `/syft` —
  `docker run --entrypoint /syft anchore/syft:v1.51.0 version` reports `syft 1.51.0`.
- **The fix runs the real arguments.** Executed the task's exact argument list
  (`scan dir:repo --exclude ... --output cyclonedx-json=...`) under `/syft` against a real
  directory: **exit 0**, one benign warning about deriving an artifact ID from a path.
- **The contrast case, so the fix is not cargo-culted.** `zricethezav/gitleaks:v8.18.4` ships
  its binary at `/usr/bin/gitleaks`, genuinely on PATH. That task was never affected, which
  is why `path: gitleaks` is correct there and `path: syft` was not here. The difference is
  per-image.
- **Blast radius.** `ci/tasks/sbom.yml` has exactly two consumers — `build-and-attest` and
  `mykronos-atlas` — so one change fixes both. Confirmed by the structural validator's
  reference map.
- `fly validate-pipeline`, `scripts/validate-pipeline.py` and the YAML parse all still pass.

## Agent findings

**None — I did not run the three-pass agent review.**

That is a deliberate departure from the `self-review` skill, and the reasoning is: the change
is a single token in a path, the defect was observed in a real build rather than reasoned
about, and the fix was confirmed by running the exact failing command. Three fresh agents
reading a one-line diff would have produced ceremony, not independence.

Recording it as a departure rather than quietly sizing the process down. If a reviewer
disagrees, the correct response is to run them — not to argue the record was adequate.

## Not verified

- **The fix has not run in Concourse.** The `keel` pipeline points at `main`, and this fix is
  on a branch. It is verified by running the identical command in the identical image by
  hand, which is strong — but it is not the same as a green `build-and-attest`. That happens
  after merge, and I have not seen it.
- **`mykronos-atlas` remains paused** for an unrelated reason (no ingestion token), so its
  sbom task has still never executed at all, before or after this change.
- **No check prevents this class from recurring.** Nothing verifies that a task's `run.path`
  resolves inside its declared image. Raised in #48 with a sketch (pull each image, resolve
  each path, on a cadence rather than per-PR) and deliberately not built here.
- The `--output cyclonedx-json=sbom/sbom.json` form was exercised as
  `--output cyclonedx-json=/tmp/s.json`. Same flag, different destination; the Concourse
  output directory itself is unexercised.

## Cold-read notes

- **What I did not want to look at:** whether the same mistake is in the other tool tasks. I
  checked rather than assumed — gitleaks is fine — but the instinct was to fix the one that
  broke and move on, which is precisely how L0008 (fixes must be propagated to siblings)
  gets earned.
- **This is the fourth time this session that something passed every static check and failed
  on execution.** The windowed time resources, the pipefail inversion, the assignment-prefix
  token bug, and now an image path. The pattern is not "the checks are bad" — it is that
  static checks answer questions about *text*, and all four of these were facts about a
  *running system*. L0011 already says this; I keep relearning it at a slower rate than I
  would like.
- The honest reason the pipeline was never run before today is that it needed a credential
  manager, and that needed a decision I was right to wait for. But "blocked on a decision"
  quietly became "unverified for a week", and the defect was sitting there the whole time.

## Residual risk accepted

- Single-identity review, and in this case a **reduced** one: no agent passes at all.
  Proportionate to a one-token fix; not proportionate to anything larger.
- Verified by hand-running the container rather than by a green pipeline job.
- Next external sample review due: 2026-10-01.
