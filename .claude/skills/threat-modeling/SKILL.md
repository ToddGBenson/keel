---
name: threat-modeling
description: Run STRIDE threat modeling on a change delta and produce dispositioned threats with allocated controls. Use when running G2 design review, writing or reviewing a threat model, assessing what can go wrong with a design, or when a story is flagged security-relevant. Also use when asked to identify attack surface, trust boundaries, or security risks in a proposed change.
---

# Threat modeling

The method behind G2. Consumers: `architect`, `security-engineer`, `/design`,
`process/gates/g2-design.md`, `docs/templates/threat-model.md`.

## Model the delta, not the system

Full-system threat models go stale within a sprint and stop being read. Model **what this
change adds or alters** — the new boundary crossing, the new data path, the new privilege.
Delta models stay true because they are small enough to keep true.

If the change touches an existing boundary, re-examine that boundary. If it does not, do not
re-model it.

## The four questions

Shostack's frame. Answer them in order; skipping to controls produces controls for threats
nobody established.

### 1. What are we building?

Draw the data flow of the delta with **trust boundaries marked**. A boundary is anywhere
data crosses between components with different privilege, ownership, or trustworthiness.

```
[User] ──HTTPS──▶ ║ [API] ──▶ [DraftService] ──▶ ║ [Postgres]
                  ║ boundary: untrusted → app    ║ boundary: app → data
```

Then name:
- **Assets** — what is worth attacking. Data, credentials, availability, the integrity of a
  decision.
- **Actors** — legitimate users and their rights; adversaries and their *plausible*
  capability.

Be realistic about adversaries. A nation-state threat model for an internal CRUD app
produces a long document and no actionable controls.

### 2. What can go wrong?

STRIDE, applied **at each trust boundary crossing**. Walking the boundaries is what makes
this systematic rather than a brainstorm.

| Threat | The question | Common real finding |
|---|---|---|
| **S**poofing | Can an actor claim an identity they do not hold? | Session fixation, token replay, missing origin validation |
| **T**ampering | Can data be modified in transit, at rest, or **in the pipeline**? | Unsigned artifacts, mutable tags, missing integrity check |
| **R**epudiation | Can an actor deny an action we cannot prove? | Missing audit event, log without actor identity |
| **I**nformation disclosure | Can data reach an unauthorized party? | **IDOR** — still the most common finding in mature code. Also over-broad responses, error messages, logs, timing |
| **D**enial of service | Can availability be exhausted, by whom, at what cost *to them*? | Unbounded query, no rate limit, amplification |
| **E**levation of privilege | Can an actor gain rights beyond their grant? | Authz on the route not the object, confused deputy, path traversal |

Record each as: threat · category · attacker · **precondition** · impact · likelihood ·
severity.

The precondition column does the most work. "An attacker reads another user's draft" is
vague; "any authenticated user can read any draft by changing the ID, no other precondition"
is a finding with a severity you can defend.

**If the change is AI-relevant**, also consider prompt injection (direct and indirect),
insecure output handling, and tool-call abuse — but cross-reference the AI Impact Assessment
rather than duplicating it. See the `ai-impact-assessment` skill.

### 3. What are we going to do about it?

**Every threat gets one of four dispositions. An undispositioned threat fails G2.**

| Disposition | Requires |
|---|---|
| **Mitigate** | A control, the **file or component** implementing it, and the **verification method** |
| **Transfer** | Who now carries it, under what contract |
| **Accept** | Human approval + POA&M entry + expiry date + named compensating control |
| **Eliminate** | Remove the feature, or do not collect the data |

Two rules that decide most G2 rejections:

**"Implemented in the application layer" is not an allocation.** Name the file. A developer
cannot act on a vague allocation and QA cannot verify it.

**A mitigation with no verification method is an intention.** "We will validate input" stays
an intention until someone names the test that proves it. That test is what G4 looks for.

### 4. Did we do a good job?

- Every trust boundary crossing examined
- Every STRIDE category considered against every boundary — *even where the answer is "none",
  record that you looked*
- Every threat dispositioned
- Every mitigation names a component **and** a verification method
- Every acceptance has approval, POA&M entry, and expiry
- Attack surface change identified and justified (SA-15(5))
- Reviewed by an identity other than the author

## Assumptions — state them as falsifiable

Every threat model rests on assumptions. Write them as things that **could be false**,
because when one breaks the model must be re-run and nobody will notice unless it was
written down.

> "The API gateway terminates TLS and rejects unauthenticated requests."
> "The database is not directly reachable from the internet."
> "Session tokens are rotated on privilege change."

## The negative-case handoff

For every control you allocate, the verification method should be a test proving the control
**denies**. A test showing an authorized user succeeds proves the feature works. Only the
denial test proves the control works, and only it is SA-11 evidence.

Say this explicitly in the allocation so the developer writes the right test.

## Output

`docs/templates/threat-model.md` → `evidence/<issue>/g2/threat-model.md`.

## Controls

SA-11(2) (threat and vulnerability analysis) · SA-8 (security engineering principles) ·
SA-15(5) (attack surface reduction) · RA-3 (risk assessment) · PL-8.
