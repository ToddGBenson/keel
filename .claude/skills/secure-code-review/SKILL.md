---
name: secure-code-review
description: Review a pull request or diff for correctness, security, failure behavior, and test quality — including the specific failure patterns of AI-authored code. Use when reviewing a PR, running the G3 gate, checking someone else's implementation, or when asked whether a change is safe to merge. Covers calibrating against automation bias.
---

# Secure code review

Consumers: `developer` (as reviewer), `/review`, `process/gates/g3-code-complete.md`.

## Independence first

Review is performed by an identity that is **not** the author. Spawn a **fresh** agent
invocation that has not seen the implementation reasoning — there are no fresh eyes inside
the same reasoning chain, and that correlation is precisely what the control exists to break
(AC-5, AIC-2).

Asking the implementing agent to "review its own work carefully" produces a review anchored
on the reasoning that created the bug.

## Not style

The linter handles formatting. A review spent on naming and whitespace is a review that did
not look for the logic error, and both parties leave feeling productive.

Review in this order — it is ordered by how expensive the miss is:

## 1. Correctness against the acceptance criteria

Read the AC list. For each one, find the code that satisfies it and the test that proves it.
Then ask what the AC does **not** say, and check what the code does there.

Most correctness bugs are not wrong logic. They are **unconsidered cases**: empty collection,
single element, duplicate, unicode, negative, zero, null, the maximum, the maximum plus one.

## 2. Security

- **Authorization on the object, on every path, server-side.** Not on the route. Not in the
  UI. Trace the alternates: batch endpoint, export, admin route, retry, webhook, the GraphQL
  resolver someone forgot.
- **Validate at the boundary, encode at the sink.** Both, in different places. Validation is
  not escaping.
- **Every query parameterised** — including in tests and migrations, because that is where
  the copy-paste pattern gets learned.
- **Fails closed.** Find the `catch` blocks. What does the code do when the authorizer
  throws, the token fails to parse, the store is unreachable? `catch { return allowed }` is
  how breaches begin.
- **No secrets, no personal data in logs.**
- **Errors say what to do, not how the system is built.**
- **Every control the threat model allocated is present** — point at the line. If you cannot
  find it, it is not implemented.

## 3. Failure behavior

The interesting bugs live here, and tests rarely reach them.

- What if the dependency is **slow** rather than down? That path is usually untested and
  usually worse than the outage path.
- What happens on partial failure — half the batch written?
- **Two requests race.** Read-then-write without a lock. Check-then-act. Non-transactional
  quota and uniqueness checks.
- Retry: is the operation idempotent? Does the retry amplify?
- Timeout: is there one? Is it shorter than the caller's?

## 4. Test quality

> **Mentally delete the implementation. Which tests fail?**

If a plausible bug leaves them green, they are decorative — and worse than absent, because
they inflate coverage and buy false confidence. Detail in the `test-strategy` skill.

Confirm specifically that **every allocated security control has a negative-case test**
proving it denies. The positive case proves the feature.

## 5. Maintainability

Will the next person understand it? Is the abstraction earning its cost? Premature
generalisation is the most common form of damage a good developer does.

---

## Reviewing AI-authored code specifically (AIC-9)

Agent output is usually right. That is exactly what makes complacent review dangerous — the
base rate trains you to skim, and the failures do not look like failures.

**Verify claims rather than reading them.** The PR says a control is implemented: go find the
line. The PR says the tests cover the error path: open the test.

### The plausible-but-wrong catalogue

What machine-generated code gets wrong, ranked by how often it survives review:

| Pattern | What it looks like |
|---|---|
| **Inverted condition** | `if (user.isAdmin \|\| resource.isPublic)` where it should be `&&` — reads naturally, fails open |
| **Off-by-one at a boundary** | `<=` where `<` belongs; correct-looking, wrong at exactly the limit |
| **Authorization on the route** | A clean-looking middleware check that never validates object ownership |
| **Swallowed exception** | `except Exception: pass` with a plausible comment about resilience |
| **Non-transactional check-then-act** | Reads a count, then writes. Correct single-threaded, wrong under load |
| **Confident hallucinated API** | A method that does not exist, or exists with different semantics — compiles in a dynamic language, fails at runtime |
| **Hallucinated dependency** | A plausible package name an attacker has registered. See `dependency-vetting` |
| **Tests mirroring the bug** | Tests written from the implementation encode the same misunderstanding and pass |
| **Over-broad error message** | Internal identifiers or stack detail in a user-facing string |
| **Plausible constant** | A timeout, limit, or retry count that sounds reasonable and matches nothing real |

### State what you verified personally

"LGTM" on agent-authored code is a control failure. The PR template asks for this; mean it:

> Traced AC-1..3 to tests and confirmed each goes red with the implementation stubbed.
> Confirmed `DraftAuthorizer:47` checks object ownership, and that the export path at
> `export.py:23` also routes through it. Did **not** verify the performance NFR.

**Approving code you do not understand is a control failure**, not politeness. "I don't
understand this — explain it or simplify it" is the correct professional response, and it is
usually the most valuable comment in the review.

---

## Writing the comment

Specific, reproducible, and about the code:

> `drafts.py:88` — the quota check reads then writes outside a transaction. Two concurrent
> autosaves at quota−1 both pass. Reproduce: parallel POST at 4 of 5. Suggest a row lock or a
> DB constraint.

Not: "this might have a race condition."

## The three outcomes

**Approve** · **Request changes** — with the specific defect and how to reproduce it ·
**Ask a question** — underused, and frequently the most valuable. A question costs the author
two minutes and often surfaces that they were unsure too.

## Size

Past ~400 changed lines reviewers degrade to skimming and everyone involved knows it. Ask for
a split rather than performing a review you know is shallow.

## Controls

SA-11 · SA-11(1) · AC-5 (separation of duties) · CM-5 · AC-3 · SI-10 · AIC-2 · AIC-7 · AIC-9.
