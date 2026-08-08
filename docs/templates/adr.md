# ADR-<n>: <short decision title>

**Status:** Proposed | Accepted | Superseded by ADR-<n>
**Date:** <YYYY-MM-DD>
**Deciders:** <names/roles>
**Related:** issue #<n>, threat model, ADR-<n>

> Write an ADR only when the decision is **costly to reverse**. Do not write one for
> reversible choices — ADR sprawl devalues the records that matter. Accepted ADRs are
> **immutable**: supersede, never edit. The record of what we believed and why is the value.

## Context

What forces are at play? Constraints, requirements, existing commitments, deadlines, team
capability. State the facts that a future reader would not otherwise know — an ADR that
requires context you did not record is a decision nobody can evaluate later.

## Decision

What we are doing. Present tense, active: "We will use X for Y."

## Options considered

### Option A — <name> *(chosen)*
How it works. Why it wins here.

### Option B — <name> *(rejected)*
How it works. **Why rejected** — specifically, in terms of the forces above. "It was worse"
is not a reason.

### Option C — do nothing / defer *(rejected)*
Always consider this. Often it is right, and it is the option most often omitted.

## Consequences

**What we gain.**

**What we give up.** Every design forecloses options — name which. A consequences section
listing only benefits means the hard part was skipped, and it is how an ADR becomes a press
release.

**What becomes harder later.** The cost that arrives in eighteen months.

**Security and privacy impact.** Attack surface change, control implications, data handling.
Link the threat model.

**AI impact,** if any. Model, provider, data flows, assurance obligations created.

**Operational impact.** Monitoring, runbook, on-call, failure modes introduced.

## How we would know we were wrong

The signal that would tell us to revisit this. Specific and observable — a metric threshold,
a class of incident, a scaling point. An ADR with no falsification condition is a commitment
disguised as a decision, and it will be defended long after it stopped being right.

## Reversal cost

If we needed to undo this in a year: what would it take? This is the number that should have
determined whether an ADR was warranted at all.
