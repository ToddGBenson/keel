# Self-review — TheHub #61972 (an agent never pushes a release tag)

Mode: solo (POAM-008); agent self-review, pending the independent review (Fable) before merge
PR: #192   Pair: binnacle #87   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-17
verdict: pass

A v* tag starts a release: release.yml signs as "release.yml@refs/tags/TAG". The hook blocked
`gh release create` and the /releases endpoint, but not the tag itself. On main an agent could run
`git push origin v1.2.3`, `git push --tags`, or `gh api repos/O/R/git/refs -f ref=refs/tags/v9`.

## The change (round 1, after Fable 5.2's BLOCK on keel #192 / binnacle #87)

The first version matched the command line with regexes. The review found both misses and false
blocks: git accepts any unique prefix of a long option, a v-word in a commit message or a redirect
target is not a refspec, and `git stash push` is not a push. guard-bash.sh now splits each view of
the command into shell words, with quotes honoured and `$(...)` and backticks as word breaks, and
judges only the arguments that name refs:

- **git push**
  - `--tags`, `--follow-tags` and `--mirror` by unique prefix.
  - A refspec naming `refs/tags/...`, a release-shaped bare name (v<digits> with dots, or v and a
    capital), or `tag v...`.
  - Any refspec it cannot resolve from the text (a variable, a substitution, a glob) is refused:
    fail-closed.
  - `push.followTags`, `remote.<n>.push` or `remote.<n>.mirror` given with `-c` or `--config-env`.
- **git send-pack**, always.
- **git tag** creating a v* tag, or one named by a variable. This is the operator's decision on the
  story: creation is blocked too. Listing, `-d`, `-v` and non-v tags stay allowed.
- **git config** setting those three keys. `--get`, `--list` and `get`/`list` stay allowed.
- **gh api**: the endpoint is normalised first. A write to `git/tags` or `git/refs/tags/...` is
  refused, and so is a write to `git/refs` unless it carries exactly one literal
  `ref=refs/heads/<name>` (from `-f`/`--raw-field`, or `-F` without `@`) and no `--input`.
- The refusal text is the review's: "A v* tag is the ref a release is cut from, and cutting a release is the operator's decision. Push your branch and open a PR; after merge the operator creates the tag and dispatches release.yml."
- docs/11-ai-agent-controls.md has the row, matching this record.
- **#120's selftest case changed:** `git push --follow-tags origin feat` was must-allow, to show
  --follow-tags is not read as -f. It is now must-block, and `--no-follow-tags` is the must-allow
  case.

## Verified independently

- **Red first, round 1:** 37 new selftest cases (review classes, not its exact inputs).
  - Against the reviewed head 8c9d987: 366 passed, 29 failed. 24 bypasses were allowed: option
    prefixes, gh api query string and trailing slash, an unreadable or duplicate ref, refspec globs,
    -c remote.<n>.push/.mirror, --config-env, a tag in a variable, a PowerShell $-string, send-pack,
    vNext, and v* tag creation. 5 false blocks: `git config --get`/`get`, `git stash push -m v1`, a
    branch v2-migration, and a redirect to v1.log.
  - 10 corpus entries, class release-tag, KB-240..249. #196 holds KB-229..231. On 8c9d987: 40 of 844
    runs failed.
  - Against main 3e12e04: selftest 350 passed, 45 failed; corpus 40 failed.
- **Green after:** selftest 395 / 0; corpus 234 entries, 844 runs, 0 failed, 32 open;
  hook-fail-closed and hook-write-fail-closed all passed; `./keel check` green in a capped container;
  shellcheck v0.10.0 `-S warning` clean; pinned gitleaks: no leaks.

- **The review's exact inputs** (binnacle #87 comment), run against this head after the round was built:
  every must-fix, should-fix and "held" input blocked through both tools, plus the PowerShell-only
  forms, and every false positive allowed. 96 checks, 0 wrong.
- **Accepted gaps are open corpus entries** KB-250..252: GIT_CONFIG_* environment variables, an inline
  git alias, and a curl write to git/refs. Each fails the run once it is blocked.

## Not verified

- Git Bash on Windows was not run.

- Not read: `GIT_CONFIG_*` environment variables, a `remote.<name>.push` or `.mirror` set earlier and
  then a plain push, a git alias, a REST tag write sent by curl (TheHub #61973's curl path), and a
  release-shaped bare name outside the pattern (for example `v2-rc1`, which reads as a branch).

## The control is the hook alone, for now

**Tag rulesets do not exist yet**: GET rulesets returns `[]`. Until the rulesets script runs
(TheHub #61006), this hook is the only control on release tags. Branch protection does not cover
tags.

## Residual risk accepted

The gaps above, until #61006 lands server-side protection.
