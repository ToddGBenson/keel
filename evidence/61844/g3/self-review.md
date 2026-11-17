# Self-review — TheHub #61844 (guard-write.sh fails closed, as guard-bash.sh does)

Mode: solo (POAM-008); agent self-review, pending the independent review before merge
PR: #186   Pair: binnacle #84   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-17
verdict: pass

TheHub #61794 made guard-bash.sh fail closed and left guard-write.sh as a follow-up. That hook had
the same three defects. The worst was real: with `printf ... | grep -q` under pipefail, a Write or
Edit whose content held a credential or a private key header followed by ~400 KB was ALLOWED,
with jq and with the python fallback. grep -q exited at its first match, the writer died of
SIGPIPE, the pipeline returned 141, and the `if` read the match as "no match".

## The change

guard-bash.sh's wrappers, fault file with sentinel, and EXIT trap, copied into guard-write.sh
(only the wrappers it calls: grep, cat, jq, python3, python). The grep wrapper drops -q and discards
output, so grep drains its input, and 141 counts as success. A helper's real error goes to the
fault file and turns an allow into a block. Every exit code but 0 and 2 is a block. `type -P`
replaces `command -v`, which would report the new wrapper functions even with no binary installed.
The python fallback calls the wrapper by name, so a failing interpreter is recorded.

## Verified independently

- **Red first:** the new test/hook-write-fail-closed.test.py against main c7ba09e: 74 of 96 checks
  failed. Twelve were padded content allowed (3 credential shapes x Write/Edit x jq/python). The
  rest were a failing grep, cat, jq or python3 (exit 2 or SIGKILL) letting must-block writes
  through, and an injected exit 1, exit 127, unbound variable, or emptied or removed fault file
  allowing a write.
- **Green after:** 96 passed, 0 failed. With no fault, each must-block write is blocked by its rule
  (not as an internal error) and a harmless write is allowed, in both parser modes.
- **No regressions:** selftest 305 passed / 0 failed; bypass corpus 224 entries, 804 hook runs,
  0 failed; hook-fail-closed.test.py all passed; `./keel check` green in a capped python:3.12-slim
  container; shellcheck v0.10.0 at CI's `-S warning` clean (one SC2120 disabled with its reason).

## Not changed, on purpose

- With neither jq nor python, the hook still skips content scanning and allows, saying so (the
  2026-08-07 decision: CI secret scanning is authoritative). That is a documented fail-open, not a
  helper failure. The evidence-path rule still runs only once a path is parsed. Changing it is a
  policy decision, not this story.
- PATH is not pinned here either. That is TheHub #61843, for guard-bash.sh first.

## Not verified

- Git Bash on Windows was not exercised.

## Residual risk accepted

The no-parser fail-open above.
