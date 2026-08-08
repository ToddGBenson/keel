# L0010: Verify the capability before enabling the control

**Date:** 2026-08-08 · **Source:** first real PR · **Class:** promotable · **Severity:** High
**Applies to:** any control that requires operator setup — signing, MFA, attestation, encryption
**Landed as:** the capability probe in `scripts/configure-github.sh` step 4b
**Related:** [L0006](0006-enforcement-strength-is-not-uniform.md)

## What happened

`configure-github.sh` enabled `required_signatures` on the default branch — a correct control
(SI-7, CM-14) — without checking whether the operator could actually sign commits.

No signing key was configured, which is the default state. Every commit was therefore
unsigned, and the first PR became **permanently unmergeable**.

The diagnosis cost was the real damage. GitHub reported `mergeStateStatus: BLOCKED` with:

- `mergeable: MERGEABLE`
- all 11 status checks green
- `reviewDecision: null`, zero required reviews
- no unresolved threads, no rulesets

Nothing in the API response named signatures. Ruling out reviews, rulesets, stale branches,
and conversation resolution took far longer than the fix.

## Why it happens

Enabling a control is one API call. Acquiring the capability to satisfy it is a multi-step
setup on the operator's machine plus a registration with the provider. The two are far apart,
so the first is easy to do alone — and it looks like progress.

The failure is silent at configuration time and only appears at the first merge, by which
point the cause is several steps behind you.

## The rule

**Never enable a control the operator cannot yet satisfy.**

Before enabling, probe the capability — and probe it by *doing the thing*, not by reading
config:

```bash
git commit-tree -S -m probe "$(git rev-parse HEAD^{tree})"   # actually sign something
gh api user/ssh_signing_keys                                  # is the key registered?
```

Config that *looks* right is not capability. `user.signingkey` can be set to a path that does
not exist; a key can be present locally and unregistered with the provider — which produces
`verified=false reason=unknown_key`, indistinguishable from unsigned at the merge gate.

If the capability is missing: **do not enable**, print the exact setup commands, and say
plainly that the control is unsatisfied so it can be recorded as a finding. Also *remove* the
control if a previous run enabled it — leaving a trap in place is worse than never setting it.

## How you would know you hit this

A PR is `BLOCKED` with everything green, no required reviews, and no explanation. Check
`gh api repos/{owner}/{repo}/commits/{ref} --jq .commit.verification` early — it is cheap and
it is not in the obvious list of things to check.

## The broader form

This is L0006 from the other direction. L0006 says: do not *claim* a control you do not
enforce. L0010 says: do not *enforce* a control you cannot satisfy.

Both produce a control map that does not match reality. The first overstates security; the
second halts delivery. The second is more embarrassing and easier to avoid — one probe.
