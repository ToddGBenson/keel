---
description: Rank the open backlog, propose a coherent epic of 3-5 stories, and create it as sub-issues once a human approves
argument-hint: "[optional theme or constraint, e.g. 'focus on the sprint runner']"
allowed-tools: Read, Grep, Glob, Bash, Task
---

# Plan the next epic: `$ARGUMENTS`

**Skill:** `backlog-prioritization` — load it; it is authoritative for the method.
**Decision record:** ADR-0002. **Gate impact:** the epic becomes the G4 batching unit.

Delegate ranking to `product-owner` (value) and dependency/flow judgement to `delivery-lead`.

## Step 1 — read the backlog

```bash
gh issue list --state open --limit 100 \
  --json number,title,labels,createdAt,body \
  --jq '.[] | "\(.number)\t\([.labels[].name]|join(","))\t\(.title)"'
```

Classify each issue by kind and pull the ranking input **its intake route already recorded**
(the skill's "Rank from what you already have" table). Do not re-score.

- **Idea / story** — the RICE score recorded at G0. No RICE means it never passed G0: not
  eligible for planning, eligible for `/idea`. Say so rather than inventing one.
- **Defect** (`bug` label, filed via `bug.yml`) — the **severity recorded on the bug form**,
  then the data-loss/exposure flags, then scope of impact. Defects never pass G0 and never
  get a RICE score; **never back-fill one**. A defect with no recorded severity is not Ready —
  say so and route it to triage.
- **Security finding, compliance gap, EOL** — the SLA due date. These are constraints the plan
  fits around, not candidates ranked against features.

## Step 2 — rank within each kind, then group for coherence

Rank each kind on its own path, adjusted for dependency order, risk flags, and decay (see the
skill). **There is no common scale across kinds** — do not convert a severity into a RICE-like
number to merge the lists. Present them separately, state the path per item, and leave the
interleave to the human at approval.

Then find the **coherent** group — stories sharing a component, a data set, a user journey, or
a trust boundary. The top N by score is usually the wrong epic: a scatter of unrelated high
scorers produces five disconnected attack surfaces in one review, which is precisely what
batched verification is not for.

Three to five stories.

## Step 3 — check batch eligibility BEFORE proposing

Any story labelled `security-relevant` or `ai-relevant` is ineligible for batching and takes
G2 up front plus its own G4 (ADR-0002 D4).

Say this in the proposal. Do not quietly include a flagged story and let the gate catch it
later — the point of surfacing it now is that the human may want to reshape the group.

**Never suggest removing a flag to make a group eligible.** That is falsifying a triage
decision (PD-7), not an optimisation.

## Step 4 — propose, and STOP

Output the shape defined in the skill: the recommended epic with its shared surface named, a
table of stories with RICE and flags, batch eligibility, and the **deferred list with
reasons**.

Then stop and ask for approval.

Selection is a scope decision and scope stays human — this is the same boundary that keeps the
unattended runner out of G0/G1 (`docs/18` P2). Proposing is your job; committing is not.

## Step 5 — only after approval, create it

```bash
# 1. The epic issue.
gh issue create --title "[Epic] <name>" --label epic --body "<rationale + story list>"

# 2. Attach each story as a NATIVE sub-issue.
#    NOTE: the API takes the child's issue *id*, NOT its number. Passing the number
#    silently attaches the wrong issue or fails — verify the result, do not assume it.
CHILD_ID=$(gh api repos/{owner}/{repo}/issues/<child-number> --jq .id)
gh api repos/{owner}/{repo}/issues/<epic-number>/sub_issues -f sub_issue_id="$CHILD_ID"
```

Then confirm the relationship actually exists rather than trusting the exit code:

```bash
gh api repos/{owner}/{repo}/issues/<epic-number>/sub_issues --jq '.[].number'
bash scripts/check-batch-eligibility.sh <epic-number>
```

## What this does not do

- **No dates, velocity, points, or capacity.** An epic is a grouping, not an iteration.
- **Does not mark anything ready.** Each story still passes G1 on its own. Membership in an
  epic confers nothing — batch selection must not cross G1 for a dozen stories at once.
- **Does not close the loop.** After approval the normal flow resumes: `/refine <epic>` if the
  stories need decomposing, then `/ready` per story.
