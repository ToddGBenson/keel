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

## Round 2 (rescoped by the PO after the 2026-11-18 protection change)

The operator's `keel-release-tags` ruleset has an admin bypass, and the agents push with the
owner's admin credential, so for the agents this hook is still the only control on release tags
until TheHub #61039. The PO rescoped this story: fix the false positives first, then the cheap
bypasses; refuse what cannot be parsed; record the rest as gaps that #61039 closes. One review
round, then ship. Fable 5.2 reviewed 8316706 (BLOCK).

- **False positives (the first fix):** the guard read the masked and the PowerShell views, which
  keep heredoc bodies and comments or drop quotes, and it judged every word that said `git`. It
  now splits the command the way the shell that runs it does, and judges only the command word of
  each simple command. So a commit message, a PR body, `echo`, `grep`, a heredoc and a comment are
  text. A Bash payload is read the bash way and a PowerShell payload the PowerShell way. A
  payload that names no tool is a Bash one, because the PowerShell tool always sends tool_name.
  Shells, `eval`, `Invoke-Expression`, `cmd /c`, `pwsh -c`, `Start-Process` and a heredoc fed to
  a shell are judged as the command they run, nested up to 8 levels.
- **Cheap bypasses closed:**
  - the `tags/` shorthand;
  - a redirect before the refspec or the subcommand (`2>&1`, `>&2`, `&>`, `>|`);
  - backslash-newline, deleted as bash deletes it;
  - brace expansion and backticks, which are not literal;
  - `--attr-source` taking a value;
  - a non-literal subcommand or command word;
  - `xargs git`;
  - two levels of shell;
  - `git tag --sort/--format/--column` with a name;
  - `git config --comment`;
  - `git update-ref` writing a tag ref, or with `--stdin`;
  - `git fetch` writing a tag ref;
  - gh api short-flag clusters (`-iX`, `-fz=XGET`);
  - the endpoint by repository id, in any case, with a scheme, host, port or fragment.
- **Gaps, recorded by class (exact inputs are in binnacle #87's review):** a remote, followTags
  or include.path config written earlier and then a plain push; a v* destination that is not
  release-shaped pushed from an existing tag; GraphQL createRef with the name in a file. Also
  GIT_CONFIG_*, a git alias and curl, as before.
- **Evidence:** the review's round-2 inputs and the earlier ones, run through the hook with no
  tool, with Bash and with PowerShell: 270 checks, 0 wrong. Selftest: 17 failing on 8316706,
  415/0 here, and 415/0 with jq off the PATH. Corpus 884/0 (KB-253..259). No process per word:
  words are classified with nocasematch (the #62031 T1 lesson); a 300-command line takes 0.3 s.

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

Since 2026-11-18 keel has a `keel-release-tags` ruleset on `v*`, but it has an admin bypass, and
the agents' identity is the owner's admin account. binnacle has no tag ruleset. So for the agents
this hook is the only control on release tags until they have their own identity (TheHub #61039).

## Residual risk accepted

The gaps above, until the agents have an identity without admin rights (TheHub #61039).
