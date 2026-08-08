# 14 — The Fast Lane

**Command:** `./keel fast "<msg>"` · **Principle:** tiered rigor · **Controls:** CM-3 (traceability preserved)

Personal DevSecOps lives or dies on this: **trivial changes must be fast, or you route around
the process** — which the platform itself calls the worst outcome (`docs/09`). The answer is
not to weaken the gates. It is to have two lanes, and to be strict about which change goes in
which.

## The two lanes

```
                    ┌─ FAST LANE ──────────────────────────────────┐
  docs · comments · │  ./keel fast "docs: fix typo"                │  automated checks only:
  formatting ·      │  no issue ceremony, no PR, no self-review,   │  secrets · format · commit-msg
  config-in-policy  │  no cooling-off. Seconds, not a session.     │  (the hooks still run)
                    └──────────────────────────────────────────────┘
                    ┌─ FULL FLOW ──────────────────────────────────┐
  anything that     │  /idea → /refine → /ready → [/design] →       │  the six gates.
  changes behavior, │  /implement → /review → /*-gate → /release    │  every control.
  security, or AI   │                                               │
                    └──────────────────────────────────────────────┘
```

## What qualifies for the fast lane

**All** of these must hold, or `./keel fast` refuses and sends you to the full flow:

- Touches **only** docs, comments, formatting, or config within existing policy
- Changes **no** logic, behavior, or control
- Touches **no** security-, AI-, or privacy-relevant path (auth, session, crypto, secrets,
  prompts, guardrails, workflows, hooks, agents, gates, compliance)
- Under 40 added lines

The check is mechanical and **fails closed** — a single disqualifying file blocks the whole
commit. You cannot talk it into the fast lane, which is the point.

## What still runs

The fast lane skips *ceremony*, not *safety*. Every commit still passes:

- **Secret scanning** — the one mistake you can't undo
- **Format + lint** (via the pre-commit hook)
- **Conventional-commit + traceability** — the commit carries a `Fast-Lane:` trailer and a
  reference to your standing housekeeping issue (CM-3 is preserved, not dropped)

And CI still runs the full suite on the branch. The fast lane is a *local* shortcut; the
server-side controls are unchanged.

## Setup (once)

Create one standing issue for housekeeping, and point keel at it:

```bash
gh issue create --title "Housekeeping (fast-lane changes)" --label chore
git config keel.housekeepingIssue <that issue number>
```

Now every fast-lane commit traces to a real work item without you opening one each time.

## The honesty rule

If you find yourself reaching for `./keel fast` on something that *almost* qualifies —
a one-line logic fix, a "quick" config change to a security path — **that is the signal to
use the full flow**, not to argue with the checker. The fast lane exists so the full flow
is worth respecting. Widen it and you have one lane again, the slow one, that everyone skips.

Emergency security fixes are **not** fast-lane changes — they follow the expedited path in
`docs/07`, which compresses timing but removes no control.
