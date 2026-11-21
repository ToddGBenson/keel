# Self-review — TheHub #62072: platform-release.sh verify --key (61779 A)

PR: #206 (binnacle pair: #103)   Author: Claude Opus 5.5 (AI-authored)   Date: 2026-11-20
Story: the verifier only checks keyless signatures (a Fulcio certificate for release.yml at the
tag). A keyed release signed in Concourse with a Vault transit key (61779 B, TheHub #62073)
cannot be verified. Add a keyed mode, with the public key read from the trusted ref.

verdict: pass

## The change

`scripts/platform-release.sh verify --key`:
- checks the bundle with `cosign verify-blob --bundle B --key K F`, with no
  `--certificate-*` flag: a key signature has no certificate to hold them against;
- reads K only from `.github/cosign.pub` as committed on the trusted ref (`git show <trusted
  sha>:.github/cosign.pub`, into a temporary file removed on exit). `--key` takes no value, so
  the key is never an argument, and the working tree is never read. No key on the trusted ref is
  a refusal. A file there that does not start `-----BEGIN PUBLIC KEY-----` is refused (a
  committed private key, say);
- runs the tag, trusted-ref, release-floor and `--tree` checks through the same code as keyless.
  The signature step is the only branch (`verify_keyed` / `verify_keyless`).

Keyless stays the default and its cosign argv is unchanged, flag for flag.
`/.github/cosign.pub` is added to CODEOWNERS next to `/.github/release-floor`, the other reviewed
input the verifier reads from the trusted ref.

## Verified independently

- `test/platform-release.test.py` in python:3.13 (the CI image), with a stubbed cosign that
  verifies a `--key` call only when handed the good key. New checks:
  - keyed pass, with cosign handed the trusted ref's key and no certificate flags;
  - a wrong key on the trusted ref: refused;
  - a key only in the working tree (written and staged, never committed): refused before cosign;
  - `--key PATH`: refused as an unknown argument;
  - a non-PEM-public-key `.github/cosign.pub`: refused;
  - keyed mode refuses a tag off the trusted ref, a tag below the floor and a tag as the trusted
    ref, and passes `--tree` on the signed tree (the shared path);
  - keyless argv exactly as before (guard).
- The same test file against origin/main's script: 11 checks fail (red), all pass on the branch.
- keel's lint and test stages and shellcheck task, run in their CI images: green.
- binnacle's `scripts/platform-release.sh` and `test/platform-release.test.py` were byte-identical
  to keel's before this change, and are after it.

## Not verified

- No real cosign key signature was verified; the test stubs cosign. A keyed `sign-blob` bundle
  uploaded to Rekor verifies with this command; one signed with `--tlog-upload=false` would also
  need `--insecure-ignore-tlog`, which this PR deliberately does not pass. That choice belongs to
  62073, which signs.
- Nothing calls `--key` yet: `ci/scripts/supply-chain.sh` still verifies keyless. 62073 wires it.
