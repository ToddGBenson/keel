# Self-review — TheHub #62000 (the hooks are best-effort guidance until the allowlist rebuild)

Mode: solo (POAM-008); agent self-review, pending the independent review before merge
PR: #191   Author: Claude Sonnet 5.5 (AI-authored)   Date: 2026-11-18
verdict: pass
Opened: 2026-11-18 02:24 UTC   Reviewed: 2026-11-18 02:40 UTC (fix round)   Cooling-off: none, 16 minutes (same session; the independent review is the compensating read)

Docs only. `docs/11-ai-agent-controls.md` listed each hook rule as "Hook-enforced: a denylist
over command text" but never said plainly, before the table, that a hook can be re-worded around
and is not the boundary. A reader of this public template could take the table as a security
boundary. Operator decision 2026-11-17: rebuild the hooks as allowlists over a parsed command
later (TheHub #60944), and meanwhile say the hooks are best-effort.

The first head (05c1422) replaced one overclaim with another: it named branch protection, a
sandbox and least-privilege credentials as the boundary. The independent review blocked it
because none of the three holds as stated today. This record covers the fix round.

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
