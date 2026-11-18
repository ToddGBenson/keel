# Self-review — TheHub #62000 (the hooks are best-effort guidance until the allowlist rebuild)

Mode: solo (POAM-008); agent self-review, pending the independent review before merge
PR: #PENDING   Author: Claude Sonnet 5.5 (AI-authored)   Date: 2026-11-18
verdict: pass

Docs only. `docs/11-ai-agent-controls.md` listed each hook rule as "Hook-enforced: a denylist
over command text" but never said plainly, before the table, that a hook can be re-worded around
and is not the boundary. A reader of this public template could take the table as a security
boundary. Operator decision 2026-11-17: rebuild the hooks as allowlists over a parsed command
later (TheHub #60944), and meanwhile say the hooks are best-effort.

## The change

- `docs/11-ai-agent-controls.md`: a new subsection "Read this first: the hooks are best-effort
  guidance, not the boundary" at the top of `## The controls`, before AIC-1 and before every
  table. It says: hooks are best-effort guidance, a denylist over command text that can be
  re-worded around; the boundary relied on is branch protection with App-pinned required checks,
  the sandbox, and least-privilege credentials (separate agent identity planned, TheHub #61039);
  the allowlist rebuild is planned (TheHub #60944). It defines how to read "Hook-enforced" and
  "Enforced" in the table, so no legend row had to change. No table row is edited.
- `README.md`: one sentence appended to the existing bullet that said "Only the tool grants,
  hooks, and branch protection hold against a confused or adversarial model", pointing at the
  section. That bullet is the existing claim that hooks are a boundary.
- Nothing under `.claude/`, `ci/`, `.github/` or `test/` changed. No bypass input string added.

## Verified independently

- Which files read `docs/11-ai-agent-controls.md`: grep of test/ and scripts/ finds only
  `test/agent-evals-record.test.py` (names it in a docstring). `README.md` is read by
  `test/self-review-docs.test.py`. Each was run as a plain process and exited 0 (commands and
  exit codes are in the PR body). `scripts/validate-platform.py`, `scripts/test-manifest.py check`
  and `scripts/validate-manifest.py` also exited 0.
- `docs/11` is platform_owned in `platform/MANIFEST.yml` and has no per-file hash; nothing in the
  tooling needed updating. `README.md` is project_owned.
- The section's claims were checked against the repo: `test/hook-bypass-corpus.yml` exists and
  holds the open entries the section cites; the AIC-2 text already ranks branch protection as the
  strongest layer; TheHub #61039 is already cited in the table rows.

## Not verified

- The three fresh-agent passes (developer, security-engineer, qa-engineer) were NOT run. This is
  an XS docs-only change and the independent review is the reviewer's. UNVERIFIED, not passed.
- That the sandbox and App-pinned required checks are configured as the section says in every
  fork. The section names them as the boundary relied on; it does not assert a fork has them.
- `test/hook-bypass-corpus.test.py` and `.claude/hooks/selftest.sh` were not run: neither reads
  the files changed, and the change touches no hook.

## Cold-read notes

- The story asks for the section "BEFORE the controls table". The page has several tables; the
  enforcement table sits mid-AIC-3, where Laptop B will edit rows for TheHub #61391. I put the
  section ahead of AIC-1 so it precedes every table and cannot touch the same lines.
- The README pointer is a second statement of the same claim; it adds a pointer, it does not
  reword the existing sentence, so the README still says hooks hold against an adversarial model.
  That sentence is now partly at odds with the new section. I left it, because rewording a
  project-owned claim is outside "one line pointer", and flag it for the PO.

## Residual risk accepted

- Single-identity review. No independent human read this diff. The reviewer reads it before merge.
