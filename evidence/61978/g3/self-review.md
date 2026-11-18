# Self-review — TheHub #61978 (b, c) and #62016 (both parsers give the same verdict)

Mode: solo (POAM-008); agent self-review, pending the independent review before merge
PR: #196   Pair: binnacle #90   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-18
verdict: pass

Part (a), pinning guard-write.sh's PATH, waits for #189 (TheHub #61843) and is not in this change.

## (b) Parser parity, and #62016

Under the PATH pin a jq outside the system directories is not used, so the sed fallback is the
live parser on such hosts, and on any host with no jq at all (the operator's Windows host has
none). It differed from jq in two ways that each allowed a blocked command:

- **`\uXXXX` was left undecoded.** A command sent with its characters as JSON escapes, which is valid
  JSON, reached the rules as text no rule reads. jq decoded it. The JSON unescape step now decodes
  `\uXXXX` to UTF-8, joining a surrogate pair into one character. U+0000 becomes a space, and a
  malformed escape is kept as it was.
- **A payload it could not parse read as "no command"** (#62016). jq refuses such a payload and the
  wrapper makes that a block; the fallback exited 0. With nothing extracted, a payload that names a
  non-empty command, or that does not end in a closing brace, is now refused as an internal error.
  An empty command (`"command": ""`) is still allowed, as in jq mode.
- The extraction sed runs in the C locale, so a byte invalid in the host's locale cannot end the match.

The corpus gets a `payload_encoding` key: `unicode-escape` (every character of the command as a
\uXXXX escape) or `truncated` (the payload ends inside the command string). Three entries,
class payload-encoding, cover it: KB-229 self-merge escaped, KB-230 force push escaped, KB-231
self-merge truncated. Each runs in both parser modes and both tools.

## (c) The corpus does not skip a parser

- When symlinks fail (Windows without Developer Mode), the no-jq mode was SKIPPED, so the whole
  sed fallback could go unrun and the run still passed. The tools are now copied instead. If copying
  fails too, the run fails ("not run is not a pass"), checked by a control that makes both fail.
- On Windows, `shutil.which("bash")` can find WSL's launcher, which cannot see the checkout's Windows
  paths. `find_bash()` skips System32 and WindowsApps and falls back to the bash beside git.
- hook-path-pinned.test.py's `shutil.which("bash")` and its missed `PATH+=` belong to #189's test
  file, which is not on main. They are part (a).

## Verified independently

- **Red first:** the new corpus against main 3e12e04's hook gave 227 entries, 816 runs, 6 failed.
  KB-229, KB-230 and KB-231 were ALLOWED in the no-jq mode, on both tools. jq mode blocked them.
- **Green after:** 227 entries, 816 runs, 0 failed, 32 open (unchanged). selftest 330 / 0, and
  hook-fail-closed all passed.
- `./keel check` green in a capped python:3.12-slim container. shellcheck v0.10.0 `-S warning`
  clean. Pinned gitleaks v8.18.4: no leaks.

## Review round 1 (Fable 5.2 on 9cdef78 / 3bdc0b9, BLOCK; no regression against main)

Fable confirmed that empty, truncated and \u-escaped payloads now block, that escapes match jq,
and that nothing new is falsely blocked. These fixes are folded in, in the story's own scope
("refuse what it cannot parse"); all of them are in the no-jq branch:
1. **More than one "command" key** anywhere (a sibling or nested object, or a key ending in an
   escaped quote and `command`) is refused: sed and jq would read different ones. A key is a
   quoted `command` whose closing quote is unescaped and followed by a colon, so `\"command\"`
   inside a value is not one.
2. **Whitespace around the colon may include a newline:** the payload is read as one line (a
   newline outside a string is JSON whitespace).
3. **`\u0000` in the value** is refused.
4. **Timing:** a 1 MB command with no jq took 1.5 s on main and 1.4 s here (linux, mawk). It is
   the same, not a regression. Fable's Git Bash run passed 10 minutes, which is past the hook
   timeout, and a timeout allows. So with no jq, a payload **over 256 KB is refused** as too
   large to judge. hook-fail-closed's 400 KB must-block cases still block, now at once.
- **Nit:** the corpus test's Windows copy fallback copied `sed.exe` without its DLLs (exit 127),
  so the no-jq mode passed vacuously. It now copies the DLLs beside each tool and probes `sed`
  from the jq-less PATH, failing the run if it cannot start.
- **Corpus KB-232..235** (second-key, newline-colon, nul, oversize). At 9cdef78, KB-232 and
  KB-233 fail in both tools; KB-234 and KB-235 already blocked there by other paths and are
  regression guards. Corpus 832/0. Selftest 330/0 with jq and without.

## Review round 2 (Fable 5.2 on a1c060d / d3f320f, BLOCK; the scope stop)

- **(a) A new false positive, fixed.** With no jq, a command holding the literal text `\u0000`
  (an escaped backslash, then `u0000`) was refused; main and jq allow it. The refusal is now the
  decoder's own: it exits 3 when it decodes a real `\u0000` escape, and only that is refused.
- **(b) A fail-open main shares, fixed.** A key spelled with `\u` escapes (alone, or after a plain
  `"command":"ls"` decoy) was not seen. Keys are now counted with each letter in either spelling
  (Fable's pattern), and any key not spelled plainly is refused. An escaped backslash before the
  `u` is a different key and does not match.
- **(c) Nit:** the 256 KB cap counts bytes, under `LC_ALL=C`, not characters.
- **Evidence:** corpus KB-236 and KB-237 (an escaped key, with and without a decoy) plus a selftest
  allow case for the literal text. At a1c060d: corpus 4 runs fail, selftest without jq 1 fails.
  Here: corpus 840/0; selftest 331/0 with jq and without; hook-fail-closed passes.
- **Scope stop:** after this round, anything new that is not a regression is a documented gap.

## Not verified

- Git Bash on Windows was not run. The copy fallback and find_bash() are written for it and untested
  there. The \u decode is plain awk with `sprintf("%c")` in the C locale, which mawk, gawk and busybox
  awk handle the same way.

## Residual risk accepted

None new.
