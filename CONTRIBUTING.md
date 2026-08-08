# Contributing

If you cannot be productive here within a week, that is a **finding about this process**, not
about you. Say so — open an issue labelled `process`. It is the most useful thing a new
contributor does.

---

## Day one — 30 minutes

```bash
bash scripts/install-hooks.sh        # git hooks + chmod the agent guards
bash .claude/hooks/selftest.sh       # 20 assertions; expect 20 passed, 0 failed
python scripts/validate-platform.py  # platform integrity
```

Then read, in this order:

1. **`README.md`** — the shape of it, and the honest limits
2. **`docs/00-overview.md`** — the six gates and what each one prevents
3. **`process/gates/g1-ready.md`** — the gate you will meet first
4. **`CLAUDE.md`** — the seven prime directives, if you are working with the agents

Skip the rest until you need it. `docs/` is reference material, not a reading list.

## The three rules that matter most

**No self-approval.** Whoever produced an artifact does not approve it. This is what makes
every downstream approval mean something, and it is enforced by branch protection rather than
by good intentions.

**Evidence or it didn't happen.** "I ran the tests" is not evidence; a workflow run URL is. If
you cannot link an artifact, the checklist item is unsatisfied — say so plainly.

**Every change traces to an issue.** Work with no issue is unauthorized change. The commit-msg
hook enforces it.

## Your first change

```bash
git switch -c feat/142-short-slug        # <type>/<issue>-<slug>
# write the failing test FIRST, then the implementation
git commit                                # conventional commit + "Refs: #142"
gh pr create                              # complete the PR template fully
```

The PR template asks three things people skip. Answer them properly:

- **What I made worse** — every change costs something. Say what. A PR claiming to improve
  everything and worsen nothing is one reviewers learn to distrust.
- **AI authorship** — which parts were agent-authored, and which agent. Not a warning label;
  it is how we measure whether AI-authored code fails review at a different rate and tune
  review depth on evidence.
- **What I verified personally** — as a reviewer especially. "LGTM" on agent-authored code is
  a control failure.

## Working with the agents

Ten roles in `.claude/agents/`, thirteen commands in `.claude/commands/`, sixteen skills in
`.claude/skills/`.

**Agents** = who does it and what they may not do. **Commands** = when it happens.
**Skills** = *how*, written once so the method does not drift.

Spawn the actual agent rather than asking one agent to role-play another — the constrained
toolset and prompt are part of the control. `/status` shows where everything sits.

## If a hook blocks you

**The hook is working.** Fix the cause.

Do not bypass it. If a control is genuinely wrong — and three of ours were, see
POAM-002/003/004 — that is a process change: open a `process` issue, propose the diff, run
`/learn`. A control you route around silently stays broken for everyone.

## When the process is wrong

It will be. It is a versioned artifact like any other, and improving it is normal work.

Describe the friction **concretely** — what you were doing, what the process demanded, what it
cost. Route-arounds are evidence about the process, never misconduct. Nobody here gets in
trouble for saying a rule is bad; the failure mode we actually worry about is people quietly
ignoring one.

`/retro` and `/learn` convert friction into a committed change. Retros are capped at two
actions and end in a merged PR, not a list of intentions.

## What will surprise you

**Gates reject things, and that is the point.** A gate that never rejects is ceremony. Expect
your first story to bounce at G1 on acceptance criteria that are not binary.

**"Unverified" is a valid answer** and is always better than "passed". Overstating coverage is
the most damaging thing you can put in an evidence record.

**Security and AI-risk blocks are not overridable** by schedule or by the Product Owner. Only
by documented, time-boxed, human-approved risk acceptance.

**A human authorizes every production deploy.** Agents assemble the evidence to make that
decision cheap to make well — not to make it unnecessary.

## Before you push

```bash
python scripts/validate-platform.py && bash .claude/hooks/selftest.sh
```

CI runs both. Running them locally saves a round trip.
