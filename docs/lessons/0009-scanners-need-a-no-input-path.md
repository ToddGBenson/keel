# L0009: Every scanner needs an explicit no-input path

**Date:** 2026-08-08 · **Source:** first real CI run · **Class:** promotable
**Applies to:** any pipeline with SAST, SCA, IaC, container, or license scanning
**Landed as:** input-detection steps in all four scan jobs in `.github/workflows/security.yml`
**Related:** [L0007](0007-checkers-that-cry-wolf-get-muted.md) ·
[L0008](0008-fixes-must-be-propagated-to-siblings.md)

## What happened

The first CI run on a real PR failed four checks. None were findings. All four were the
same defect in different jobs:

| Job | What happened |
|---|---|
| SCA | grype found no manifests → produced no SARIF → **Upload SARIF failed** |
| IaC | checkov found no IaC → produced no SARIF → **Upload SARIF failed** |
| SAST | CodeQL found no JavaScript → **"no source code found"** |
| Secret scanning | needed `pull-requests: read` → 403 that reads as a scan failure |

Each was fixed in turn, and the *next* run surfaced the next one — three sequential red
runs for reasons unrelated to security. Exactly the tax L0008 describes.

## Why it happens

Scanners are written for the case where their input exists. A greenfield repository, a
docs-only repository, or a project before its first dependency has **no input**, and that is
a legitimate state — not an error and not a pass.

The default behaviours are both wrong:

- **Fail** → red gate for a non-finding reason. People learn the gate is noise.
- **`continue-on-error`** → green gate for a scan that never ran. **Worse:** the control map
  now claims coverage that does not exist, which is the overstatement L0006 warns about.

## The rule

Every scan job gets three states, not two:

```
input present   -> scan, gate on findings
input absent    -> SKIP, and say so LOUDLY in the job summary:
                   "SA-11(1) is NOT satisfied — no code was analysed.
                    This is a scope statement, not a pass."
scan failed     -> fail the gate
```

Gate on the scanner's **findings**, not on its exit code — tools exit non-zero for
configuration reasons that have nothing to do with your security posture.

And guard every SARIF upload on the file actually existing. `if: always()` on an upload step
is a trap: it runs precisely when the scan did not produce output.

## How you would know you hit this

Your first CI run on a new repo is red, and every failure is a tooling message rather than a
finding. Or, more dangerously: your pipeline is green on a repo where you know no scanner
could have found anything to look at.

## The check worth stealing

Ask of every green scan job: **what would this have to find for it to go red — and did it
actually look?** If you cannot answer the second half from the job summary, the summary is
not saying enough.
