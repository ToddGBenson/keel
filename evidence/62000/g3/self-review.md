# Self-review — TheHub #62000 (the hooks are best-effort guidance until the allowlist rebuild)

Mode: solo (POAM-008); agent self-review, pending the independent review before merge
PR: #191   Author: Claude Sonnet 5.5 (AI-authored)   Date: 2026-11-18
verdict: pass
Opened: 2026-11-18 02:24:58 UTC (first commit; PR opened 02:25:12Z)   Reviewed: first self-review at the round-1 fix commit 02:32:21Z; this record last updated for round 2 at 02:43:13 UTC
Cooling-off: none (same session). Measured: round-1 independent review posted 02:29:25Z, round-1 fix commit 02:32:21Z (about 3 minutes later), round-2 independent review posted 02:40:34Z, round-2 fix written at 02:43:13 UTC (about 18 minutes after the first commit). The independent review is the compensating read.

Docs only. `docs/11-ai-agent-controls.md` listed each hook rule as "Hook-enforced: a denylist
over command text" but never said plainly, before the table, that a hook can be re-worded around
and is not the boundary. A reader of this public template could take the table as a security
boundary. Operator decision 2026-11-17: rebuild the hooks as allowlists over a parsed command
later (TheHub #60944), and meanwhile say the hooks are best-effort.

The first head (05c1422) replaced one overclaim with another: it named branch protection, a
sandbox and least-privilege credentials as the boundary. The independent review blocked it
because none of the three holds as stated today. This record covers the fix round.

Round 2: the second independent review (Opus, on head 0845f3f) blocked on three points, fixed
here with new commits. B1: the tool grant was called "the one column that limits what the
agent can attempt", and AIC-2 said `developer` has no approval capability and `product-owner`
cannot write source. Read from `.claude/agents/*.md`, 14 of 15 agents are granted `Bash` (only
`ux` is not), `Bash` runs `gh`, and `developer` and `product-owner` both have `Bash` and
`Write`/`Edit`, so the claim was false; the sentence, the AIC-2 parenthetical and the AIC-2 and
AIC-3 approve/merge/push tool-grant marks now say so. Nits N1-N4 applied. B2: the timestamps
on this record were wrong (a review time later than the commit that holds it); they are now
the measured ones above, from `git log` and the GitHub API. B3: `docs/compliance/ai-inventory.md`
marked "Cannot approve a PR" and "Cannot merge, force-push, or push to `main`" as Enforced by
`guard-bash.sh` + branch protection; those two status cells now agree with `docs/11`
(Hook-enforced, a denylist over command text, until agents have their own GitHub identity,
TheHub #61039). Nothing else in that file changed. Files that read `ai-inventory.md`:
`test/agent-evals-record.test.py` (AIC-12 paragraph only) and `scripts/validate-platform.py`
(the agent table in section B, which was not touched); both re-run, exit codes in the PR body.
Follow-ups F1-F5 from that review (stale `enforce_admins` claims in docs/13, the CIS and NIST
maps, AIC-10 signed commits, the AC-5 assessment test) are not fixed here; the PO files them
under TheHub #62001.

## The change

- `docs/11-ai-agent-controls.md`: a new subsection "Read this first: the hooks are best-effort
  guidance, not the boundary" at the top of `## The controls`, before AIC-1 and every table.
  It says hooks are a denylist over command text that can be re-worded around, and that what
  bounds an agent is its GitHub credential. Branch protection restricts direct pushes,
  force-pushes and deletion and pins required checks to a GitHub App, but does not stop a merge
  (no approving review is required, the agent's identity is the owner's, `enforce_admins` is
  off). Least-privilege credentials are the target (TheHub #61039). The sandbox is not
  configured by this repo. The allowlist rebuild is planned (TheHub #60944).
- Fix round, same file: AIC-2 no longer calls branch protection the strongest layer without
  qualification; the *May approve* and *May push/merge* rows no longer say branch protection
  blocks self-approval or backs the hook, and their strength reads "Hook-enforced" instead of
  "Enforced"; the *Enforcement summary* paragraph no longer says a branch-protection mark holds
  under adversarial conditions. No table row was added or removed.
- `README.md`: the bullet is reworded, not qualified, so it no longer says the hooks hold
  against an adversarial model.
- `.claude/commands/self-review.md`: the closing paragraph said `enforce_admins` is still on; it
  is off on `main`, so it now says so.
- Nothing under `.claude/hooks`, `.claude/settings.json`, `ci/`, `.github/` or `test/` changed.
  No bypass input string added.

## Verified independently

- Live branch protection on `main` was read in this fix round with read-only `gh api` calls
  (the earlier head's record did not do this, and the claim that failed was exactly that one):
  `required_approving_review_count` is 0, `enforce_admins` is false, the two required checks are
  pinned to one GitHub App, `strict`, linear history and conversation resolution are on,
  force-push and deletion are off, and the repository has no rulesets. The repository
  permissions of the agent's `gh` identity include `admin: true`. Every factual claim in the
  new section was checked against that output.
- `.claude/settings.json` was read: it carries `permissions` and `hooks` (plus `$schema`) only,
  so no sandbox is configured in this repo.
- Files that read the changed docs: `README.md` and `.claude/commands/self-review.md` are read by
  `test/self-review-docs.test.py`; `docs/11-ai-agent-controls.md` is named by
  `test/agent-evals-record.test.py`. Each was run as a plain process (commands and exit codes in
  the PR body), with `scripts/validate-platform.py` and `scripts/test-manifest.py check`.
- `docs/11` is platform_owned in `platform/MANIFEST.yml` with no per-file hash; `README.md` is
  project_owned.

## Agent findings

- The three fresh-agent passes (developer, security-engineer, qa-engineer) were NOT run on this
  XS docs-only change. The independent Opus review of the first head stands in for them and its
  four blocking findings and three follow-ups are fixed in this round:
  - B1-B3 (false merge/approve claim, unbacked sandbox and least-privilege claims, the
    "rests on guard-bash.sh alone" qualifier): section rewritten, qualifier dropped.
  - B4 (README bullet contradicting itself): bullet reworded.
  - F1, F2, F3 (Enforcement summary, AIC-2 and the *May approve* row, `self-review.md`
    `enforce_admins` text): fixed in this PR.

## Not verified

- The three passes above. UNVERIFIED, not passed.
- That a fork has the branch protection, App pinning or sandbox it would need. The section
  states what this repo has today; it does not assert a fork's settings.
- `test/hook-bypass-corpus.test.py` and `.claude/hooks/selftest.sh` were not run: neither reads
  the files changed, and the change touches no hook.
- `docs/13-solo-operation.md` still says "`enforce_admins` stays true". It is outside this
  story's scope and is not changed here; it is the same stale claim and should be fixed
  separately.

## Cold-read notes

- The story asks for the section "BEFORE the controls table". The page has several tables; the
  enforcement table sits mid-AIC-3, where a separate hook story (TheHub #61391) edits rows. I put
  the section ahead of AIC-1 so it precedes every table and cannot touch the same lines.
- What I did not want to look at: the first head claimed a boundary I had not checked against
  live settings. Reading the protection output showed all three "boundary" items were wrong or
  unbacked. The rewrite states the thin boundary rather than a reassuring one.

## Residual risk accepted

- Single-identity review. No independent human read this diff. The reviewer reads it before merge.
