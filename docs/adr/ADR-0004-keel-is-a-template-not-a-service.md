# ADR-0004: keel is a template, and is governed as one

**Status:** Accepted
**Date:** 2026-08-14
**Deciders:** platform owner (human), with agent-drafted analysis
**Related:** #56, ADR-0001, ADR-0003, POAM-006, POAM-010, POAM-011, POAM-014,
`platform/MANIFEST.yml`, `scripts/sync-platform.sh`

## Context

keel had been governed as though it were a deployable service. It has a release lane with a
staging deploy, a supply-chain lane that signs an artifact, a container scan, and POA&M
entries about production authorisation and artifact provenance.

None of those things exist. keel ships no artifact, has no production environment, and its
`registry`, `staging_url` and `production_url` are all empty. The release lane had **never run
once**, and `cosign sign`, `cosign attest` and `cosign verify` are `echo` statements.

The question "is everything in prod?" has no true answer here, and the honest one is not "not
yet" — it is **that is the wrong question for this repository.**

## Decision

**keel is a template.** What it distributes is itself, to forks, via
`scripts/sync-platform.sh` under the contract in `platform/MANIFEST.yml`.

### D1 — The manifest is the build output, and it gets a check

A template has no build to break, so the failure mode moves: an unclassified path is simply
never delivered to a fork, and **no fork can notice a file it was never sent**.

That had already happened, more than once. When `scripts/validate-manifest.py` was written and
first run, **nine tracked paths were unclassified** — including `keel` itself, the CLI the
operator actually types, and `evals/`, the agent assurance suite. `ci/`, the entire Concourse
pipeline, had been unclassified until caught by hand a day earlier.

The check now runs in `platform-integrity` on every commit: every tracked path is governed,
every platform-shipped entry exists, no path is claimed twice.

It deliberately does **not** require `project_owned` entries to exist. Those describe what a
*fork* will have — `src/`, `app/`, `package.json`. Requiring them would be requiring the
template to be an application, which is the confusion this ADR removes.

### D2 — A release is a tag, and its blast radius is wider than a deploy

`deploy-staging` is removed rather than left as scaffolding around an absence. The release
lane is `release-preflight` → `authorize-release`, and preflight now checks what actually
matters: does the manifest govern everything, does the platform validate, does the pipeline
forks inherit still validate.

**The authorisation control is not relaxed, because the risk is larger, not smaller.** A bad
service deploy affects one environment and rolls back in minutes. A bad platform release is
fast-forwarded into every fork's platform-owned paths, overwriting their local edits by
design, and each fork discovers it independently on its own schedule. `authorize-release`
still refuses to run without a recorded human.

### D3 — Inert lanes are inherited, not dead

`container-scan`, `build-and-attest` and `verify-artifact` stay, inert, with loud scope
statements. This is the reframe that matters most for reading this repository:

**a lane that does nothing here is not dead code — it is what a fork inherits.** The template's
job is to hand a fork a working container scan on the day it first ships an image, not to
delete the lane because the template itself has no image. The same is true of the `build`
job's "nothing to build" statement, which fails loudly if a manifest ever appears without a
build step behind it.

### D4 — Re-scope the findings that assumed an artifact, do not close them

POAM-006, POAM-010 and POAM-011 were written about deploying and signing something that does
not exist. The tempting move is to mark them not-applicable.

That would be wrong, and POAM-011 shows why: keel *does* distribute, and a fork currently has
**no way to verify that what it just pulled is what upstream intended**. That is the same
property SR-4(3) describes, applied to the thing this repository actually ships. Re-scoped,
not closed — closing it now looks like progress and buys nothing.

## Consequences

**Good.** The pipeline stops asserting things about an artifact that does not exist. The
delivery mechanism gets its first check, and that check immediately found nine ungoverned
paths. The release lane describes a real act.

**Bad.** "Is it in production?" remains unanswerable for this repository, and anyone arriving
from a service-shaped mental model will keep asking it. This ADR is the answer.

**Unresolved.** POAM-014 is unaffected and still Critical: `main` has no merge gate. Being a
template makes that worse rather than better — an unreviewed change here propagates to every
fork, which is precisely the blast radius D2 describes.
