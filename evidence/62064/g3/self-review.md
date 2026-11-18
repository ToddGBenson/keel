# Self-review — TheHub #62064: pr-pick judges the head that has waited longest first

PR: (keel; binnacle pair: #100)   Author: Claude Opus 5.5 (AI-authored)   Date: 2026-11-18
Story: pr-pick judged the newest pull request first, one head per run (about 20 minutes a run).
Every push to a higher-numbered PR jumped ahead of an older unjudged head and starved the merge
train: keel #189 waited 30+ minutes on 2026-11-18. Judge the oldest unjudged head first.

## The change

`ci/scripts/pr-pick.sh` lists the candidates as before (same-repository heads with a merge
ref, never a fork's or the base branch's). Then:
- it fetches each candidate's `refs/pull/<n>/head` at depth 1 into a scratch repository;
- it orders the candidates by the head commit's committer time, oldest first, breaking ties by
  pull request number. A head that moved between `ls-remote` and the fetch sorts last.
- If the times cannot be read, the order is the pull request number, oldest first.

Skipping already-judged heads, PR_PICK_LIMIT, the moved-head refusal and the checkout are
unchanged. It still never calls the GitHub API.

## Verified independently

- `test/pr-pick.test.py`: the fixture gives commits distinct, increasing committer times. The
  first-pick expectations now read oldest first. New cases: a newer push to #12 does not jump
  #11's older unjudged head, and an old head on a higher-numbered PR (#20) is judged first.
  At origin/main, 8 checks fail; here, all pass.
- shellcheck clean.

## Not verified

- On Concourse. The extra fetch is a depth-1 fetch of each open PR head over the same deploy key.
  On GitHub that is a few seconds for a handful of PRs.
- The optional "ready to merge first" ordering (an approved PR or a `train` label) is not
  implemented: it would need the GitHub API, which this task does not call.
