# AI System Inventory

**Owner:** AI Risk Officer · **Controls:** AI RMF GOVERN 1.6 · 800-53 CM-8, PM-5 ·
ISO 42001 A.4 · **Reviewed:** monthly

An organization that cannot enumerate its AI systems cannot govern them. This is the first
artifact an AI-focused assessor asks for, and the one most organizations cannot produce.

Two sections, deliberately separated — conflating them is the most common failure in AI
governance programs.

---

## Section A — AI in products we ship

| ID | System / feature | Owner | Tier | Model + version | Data touched | Eval suite | Last red-team | Last assessment | Monitoring |
|---|---|---|---|---|---|---|---|---|---|
| — | *No entries yet.* | | | | | | | | |

**Required per entry:** purpose · risk tier (Minimal / Limited / High) · model, version, and
provider · whether user data reaches the provider and under what contractual terms ·
whether that data trains anything (it must not, for anything non-public) · grounding and
retrieval sources · guardrails in place · human oversight point · eval suite location and
last run · last red-team date · monitoring status · AIA reference.

**Update triggers:** new AI feature · model or provider change · prompt change · grounding
data change · tier reassessment · red-team completion · decommission.

---

## Section B — AI used to build (the agents in this repo)

**Write scope is EXPECTED scope, not enforced scope.** See the enforcement note below the
table — this column describes what each role is instructed to write, and a violation is
detected at review, not prevented at the tool layer. Do not read it as a control.

| Agent | Purpose | Model | Tool grant (actual) | Expected write scope | Approval authority | Last eval |
|---|---|---|---|---|---|---|
| `product-owner` | Intake, refinement, acceptance | opus | Read/Write/Edit/Bash/Web | Issues, product docs | None | — |
| `architect` | Design, ADRs, control allocation | opus | Read/Write/Edit/Bash/Web | Docs only | Recommends (G2) | — |
| `developer` | Implementation | opus | Read/Write/Edit/Bash/Web | Source + tests | **None** | — |
| `security-engineer` | Threat models, control verification | opus | Read/Write/Edit/Bash/Web | Findings, threat models | Recommends (G2/G4); **blocks** | — |
| `qa-engineer` | Test strategy, verification | opus | Read/Write/Edit/Bash | Tests only | Recommends (G4) | — |
| `ai-risk-officer` | AI assessments, evals, red-team | opus | Read/Write/Edit/Bash/Web | Assessments, evals | Recommends (G2/G4); **blocks** | — |
| `delivery-lead` | Flow, retros, facilitation | opus | Read/Write/Edit/Bash | Process docs | None | — |
| `release-manager` | Change control, release readiness | opus | Read/Write/Edit/Bash | Release docs | Prepares G5; **human authorizes** | — |
| `compliance-officer` | Control map, assessments, POA&M | opus | Read/Write/Edit/Bash | Compliance docs | Assesses only | — |
| `tech-writer` | Documentation | opus | Read/Write/Edit/Bash | Docs only | None | — |

**Governing document:** `docs/11-ai-agent-controls.md` (AIC-1..12).

### Enforcement status of the write-scope column — read before relying on it

| Boundary | Enforcement | Status |
|---|---|---|
| Cannot approve a PR | `guard-bash.sh` + branch protection | **Enforced** |
| Cannot merge, force-push, or push to `main` | `guard-bash.sh` + branch protection | **Enforced** |
| Cannot touch production or handle secrets | `guard-bash.sh` + `settings.json` deny rules | **Enforced** |
| **Restricted to its expected write scope** | Role prompt only | ⚠️ **Prompt-enforced** |

**Verified 2026-08-07.** Claude Code grants tool *types* in agent frontmatter, not path
scopes; `settings.json` permissions are project-wide rather than per-agent; and the
`PreToolUse` hook payload was probed directly and contains **no field identifying the acting
subagent** (`cwd`, `session_id`, `tool_name`, `tool_input`, `permission_mode`, `prompt_id`,
`tool_use_id`, `transcript_path`). Per-agent path scoping is therefore not currently
implementable at any enforcement layer.

**Compensating controls (detection, not prevention):** G3 review by a non-author · CODEOWNERS
routing on source paths · AI-authorship declaration naming the producing agent on every PR
(AIC-6) · the monthly agent audit sampling merged PRs for role/artifact mismatch (AIC-12).

**Tracked as POAM-001.** Upgrade to enforcement if a future Claude Code release exposes
agent identity to hooks. Recording this honestly is the point — a documented weak control
is defensible; an overstated one fails at the first real assessment.

**Verify against this table quarterly.** The Compliance Officer confirms each agent's actual
tool grant in `.claude/agents/` matches the "Tool grant (actual)" column. Drift there **is**
enforceable and is a genuine control failure — an agent definition edited to "unblock" a task
is the usual cause.

**Model versions.** Recorded in gate evidence bundles per AIC-8, so an assessor can determine
which model version produced any given artifact. A model upgrade is a **Normal change**:
impact assessed, behavior spot-checked against the regression set of past gate decisions,
human-approved, recorded.

**Agent evaluation (AIC-12).** Monthly regression run at
`evidence/ai-assurance/agent-evals/`. Did the security agent still catch the seeded findings?
Did the PO agent still reject untestable criteria? Did any agent attempt an action outside
its grant? Regressions are defects against the agent definitions, fixed through `/learn`.

---

## Decommissioned

| ID | System | Decommissioned | Data disposition | Records retained until |
|---|---|---|---|---|
| — | — | — | — | — |

Removal is planned work, not deletion: data disposal, user notice, dependent systems, and
retention of records for the audit period (MANAGE 4.2).
