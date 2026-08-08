# keel

*A governed SDLC base repo. Fork it; it keeps you upright.*

An executable SDLC. Ideas become stories, stories become verified software, and every
transition leaves audit evidence behind. Roles are played by Claude Code subagents;
a human holds the approval authority at every gate.

**Compliance anchors:** NIST SP 800-53 Rev. 5 (primary) · SP 800-218 SSDF (crosswalk) ·
NIST AI RMF 1.0 + AI 600-1 Generative AI Profile · OWASP LLM Top 10 · ISO/IEC 42001.
**Toolchain:** GitHub Issues + GitHub Projects + GitHub Actions.
**Team model:** AI agents execute, a human authorizes. Agents never self-approve a gate.

---

## The shape of it

```
   IDEA          READY          DESIGNED       BUILT         VERIFIED      RELEASED
     │             │               │             │              │             │
  ┌──▼──┐      ┌───▼───┐      ┌────▼────┐   ┌────▼────┐   ┌─────▼─────┐  ┌────▼────┐
  │ G0  │─────▶│  G1   │─────▶│   G2    │──▶│   G3    │──▶│    G4     │─▶│   G5    │
  │Intake│     │  DoR  │      │ Design  │   │  Code   │   │ Verified  │  │ Release │
  └─────┘      └───────┘      │ +Threat │   │Complete │   │ QA + Sec  │  │  Auth   │
                              └─────────┘   └─────────┘   └───────────┘  └────┬────┘
     ▲                                                                        │
     │                                                                        ▼
  ┌──┴──────────────────────────────────────────────────────────────┐   ┌──────────┐
  │  IMPROVE — retros, postmortems, gate-failure analysis           │◀──│  OPERATE │
  │  Every finding must land as a doc, a check, or an agent change. │   │ monitor  │
  └─────────────────────────────────────────────────────────────────┘   └──────────┘
```

Each gate is a **checklist + an approver + an evidence artifact**. No gate is passed by
assertion; it is passed by producing the evidence the gate names. See `process/gates/`.

## Use it as a base for a new project

This repo is a **template**. Fork it, bootstrap it into a project, and pull platform
improvements later.

```bash
gh repo create my-service --private --template ToddGBenson/keel
cd my-service

bash scripts/bootstrap.sh          # identity + stack; splices real commands into CI
bash scripts/configure-github.sh   # branch protection + environments — turns gates into controls
/idea  <a problem your users have>
```

`bootstrap.sh` detects or asks for your stack (`node` · `python` · `go` · `rust` · `none`),
replaces every `ADAPT:` placeholder with real commands, rewrites the README for your project,
**resets the POA&M and AI inventory to empty** — you inherit the process, not the base repo's
findings — and wires an `upstream` remote.

Later, when the platform improves:

```bash
bash scripts/sync-platform.sh --check   # what changed upstream
bash scripts/sync-platform.sh           # apply it
```

`platform/MANIFEST.yml` governs that sync: platform-owned paths fast-forward, project-owned
paths are never touched, and merge-required paths (your workflows, your `CLAUDE.md`) are
reported as a diff for a human to merge. Silently overwriting a workflow you tuned would
break your build; silently skipping it would strand you on an old control set.

## The learning loop crosses projects

`/retro` produces the record. `/learn` produces the diff — and classifies each lesson
**project-local** or **promotable**. `/promote` opens an upstream PR carrying the promotable
ones, so every fork receives them on their next sync.

The test is: *would a team on a completely different stack hit this same wall?*

`docs/lessons/` already holds eleven, every one a defect that shipped in this platform before it
was caught — including a secret guard that blocked the edit *removing* a secret, a control
that blocked its own repair, and a signing requirement enabled without the capability to
satisfy it, which made every PR permanently unmergeable.

## Quickstart

```bash
# 1. Capture a raw idea. Produces a problem statement, not a solution.
/idea  Users keep losing draft work when their session expires

# 2. Turn it into an epic + INVEST-shaped stories with acceptance criteria.
/refine  IDEA-014

# 3. Run the Definition of Ready gate. Fails loudly with specific gaps.
/ready  #142

# 4. Design + threat model (required for stories flagged security-relevant).
/design  #142

# 5. Implement against the story, TDD, on a branch, with control evidence.
/implement  #142

# 6. Independent review passes — they are separate agents on purpose (AC-5).
/review  #142           # code review
/security-gate  #142    # threat + control verification
/qa-gate  #142          # test verification, evidence capture

# 7. Release readiness + change record. Human authorizes the deploy.
/release  v1.4.0

# 8. Learn. Retro output must produce a committed change, not a wish list.
/retro  sprint-23
/learn  sprint-23
```

Run `/status` at any time to see where every work item sits against the gates.

## Layout

| Path | What lives there |
|---|---|
| `.claude/agents/` | The ten role agents — PO, architect, dev, security, QA, **AI risk**, delivery lead, release manager, compliance, tech writer |
| `.claude/commands/` | The workflow verbs listed above |
| `.claude/skills/` | The 16 shared *methods* — threat modeling, evidence writing, control verification, scanner triage, eval design, red-teaming, postmortems, and the rest. Written once; loaded on demand by whichever agent or command needs them |
| `.claude/settings.json` | Permissions and hooks that enforce the process mechanically |
| `.claude/hooks/` | Guard scripts — what makes the agent constraints non-optional |
| `docs/` | The written handbook — the "why" behind every gate |
| `docs/compliance/` | 800-53 control map, SSDF crosswalk, evidence model, SSP outline, POA&M |
| `docs/templates/` | Story, epic, ADR, threat model, test plan, change request, retro, exception |
| `process/gates/` | The six gate checklists. These are the contract. |
| `.github/` | Issue forms, PR template, CODEOWNERS, and the CI/CD + compliance workflows |
| `evidence/` | Generated. Gate evidence, indexed by work item and control. |

## AI governance — two scopes, deliberately separated

Conflating these is the most common failure in AI governance programs, so the platform
keeps them apart:

**Controls *on* the agents that build here** — `docs/11-ai-agent-controls.md` (AIC-1..12).
Least agency via scoped tool grants · separation of duties that survives automation ·
prompt-injection isolation · secret handling · AI-authorship provenance · hallucinated-
dependency defense · model and prompt change control · review calibrated against automation
bias · agent action audit trail · bounded autonomy with hard stop conditions · monthly
evaluation of the agents themselves.

**Controls *for* AI features shipped in products** — `docs/12-ai-feature-governance.md`.
AI impact assessment and risk tiering at G2 · eval suites gated against baseline in CI ·
red-teaming · guardrail verification by tests that prove blocking · human oversight design ·
transparency · drift monitoring · AI incident response · a maintained AI system inventory.

Read the enforcement table in `docs/11-ai-agent-controls.md` **by column, not by row**.
Prompt-only controls are advisory — a sufficiently confused model ignores them. The ones
that hold under adversarial conditions have a mark in the tool-grant, hook, or
branch-protection column. When adding a control, the question is never "what should the
agent be told" but **"what makes the unwanted action impossible."**

## The three rules that keep this honest

1. **No self-approval.** The agent that wrote the code does not review it, test it, or
   authorize its release. This is NIST AC-5 / CM-5, and it is enforced by CODEOWNERS and
   branch protection, not by good intentions.
2. **Evidence or it didn't happen.** A gate checklist item is satisfied by a linked
   artifact — a workflow run, a SARIF file, an attestation, a signed approval. Prose
   claiming the work was done is not evidence.
3. **Every retro action becomes a diff.** A retrospective that ends in a list of
   intentions has failed. It ends in a PR against `docs/`, `.github/workflows/`, or
   `.claude/agents/`. See `docs/09-retrospective-and-improvement.md`.

## Before this is real

Several controls live in GitHub settings, not in files — a repository cannot configure
its own branch protection. **Until you complete `SETUP.md`, the separation-of-duties and
release-authorization controls are documentation, not controls.** That gap is the single
most common way a governance program ends up with a clean-looking repo and no actual
assurance.

## Where to start reading

- New to the process → `docs/00-overview.md`
- "Who does what" → `docs/01-roles.md`
- "What must be true before I code" → `process/gates/g1-ready.md`
- "What constrains the agents" → `docs/11-ai-agent-controls.md`
- "How does this satisfy an auditor" → `docs/compliance/nist-800-53-control-map.md`
- "How do I change the process itself" → `docs/09-retrospective-and-improvement.md`
- **"How do I turn the controls on" → `SETUP.md`**

## Honest limits

Written down so nobody discovers them during an assessment:

- **The workflows are structural skeletons.** Every `run:` step marked `ADAPT:` needs your
  toolchain. The gate structure, the fail-on-new-not-total decision, and the permission
  scoping are the real content; the shell commands are placeholders.
- **800-53 coverage is SDLC-scoped.** A full system authorization also needs operational,
  physical, and personnel control families that live outside this repo. The control map
  marks what is partial — read the 🟡 entries as the honest ones.
- **Prompt-level agent controls are advisory.** Only the tool grants, hooks, and branch
  protection hold against a confused or adversarial model.
- **`bootstrap.sh` and `sync-platform.sh` are now verified end to end** against a real
  clone — nine defects were found and fixed on their first execution (L0011). The remaining
  untested surface is the non-`node` stack profiles and `release.yml`.
- **Agent write-scope by role is not enforceable today.** Claude Code grants tool *types*,
  not path scopes, and the hook payload carries no agent identity (probed and verified
  2026-08-07). "The product-owner agent cannot write source" is a prompt instruction, not a
  control — caught downstream by non-author review rather than prevented. Tracked as
  **POAM-001**. The consequential boundaries — approve, merge, push, production, secrets —
  *are* enforced.
- **A one-person team cannot fully satisfy AC-5.** Record the role compression in the SSP
  with its compensating control rather than describing a team that does not exist.
