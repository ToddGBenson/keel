# Self-review — TheHub #61064 (keel PR #166)

Mode: solo (POAM-008). Written under the operator decision of 2026-11-04: the agent that
builds a binnacle or keel pull request writes its self-review record.
PR: #166   Date: 2026-11-04
Author: Claude Opus 5.5 story builder (AI-authored). This record was written by the SAME
builder session, after a second full read of the diff. It is not a cold read by another session.
Opened: 2026-11-04T16:35Z   Reviewed: 2026-11-04T16:45Z   Cooling-off: none (same session)
verdict: pass

## Verified independently

- The test commit was run against the old hook and settings. `test/hook-bypass-corpus.test.py` exits 1 with "guard-bash.sh is not bound to the PowerShell tool (matchers: ['Bash'])", and the selftest binding check prints NOT BOUND for PowerShell.
- The 22 PowerShell must-block spellings were sent to the OLD hook as PowerShell payloads, and 20 were allowed. KB-145 (--f`orce) and KB-162 (gh release create with an escaped quote) were already blocked, so they are guards, not evidence.
- On the new hook, the same 22 must-block and 14 must-allow probes all came out as expected. The allow cases include a GET of pending_deployments with irm and -Headers @{...}, a GraphQL query with no mutation, and the existing gh api contents write to a feature branch.
- `scripts/validate-platform.py` passes. Hooks, settings, corpus and selftest are byte-identical between keel and binnacle (checked with cmp).

## Agent findings

- No three-pass agent review was run for this record, and no independent reviewer comment exists on this PR.

## Not verified

- The full `selftest.sh` and `hook-bypass-corpus.test.py` did not finish locally. The host was loaded and ran about 20 s per hook call, so the CI run on this PR is the evidence for the whole suite.
- I did not confirm against Claude Code's source that the PowerShell tool's PreToolUse payload uses tool_name "PowerShell" and tool_input.command. I inferred it from the tool's schema in this session. The hook does not read tool_name, so only the matcher depends on the name.
- That Claude Code reads the matcher "Bash|PowerShell" as an exact list of names is per its documentation. I did not test it in a live session.

## Cold-read notes

- The PowerShell view runs for every command, Bash ones included. It drops backticks, turns { } and , into spaces, and strips Start-Process and -Arg* tokens. It can only add blocks, but a Bash command whose text turns into a blocked call after those rewrites would now be refused.
- curl writes to /releases, /pulls/N/merge and the other gh-protected endpoints are now refused by the hook under Bash too. Before, only the Bash(curl:*) permission rule stopped them. curl or cmdlet writes to /contents/ and /merges are refused outright, even for a feature branch. Use gh api for those.
- Windows PowerShell 5.1 aliases curl to Invoke-WebRequest. A `curl -Headers ...` GET to a deployment-review endpoint is read with curl's flags, where -Head looks like a body flag, so it is refused. This is a known false positive.
- `(Get-Content -Encoding utf8 FILE)` in a GraphQL body takes "utf8" as the file, and the call is refused because the file is unreadable. This is also a known false positive.
- The corpus now runs every guard-bash entry through both tools, which doubles its CI time.

## Residual risk accepted

- The reviewer is the same model family, the same session and the same GitHub identity as the builder. This is a self-review, not an independent review, and it is not an approval.
- The permission deny/ask/allow lists in settings.json are still spelled Bash(...) only, so the hook alone enforces the rules for PowerShell. Splatted arrays (gh @a) and .NET HTTP clients stay open entries until TheHub #61039.
