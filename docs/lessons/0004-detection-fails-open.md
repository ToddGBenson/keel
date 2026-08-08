# L0004: Detection fails open; enforcement fails closed

**Date:** 2026-08-07 · **Source:** platform build · **Class:** promotable
**Applies to:** every automated control
**Landed as:** GP-4 in `docs/11-ai-agent-controls.md` · the no-parser path in `guard-write.sh`

## The tension

SA-8 says fail secure. Applied uniformly, that means a secret scanner whose parser is missing
blocks every write in the repo. Work stops, and within a day someone disables the hook —
after which it detects nothing at all.

**Failing closed made the control less safe.**

## The rule

| Control type | On its own failure | Why |
|---|---|---|
| **Enforcement** — approve, merge, push, production, secrets at rest | **Fail closed** | The action is consequential and often irreversible. Blocking costs a delay. |
| **Detection** — scanning, linting, content heuristics | **Fail open, loudly** | A detection control that halts all work gets removed, and a removed control detects nothing. Server-side CI is authoritative anyway. |

"Loudly" is load-bearing: the failure must appear in output, never be silent. A detection
control that fails open *quietly* is the worst of both — no protection and no signal.

## How you would know you hit this

A dependency of a *checking* control is missing and the entire workflow stops. Or, later:
someone has commented out a hook "temporarily."

## The deeper point

The safe choice is the one that leaves the control operating in six months, not the one that
looks strictest today. Strictness that gets bypassed is theatre with extra steps — and it
still reports green on the assessment, which makes it worse than an honest absence.
