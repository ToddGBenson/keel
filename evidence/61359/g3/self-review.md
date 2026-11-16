# Self-review — TheHub #61359 (ci/vars.example.yml pins MyKronos v15)

Mode: solo (POAM-008); agent self-review per the operator's 2026-11-04 decision
PR: #177   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-16
verdict: pass

`ci/vars.example.yml` pinned `mykronos_ref` to v15 (2dd4e44) while every `.github/workflows` pin is
v17 (603e0f0), and v15 predates mykronos #1036. The example moves to v17, and
`test/mykronos-pins.test.py` now reads it with the same rules as the workflow pins.

## Verified independently

- **Tag commits, from a mykronos clone:** v15 = 2dd4e4465c21 (2026-10-18), v16 = fc65c4b942c6,
  v17 = 603e0f0febee (2026-10-31), v18 = d5f792ad025c (2026-11-12). Every workflow pin (7 of them)
  names 603e0f0.
- **Red first:** with only the test change, the pins test fails 2 checks on main's example:
  "vars.example.yml:70 pins a commit that has #1036 (2dd4e4465c21 is v15 …)" and "every pin names
  the same commit".
- **Green after:** all checks pass, including the new "ci/vars.example.yml's mykronos_ref is among
  them" (so a pattern break cannot make it pass vacuously).
- **Suites** (python:3.13, --cpus 2 --memory 2g): every manifest test passes (keel: except
  `task-timeouts`, red on main and fixed by keel #175); `validate-pipeline.py` rc=0; guard selftest
  and agent evals pass.

## Agent findings

None. No three-pass agent review was run.

## Not verified

- The live Concourse vars: the test docstring says the live pipeline moved to v17, but the real vars
  file is not in the repository and was not read. Unverified.
- v18 exists; the pin follows the workflows (v17) rather than moving everything to v18, which would
  be its own change. Whether v17's uploader accepts every flag `mykronos-upload.sh` passes was not
  re-run here; it is the version the workflows already use. Unverified for the Concourse uploader.

## Cold-read notes

- The example is what a fork copies, so a stale pin there is a stale pin in every new fork; that is
  why it is now under the test rather than only edited.
- The same change is made in keel and binnacle, where the test file is identical.

## Residual risk accepted

None.
