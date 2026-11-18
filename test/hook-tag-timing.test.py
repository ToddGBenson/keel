#!/usr/bin/env python3
"""
guard-bash.sh's release-tag guard costs about the same per command as a one-line command.
Refs: TheHub #61972

Review of keel #192, the final round: a process per refspec (`tag_versionish` ran printf | grep)
made 300 `git push origin feat` lines take 81 s on Git Bash (main: 7 s), and `cmd /c` was read
twice per level, so seven levels took 82 s. A hook past Claude Code's 60 s timeout ALLOWS the
command, so slowness is a fail-open (TheHub #61939).

The bound is RELATIVE, measured on the same machine in the same run: each case must take at most
4 times the same hook's time for a one-line command (best of 3), plus 1 s.

    python test/hook-tag-timing.test.py
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


def timed(cmd, tool="Bash"):
    payload = json.dumps({"tool_name": tool, "tool_input": {"command": cmd}}).encode()
    t = time.perf_counter()
    r = subprocess.run(["bash", str(HOOK)], input=payload, capture_output=True, cwd=ROOT, timeout=600)
    return r.returncode, time.perf_counter() - t


base = min(timed("git push origin feat")[1] for _ in range(3))
limit = 4 * base + 1.0
rc, took = timed("\n".join(["git push origin feat"] * 300))
check(f"300 `git push origin feat` lines: {took:.2f} s, within 4x one line ({base:.2f} s) + 1 s = {limit:.2f} s",
      took <= limit and rc == 0, f"rc={rc}")
rc, took = timed("cmd /c " * 7 + "echo hi", "PowerShell")
check(f"PowerShell `cmd /c` nested 7 times: {took:.2f} s, within {limit:.2f} s", took <= limit and rc == 0, f"rc={rc}")

print()
if failures:
    print(f"{len(failures)} FAILED")
    sys.exit(1)
print("all passed")
