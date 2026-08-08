# Architecture Decision Records

Decisions that are **costly to reverse**, with the reasoning that produced them.

Template: `docs/templates/adr.md`. Method: the `architect` agent, at G2.

## When to write one

Data model shape · service boundary · persistence or messaging technology · auth model ·
external dependency · public interface contract · AI model or provider choice.

## When *not* to

Anything reversible. **ADR sprawl devalues the records that matter** — a directory of thirty
ADRs where four were consequential means nobody reads any of them. The reversal-cost question
at the bottom of the template is the filter: if undoing this in a year is cheap, do not write
one.

## Rules

**Accepted ADRs are immutable.** You supersede; you do not edit. The record of what we
believed *at the time*, and why, is the entire value — an edited ADR is a retrofitted
justification.

**Record the rejected options and why.** An ADR listing only the chosen option is a press
release.

**Name the falsification condition.** "How we would know we were wrong" — specific and
observable. An ADR with no falsification condition is a commitment disguised as a decision,
and it will be defended long after it stopped being right.

## Index

| ADR | Title | Status | Date |
|---|---|---|---|
| [0001](ADR-0001-platform-architecture.md) | Governed agent-driven SDLC anchored to NIST 800-53 | Accepted | 2026-08-07 |
