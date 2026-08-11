# 18 — Automated Run Policy

**Contract:** `automation-policy.yml` · **Check:** `./keel sprint --preflight` · **Run:** `./keel sprint --unattended`
**Controls:** AIC-11 (bounded autonomy) · AC-5 (human authorizes) · CM-3 · SA-11 · SI-7 · CA-7

Five parameters govern every unattended run. They are not advice. `--preflight` reads
`automation-policy.yml`, and `--unattended` re-runs that check *at start of run* and refuses
to proceed if any parameter is unmet — a human having run preflight last week proves nothing
about tonight.

---

## P1 — CLI credential, never a standing API key

`credential_mode: cli`

The runner uses the local `claude` login. `api_key` is a prohibited value.

**Why it is a control and not a billing preference.** An `ANTHROPIC_API_KEY` in CI is a
long-lived credential that runs unattended with no session boundary, held by a system that
can also read the repository. The CLI login is bounded by a session a human established on a
machine that human controls. If the key leaks, the blast radius is every future scheduled
run, not one session.

**What this costs you.** The machine has to be awake — see `docs/17`. And the run inherits
your local filesystem and your session rather than a fresh ephemeral runner, so isolation is
weaker than CI's. That is a real trade, made deliberately: a standing credential is the
worse of the two risks.

**Consequence:** the scheduled GitHub Actions runner is **removed**, not disabled. A
workflow that must never be enabled is a trap, and a disabled trap is still a trap.

## P2 — Only dev-ready stories are eligible

`ready_label: ready` · `require_g1_evidence: true`

An unattended run starts at **G2**. It may not cross G0 or G1.

This is the parameter that most changes the system. The supervised path
(`./keel sprint`) takes a raw description and does its own intake, splitting and G1 — fine
when you are watching. Unattended, that would let a machine decide *what to build* with no
human present, which is a scope decision, not an implementation one.

So the unattended work list is **open issues carrying the ready label**, not `sprint/inbox/`.
The inbox holds unrefined ideas and is invisible to a scheduled run.

The label alone is not sufficient: `require_g1_evidence` makes the runner look for a G1 gate
record on the issue and skip the story if there is none. A label is a claim; the gate record
is the evidence (PD-3). Mislabelling is then a stopped run rather than an unrefined story
built at 3am.

## P3 — A non-prod environment to deploy and exercise

`nonprod_name` · `nonprod_deploy_command` · `nonprod_health_command`

All three required. The change is deployed to a lower environment and health-checked before
any human is asked to approve it.

**This deliberately loosens an earlier boundary.** The runner previously could not deploy at
all — the CI token omitted `deployments` and the guard hooks blocked deploy-shaped commands.
It can now deploy to *the environment this file names*, and only that one. Production remains
blocked by `guard-bash.sh` regardless of what any policy file says, because a control that a
config file can switch off is not a control.

Be honest about what changed: the runner's reach grew. What contains it is that the target is
declared in advance, in a file that is reviewed, rather than chosen at runtime by an agent.

## P4 — The final gate is a human approving what is running

`approval_mode: human_after_nonprod` — the only permitted value.

A human approves **what is deployed in the lower environment**, not a diff. The diff is how it
got there; the environment is what you are accepting.

There is no auto-merge mode, and adding one would falsify every AC-5 claim this repo makes.
The runner opens a PR and stops. `guard-bash.sh` blocks `gh pr merge`, and branch protection
backs that up, so this holds even if a future prompt says otherwise.

## P5 — Unit, functional and security tests, all enabled

`test_unit_command` · `test_functional_command` · `test_security_command`

All three declared and all three passing. The runner re-runs them itself after the agent
reports done, because an agent saying "tests pass" is an assertion and a re-run is evidence
(PD-3). Any failure means no PR — the branch is left for inspection with a `.BLOCKED.md`.

**A blank command is a policy violation, not a skip.** "No security tests configured" must
never render as green; that is L0007 (checkers that cry wolf, and checkers that stay silent
when they should not) applied to the thing that matters most.

---

## Why keel itself cannot run unattended

Run `./keel sprint --preflight` here and it fails P3 and P5. That is correct, and it is worth
stating plainly rather than papering over: **keel is a platform repo with no application to
deploy and no product test suites.** By its own policy it may not schedule an automated run.

A fork fills in `automation-policy.yml` with its stack's commands and its own environment.
Until it does, `--unattended` refuses. The platform holds itself to the rule it publishes.

## What a scheduled night actually looks like

```
  ./keel sprint --unattended
        │
        ├─ re-check all five parameters ─────────▶ any unmet → REFUSE, exit 1
        │
        ├─ work list = open issues labelled `ready`   (P2, capped at max_items_per_run)
        │     └─ no G1 evidence on the issue? → skip, write .BLOCKED.md
        │
        ├─ per story: threat model → failing test → implementation → control verification
        │
        ├─ protected-path check ─────────────────▶ touched a control → abandon branch
        ├─ unit / functional / security re-run ──▶ any failure → no PR, .BLOCKED.md
        ├─ deploy to non-prod + health check      (P3)
        └─ open PR
                │
                ▼
        YOU approve what is running in the lower environment   (P4)
```

## Residual risk, stated plainly

- **The self-review is written by the agent that wrote the code.** One reasoning chain
  produced both, which makes it the weakest form of the POAM-008 compensating control. It
  catches mechanical defects well and misunderstood requirements poorly. Overnight PRs
  deserve *more* scrutiny in the morning, not less.
- **P3 grew the runner's reach.** Declared-in-advance is a real mitigation, not an
  elimination. Review changes to `automation-policy.yml` with the care you would give a
  change to a workflow file.
- **Silence is not success.** If the summary says three processed and you approve three PRs
  without opening the environment, the automation has replaced your judgement rather than
  your typing. That is the failure mode this whole platform exists to prevent.
- **None of this has run end to end.** The refusal path is tested; the success path is not.
  See `docs/17`.
