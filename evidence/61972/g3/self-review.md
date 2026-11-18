# Self-review — TheHub #61972 (an agent never pushes a release tag)

Mode: solo (POAM-008); agent self-review, pending the independent review (Fable) before merge
PR: #192   Pair: binnacle #87   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-17
verdict: pass

A v* tag starts a release: release.yml signs as "release.yml@refs/tags/TAG". The hook blocked
`gh release create` and the /releases endpoint, but not the tag itself. On main an agent could run
`git push origin v1.2.3`, `git push --tags`, or `gh api repos/O/R/git/refs -f ref=refs/tags/v9`.

## The change (guard-bash.sh, beside the push-to-main rule, the gh api write rules and gql_mutations)

- **git push** refuses a v<digit> tag by name or as `tag v1`. It also refuses any `refs/tags/v*` or
  `refs/tags/*` refspec, as source, as destination, `+`forced or `:`deleted, and the flags `--tags`,
  `--follow-tags` and `--mirror`.
- **push.followTags** is refused when given with `-c` or set with `git config`. Config keys are
  case-insensitive, and so is the match.
- **gh api** refuses any write to `git/tags` or `git/refs/tags/...`, and to `git/refs` when the `ref`
  field names `refs/tags/` or cannot be read (`--input`, `$(...)`).
- **GraphQL** `createRef` with `refs/tags/` is refused. It shares gql_mutations, so the same rule
  applies to curl.
- The refusal names the operator's path: the Keel-Rulesets-Release script, or a release.yml dispatch.
- docs/11-ai-agent-controls.md has a row, including what is not read.
- **#120's selftest case changes.** `git push --follow-tags origin feat` was a must-ALLOW case, kept
  to show that --follow-tags is not read as -f. It now pushes release tags, so it is must-block, and
  `--no-follow-tags` is the must-allow case.

## Verified independently

- **Red first:** the 27 new selftest cases against main 7d4c7fb (after #184, #186 and #190):
  selftest 338 passed, 20 failed. All 19 must-block cases were ALLOWED, including PowerShell, and so
  was #120's `--follow-tags` case, now must-block. The 8 must-allow cases passed: a branch push, --no-follow-tags,
  `git tag -l`, `git tag -l 'v*'`, `git fetch --tags`, a GET of git/refs/tags, a POST to git/refs for
  a branch, and a PowerShell branch push.
- **Green after:** selftest 358 passed / 0 failed. A first attempt placed the gh api git/refs check
  before `api_field` was defined, which blocked the branch-ref case. The red/green caught it, and the
  check now sits after the definition.
- **No regressions:** bypass corpus 224 entries, 804 hook runs, 0 failed. hook-fail-closed.test.py
  and hook-write-fail-closed.test.py all passed. `./keel check` green in a capped python:3.12-slim container. shellcheck v0.10.0
  `-S warning` clean. Pinned gitleaks v8.18.4: no leaks.

## Not verified

- Git Bash on Windows was not run.
- Not read: `GIT_CONFIG_*` environment variables, an earlier `remote.<name>.push` or `.mirror` setting,
  a git alias, and a REST tag write sent by curl. That last one is the curl path TheHub #61973
  rewrites, so it is left for that story.

## Residual risk accepted

The gaps above. Branch protection and rulesets on tags remain the server-side control.
