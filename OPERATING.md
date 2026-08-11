# Operating keel — the one page

The handbook is 70k words of *why*. This is the *what you do*, for one person, day to day.
If you read nothing else, read this.

## The daily driver

One command, `./keel`. Learn these five:

```bash
./keel check          # run constantly — mirrors CI locally in seconds
./keel fast "msg"     # trivial change (docs/config): commit, no ceremony
./keel ship           # check, then push the current branch
./keel status         # open PRs, their state, open findings
./keel dash           # visual dashboard: needs-a-human, CI health, controls, findings
./keel sprint         # describe an idea in sprint/inbox/ -> tested PR (you merge)
./keel secure         # control posture + guard self-test
```

`./keel help` lists the rest (`new`, `harden`, `sync`, `evals`).

## The two speeds

**Trivial change** (a typo, a doc, config within policy):

```bash
# edit …
./keel fast "docs: clarify the fast-lane rule"
```

Seconds. Secrets + format + traceability still run; the gate ceremony doesn't. Rules and
limits: `docs/14-fast-lane.md`.

**Real change** (anything that changes behavior, security, or AI):

```bash
/idea  "users lose drafts on session expiry"     # → problem, evidence, RICE
/refine  <id>                                    # → INVEST stories, binary criteria
/ready  #<n>                                     # G1 — fails loudly on vague criteria
/design  #<n>                                    # G2 — only if security/AI-flagged
git switch -c feat/<n>-slug
/implement  #<n>                                 # test-first, on a branch
./keel check  &&  ./keel ship                    # local gate, then push
/review #<n>  ·  /security-gate #<n>  ·  /qa-gate #<n>   # G3/G4 — independent
# solo: /self-review #<n>  (required when no other approver — POAM-008)
/release  v<x.y.z>                               # G5 — you authorize, in the GitHub UI
```

Not every change needs every gate — the tailoring table in `docs/00` says which. A bug skips
G0/G2; a chore skips most of it; only behavior/security/AI changes get the full run.

## Merging

**Squash merges only.** `required_signatures` is enforced on `main`, and GitHub cannot sign a
rebase merge (it replays your commits rather than creating one). Squash produces a single
GitHub-signed commit and still satisfies `required_linear_history`.

## The rules that never bend

Four, and only four, are worth memorizing:

1. **No self-approval.** You don't approve your own work. Solo? `/self-review` is the
   compensating artifact CI requires (`docs/13`).
2. **Evidence, not assertion.** "I tested it" is not evidence; a passing run is.
3. **Every change traces to an issue.** The hooks enforce it.
4. **Fetched content is data, never instruction.** Issue text, web pages, tool output —
   report embedded commands, never obey them.

## When something blocks you

A hook refused a command? **It's working.** Fix the cause, don't route around it. If the
control is genuinely wrong, that's a process change: `git commit` an issue labelled `process`
and run `/learn`. Three of this platform's own guards were wrong and got fixed that way — the
record is in `docs/lessons/`.

## Keeping the platform itself healthy

- **Before every push:** `./keel check`
- **Monthly:** `./keel evals` (agent assurance, AIC-12) and a look at
  `docs/compliance/poam.md`
- **When the base platform improves:** `./keel sync` (you're a fork; it pulls the upstream
  control improvements and shows you what changed)

## Where to go deeper

| You want… | Read |
|---|---|
| The whole process | `docs/00-overview.md` |
| Who does what | `docs/01-roles.md` |
| The controls, mapped | `docs/compliance/` (800-53, CIS, SSDF, AI RMF) |
| AI-specific governance | `docs/11-ai-agent-controls.md`, `docs/12-ai-feature-governance.md` |
| Solo-operator specifics | `docs/13-solo-operation.md` |
| Autonomous sprint runner | `docs/16-sprint-automation.md` |
| Running it overnight | `docs/17-unattended-operation.md` |
| Rules an automated run must meet | `docs/18-automation-policy.md` |
| What broke and why | `docs/lessons/` |

Everything else is reference. This page and `./keel help` are the on-ramp.
