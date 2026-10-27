# Self-review — #144, TheHub #60936

Mode: solo (POAM-008)
Issue: #144   Author: Claude Opus 5.5 (AI-authored), for Todd Benson   Date: 2026-10-22

Make signing and attestation real (POAM-011), and make `verify-artifact` fail an unsigned
release.

## What the subject is, and why

keel ships no image (ADR-0004), so "images are signed" is read as the POAM-011 re-scope
reads it: the thing forks receive is the set of platform-owned files, and that is what is
signed. `scripts/platform-release.sh manifest` writes a SHA-256 line for every tracked
platform-owned file.

## Measured, not read (2026-10-22)

- Concourse `keel` pipeline (anonymous API): `build-and-attest` build 64 and `verify-artifact`
  build 60 both `succeeded`, while the script's cosign steps were `echo "ADAPT: ..."` lines.
- `https://api.github.com/repos/ToddGBenson/keel/releases/latest`: HTTP 404. keel has no
  release and no tag, so **after this merges `verify-artifact` is red until the first release
  is cut through `release.yml`.** That is the intended behaviour (nothing signed exists), and it
  is the operator's call to accept it.
- cosign 3.1.3 (the `ci/vars.example.yml` pin, checksum verified): `sign-blob` has `--bundle`
  and `-y/--yes`; `verify-blob` has `--bundle`, `--certificate-identity` and
  `--certificate-oidc-issuer`. Given a bogus bundle, the real binary refuses and
  `platform-release.sh verify` exits 1. Given no bundle it exits 1 as UNSIGNED.
- Manifest over this tree: 155 platform-owned files.

## Tests: red before, green after

`test/platform-release.test.py`, 37 checks.

- Source reverted to `origin/main` (script absent, old `supply-chain.sh` and `release.yml`):
  16 failed, 3 passed, then the run aborts where it copies the missing script.
- Only `supply-chain.sh` and `release.yml` reverted (new verifier kept): 17 failed, 20 passed.
  Every `verify-artifact` behaviour check fails: the old stage exits 0 for no release, an
  unsigned release and a bad signature alike.
- On this branch: 37 of 37.

Guards (green both ways, by design): "untracked file not in the release", "no CR in the
manifest", "no bundle -> cosign never called", "unsigned -> cosign never reached".

## CI-equivalent runs (python:3.13, the image Concourse uses)

- `STAGE=test ci/scripts/ci-stage.sh`: rc 0, including the new test, guard selftest 143/143,
  bypass corpus 62 hook runs 0 failed.
- `STAGE=build`: rc 0. `STAGE=lint` (with the shellcheck report): rc 0, including
  `validate-pipeline`, `validate-manifest` and `check-run` tests.
- `ci/scripts/shellcheck.sh` on `koalaman/shellcheck-alpine:v0.10.0`: clean, 31 files.
- checkov `github_actions` over `.github/workflows/`: 636 passed, 0 failed, 0 skipped.

## Not verified, so not claimed

- A real keyless signature. That needs GitHub's OIDC token in a `release.yml` run, which needs
  a tag, a change record and the `production` approval. POAM-011 stays **Open** until that
  run exists and a `verify-artifact` build verifies it.
- `gh attestation verify` against a real attestation, for the same reason.
- `sync-platform.sh` still takes `upstream/main`, not a signed tag; a fork does not yet verify
  before it syncs. Recorded under POAM-011 as not covered.
