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
# Review of binnacle #87 at 7f6e00e5, round 4: every nested pwsh -c ran the judge (and its
# tokenizer process) again: 300 lines took 342 s on Git Bash (main 4.5 s), 30 lines 23 s.
for lines in (300, 30):
    rc, took = timed("\n".join(["pwsh -NoProfile -c Write-Host hi"] * lines), "PowerShell")
    check(f"{lines} nested `pwsh -NoProfile -c Write-Host hi` lines: {took:.2f} s, within {limit:.2f} s",
          took <= limit and rc == 0, f"rc={rc}")
rc, took = timed("\n".join(["cmd /c " * 7 + "echo hi"] * 3), "PowerShell")
check(f"3 lines of `cmd /c` nested 7 times: {took:.2f} s, within {limit:.2f} s", took <= limit and rc == 0, f"rc={rc}")
rc, took = timed("\n".join(["pwsh -NoProfile -c Write-Host hi"] * 60 + ["git push origin v1.2.3"]), "PowerShell")
check(f"60 nested pwsh lines and a tag push: refused in {took:.2f} s, within {limit:.2f} s",
      took <= limit and rc == 2, f"rc={rc}")

print()
if failures:
    print(f"{len(failures)} FAILED")
    sys.exit(1)
print("all passed")
