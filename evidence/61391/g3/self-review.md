# Self-review — TheHub #61391 (guard-write.sh on every write tool)

Mode: solo (POAM-008); agent self-review, pending the independent review before merge
PR: #195   Pair: binnacle #89   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-18
verdict: pass

guard-write.sh was bound to `Write|Edit`. Its evidence rule (AU-9) and secret rules (AIC-5) never
ran for a NotebookEdit or a MultiEdit. Binding alone would not have fixed that. The hook read only
`file_path` and `content`/`new_string`. A NotebookEdit carries `notebook_path` and `new_source`, and
a MultiEdit its text in `edits[].new_string`, so the path read empty and the hook allowed the write
unread. This story was held until #186 merged, because the fix rewrites the extractor lines #186
changed.

## The change

- **settings.json** binds guard-write.sh to `Write|Edit|MultiEdit|NotebookEdit`. MultiEdit is not in
  every Claude Code version; a matcher for a tool that does not exist costs nothing.
- **The extractor**, in both the jq and python branches, reads the path from `file_path` or
  `notebook_path`. It reads the content from all new text the call carries: `content`, `new_string`,
  `new_source`, and every `edits[].new_string`, joined by newlines. `old_string` is never read
  (the 2026-08-07 rule). The fail-closed wrappers from #186 are unchanged around it.
- **test/hook-bypass-corpus.test.py**
  - The binding check now covers guard-write.sh for every tool in WRITE_TOOLS.
  - Its jq shim knows the new filters. It gives the same output as real jq on a NotebookEdit plus
    MultiEdit payload, checked here.
  - Four corpus entries (class write-tool): a cloud key in a notebook cell, generated evidence
    through NotebookEdit, a credential in a MultiEdit, and generated evidence through MultiEdit.
- **selftest.sh** checks the binding for all four tools, and adds 4 must-block and 2 must-allow
  payload cases.
- **docs/11-ai-agent-controls.md** states which write tools the guard covers, and what it does not:
  shell writes, which are guard-bash.sh's ground, and MCP tools that write files.

## Verified independently

- **Red first, binding:** the corpus against main 7d4c7fb's settings.json refused to run. guard-write.sh
  is not bound to MultiEdit or NotebookEdit.
- **Red first, binding alone:** settings fixed, the hook not changed. The corpus then ran, and 6 runs
  failed: KB-225, KB-226 and KB-227 were ALLOWED in both parser modes. KB-228 (MultiEdit to a .sarif)
  was already blocked, because its file_path was readable. A green binding check over a guard that
  still allows is exactly what this story must not ship.
- **Red first, selftest:** the new cases against main's hook and settings gave 335 passed and 5 failed.
  The 2 bindings were missing and 3 payloads were allowed.
- **Green after:**
  - corpus 228 entries, 812 hook runs, 0 failed, 32 open (unchanged);
  - selftest 340 passed / 0 failed;
  - hook-write-fail-closed and hook-fail-closed all passed;
  - `./keel check` green in a capped python:3.12-slim container, and validate-platform passes;
  - shellcheck v0.10.0 `-S warning` clean; pinned gitleaks v8.18.4: no leaks.

## Not verified

- Git Bash on Windows was not run. Nothing in the change depends on the shell. On that host the
  python branch is the live one when there is no jq, and it takes the same keys.
- A NotebookEdit `new_source` given as a list of lines (not a string) is not scanned. Claude Code
  sends a string. The cell is skipped silently, not blocked.

## Residual risk accepted

Shell and MCP writes, listed in the docs row, and the list-shaped `new_source` above.
