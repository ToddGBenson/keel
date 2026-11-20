#!/usr/bin/env python3
"""
guard-bash.sh judges a long heredoc about as fast as a one-line command. Refs: TheHub #61987

Review of keel #198, round 4: the container word judge forked a subshell per word, on two views,
even when the text named no container engine. A 300-line heredoc commit took 8.5 s on a fast
Linux host (main: 0.13 s) and ran past 200 s on Windows under load. A hook that passes Claude
Code's 60 s timeout ALLOWS the command, so slowness is a fail-open (TheHub #61939).

The bound is RELATIVE, measured on the same machine in the same run: the same hook's time for a
one-line command (best of 3) is the baseline. A 300-line heredoc with no engine word must take
at most 4 times that, plus 1 s. Fast CI forks cannot hide a per-line cost that way, and a slow
host does not fail it for being slow.

    python test/hook-heredoc-timing.test.py
"""
import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOOK = ROOT / ".claude" / "hooks" / "guard-bash.sh"
failures = []


def check(name, cond, detail=""):
    print(f"  [{'ok' if cond else 'FAIL'}]   {name}" + ("" if cond else f" {detail}"))
    if not cond:
        failures.append(name)


def timed(cmd):
    payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}}).encode()
    t = time.perf_counter()
    r = subprocess.run(["bash", str(HOOK)], input=payload, capture_output=True, cwd=ROOT, timeout=300)
    return r.returncode, time.perf_counter() - t


def heredoc(lines):
    body = "".join(f"Line {i}: the hook reads the words (x) and $(y) here, then `z`\n" for i in range(lines))
    return "git commit -F - <<'EOF'\nfix: a long message\n\n" + body + "EOF"


base = min(timed("git status")[1] for _ in range(3))
limit = 4 * base + 1.0
rc, took = timed(heredoc(300))
check(f"a 300-line heredoc with no engine word is decided in {took:.2f} s, within 4x a one-line command ({base:.2f} s) + 1 s = {limit:.2f} s",
      took <= limit, f"rc={rc}")
check("... and it is allowed (prose in a commit message)", rc == 0, f"rc={rc}")
rc, took = timed(heredoc(300).replace("the hook reads", "run docker compose ps, then"))
check(f"the same heredoc naming docker on every line: {took:.2f} s, within {limit:.2f} s (a heredoc fed to git is text)",
      took <= limit and rc == 0, f"rc={rc}")

print()
if failures:
    print(f"{len(failures)} FAILED")
    sys.exit(1)
print("all passed")
