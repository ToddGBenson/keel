# Self-review — #169

Mode: solo (POAM-008)
PR: #170   Author: Todd Benson (Claude Opus 5.5, AI-authored)   Date: 2026-11-05
verdict: pass

`sast` is OOM-killed during CodeQL evaluation (builds 135, 138, 141: exit 137). This PR runs the
two languages one at a time and makes `--ram` state the 2048 MB CodeQL really uses.

## Verified independently

- **The cause is read from the build log, not inferred.** Build 141's events show, for both
  languages, `Warning: rounding --ram up to the minimum of 2048` and `max heap size is only
  1356 MB` (python 1382 MB). Both `codeql-python` and `codeql-javascript` were placed on the
  same worker. `test` and `sca` ran their tasks on the other worker: their only steps on the
  first worker were 1-second cached `get`s. The javascript task got exit 137, while python
  finished with 11 findings, none at medium or above.
- **Builds 135 and 138 were before #159.** Their logs have no `--ram` line and no rounding
  warning, because CodeQL sized itself from the host. In 135 both languages were on one worker
  and both were killed. In 138 only the javascript one was killed. So #159 alone could not
  have fixed this: its 1024 was rounded up to 2048, and two of those still do not fit.
- **Build 136's exit 1 is a different cause.** Its python task printed `7.8: 1` and
  `ERROR: 1 security finding(s) at severity >= medium`. That finding was
  `py/overly-permissive-file` on a test stub's `chmod 0o755`, fixed by #157 (9699ecb).
  Builds 137.1 and 139 passed on that commit.
- **The new checks fail against main.** The test was committed first (81bb7fa) and run against
  main's pipeline and script: 2 failures, `--ram resolves to 1024` and
  `sast[2].in_parallel (2 CodeQL branches, limit=None)`. They pass on this branch. These are
  **guards**: they read YAML and script text. They are not evidence that the job survives.
- **The evidence is a run of the real script.** I ran `ci/scripts/codeql.sh`, at this branch, in
  a `python:3.13` container with `--cpus 2 --memory 2g --memory-swap 2g` (smaller than a 3 GiB
  worker). It ran javascript-typescript and then python, both suites, with a once-a-second
  sample of the cgroup's anonymous memory:
  - javascript-typescript: rc 0, 0 findings, heap 1356 MB (the same as build 141), peak anon
    1560 MiB, 0 OOM kills.
  - python: rc 0, 11 findings (3 note, 8 warning, none at medium or above, the same as build
    141), heap 1382 MB, peak anon 1553 MiB, 0 OOM kills.
  Two at about 1.5 GiB each come to more than 3072 MiB. One fits, even in 2 GiB.
- **Every test that reads the touched files passes:** codeql-limits, container-limits,
  serial-lanes, task-timeouts, check-run, poam-wiring, platform-release, supply-chain.
  `fly validate-pipeline` (8.3.1) gives "looks good". `container-limits`, `serial-lanes` and
  `task-timeouts` already walk the `in_parallel: {steps: [...]}` form, so the CodeQL steps are
  still checked for a CPU share and a timeout.

## Agent findings

None. No three-pass agent review was run.

## Not verified

- **No Concourse `sast` run of this branch.** keel's pipeline sets itself from main, so the
  first real run is after merge. Until then the survival claim rests on one container
  measurement, not on a worker.
- **`limit: 1` with fail_fast false running javascript after a python failure** comes from
  the Concourse docs and fly's validation. I did not observe it in a build.
- **The margin beside other pipelines is unmeasured.** Serial groups do not span pipelines, so a
  heavy thehub or mykronos task can still be placed beside this evaluator on a 3 GiB worker.
- **The container's page cache behaves differently from a worker's.** `memory.peak` reached the
  2 GiB cap in the measurement because of page cache from the 846 MB bundle and its
  extraction. Anonymous memory is the figure that cannot be reclaimed. I am assuming the
  kernel reclaims cache the same way on a worker.

## Cold-read notes

- **The 1024 was a comment that agreed with the test, and both were wrong in the same way.**
  #159 set `--ram=1024` and wrote a test that held it at 1024. The test passed and the log
  printed the rounding warning on every run. The text-reading guard could not see the
  runtime, so the real figure only showed up when I read a build log.
- **I nearly wrote that `test` was competing on the same worker.** Its first two steps were
  placed there, and I had put that in the issue before I checked that they were cached `get`s
  lasting one second. I corrected the issue. The two CodeQL tasks were the only heavy tasks on
  that worker.
- `serial-lanes.test.py` still models `sast` at its old median of 8.88 min. With the languages
  in turn it will be longer, so the `codeql` lane's replay is now optimistic. I left the
  number alone because there is no new median to measure yet.

## Residual risk accepted

- One evaluator per 3 GiB worker, with about 1.5 GiB for everything else placed beside it.
- The job takes longer by about one language's analysis time.
