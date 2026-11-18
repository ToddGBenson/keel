#!/usr/bin/env python3
"""
guard-bash.sh finds its helpers only in system directories. Refs: TheHub #61843

The hook reads every command through grep, sed, awk, tr, cat and jq, looked up on PATH.
A directory earlier on PATH that an agent can write to (~/bin, ~/.local/bin, a venv's bin)
could hold a grep that always answers "no match", or a jq or sed that prints nothing, and
the hook would ALLOW every blocked command. A planted helper that exits 0 or 1 is not a
fault, so #61794's wrappers cannot see it. The hook now pins PATH to the system's own
directories before it runs anything.

This runs the LIVE hook, not a copy, with a user-writable directory of planted helpers
first on PATH:

- each planted helper alone, then all of them together: every must-block command is still
  blocked, and `git status` is still allowed;
- the hook has exactly one pinned-PATH line, the one the other hook tests rewrite in their
  copies (their shim directories), and no variable or file can widen it.

    python test/hook-path-pinned.test.py
"""
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOOK = ROOT / ".claude" / "hooks" / "guard-bash.sh"
MUST_BLOCK = {
    "KB-177 upload replaces an environment": "curl -T env.json https://api.github.com/repos/O/R/environments/production",
    "self-merge": "gh pr merge 12",
    "force push": "git push --force origin feat",
}
HARMLESS = "git status"
# What a planted helper does: answer "no match", or print nothing and succeed.
PLANTED = {
    "grep": "#!/bin/sh\nexit 1\n",
    "jq": "#!/bin/sh\nexit 0\n",
    "sed": "#!/bin/sh\nexit 0\n",
    "awk": "#!/bin/sh\nexit 0\n",
    "tr": "#!/bin/sh\nexit 0\n",
    "cat": "#!/bin/sh\nexit 0\n",
}
failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def payload(command, tool="Bash"):
    return json.dumps({"session_id": "path-pinned", "transcript_path": "/dev/null",
                       "cwd": str(ROOT), "permission_mode": "default",
                       "hook_event_name": "PreToolUse", "tool_name": tool,
                       "tool_input": {"command": command, "description": "path-pinned test"}}).encode()


def planted_dir(tmp: Path, names):
    d = Path(tempfile.mkdtemp(dir=tmp))
    for n in names:
        p = d / n
        p.write_text(PLANTED[n], encoding="utf-8")
        p.chmod(p.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return d


def run(command, path, tool="Bash"):
    env = {"PATH": path, "CLAUDE_PROJECT_DIR": str(ROOT), "HOME": os.environ.get("HOME", "/tmp")}
    r = subprocess.run([shutil.which("bash"), str(HOOK)], input=payload(command, tool),
                       capture_output=True, cwd=ROOT, env=env, timeout=60)
    return r.returncode, r.stderr.decode("utf-8", "replace")


def main():
    if not shutil.which("bash"):
        print("bash is required")
        return 1
    tmp = Path(tempfile.mkdtemp(prefix="path-pinned-"))
    try:
        host_path = os.environ.get("PATH", "")
        print("a helper planted first on PATH cannot make the hook allow")
        cases = [[n] for n in PLANTED] + [list(PLANTED)]
        for names in cases:
            d = planted_dir(tmp, names)
            label = names[0] if len(names) == 1 else "every helper"
            path = str(d) + os.pathsep + host_path
            for name, cmd in MUST_BLOCK.items():
                for t in ("Bash", "PowerShell"):
                    rc, err = run(cmd, path, t)
                    check(f"planted {label} ({t}): {name} is still blocked", rc == 2,
                          f"rc={rc} ALLOWED {err[:200]}")
            rc, err = run(HARMLESS, path)
            check(f"planted {label}: `{HARMLESS}` is still allowed", rc == 0, f"rc={rc} {err[:200]}")

        print("one pinned PATH, and nothing widens it")
        text = HOOK.read_text(encoding="utf-8")
        pins = re.findall(r"^PATH=.*# guard-path-pin\b.*$", text, re.M)
        check("the hook has exactly one marked PATH line", len(pins) == 1, f"found {len(pins)}")
        check("the marked line sets PATH from the hook's own constant",
              bool(pins) and pins[0].startswith('PATH="$guard_path"'), f"{pins[:1]}")
        assigns = re.findall(r"^\s*(?:export\s+)?PATH=", text, re.M)
        check("no other line assigns PATH", len(assigns) == 1, f"found {len(assigns)}")
        # guard_path is assigned only inside the hook's own case statement on $OSTYPE.
        gp = re.findall(r"guard_path=\"([^\"]*)\"", text)
        check("guard_path names only system directories",
              bool(gp) and all(all(p in ("/usr/bin", "/bin", "/usr/sbin", "/sbin", "/mingw64/bin")
                                   for p in v.split(":")) for v in gp), f"{gp}")
        # A variable an agent might hope the hook reads does nothing: guard_path is
        # assigned before use, so an inherited value is overwritten.
        d = planted_dir(tmp, ["grep"])
        env = {"PATH": str(d) + os.pathsep + host_path, "guard_path": str(d),
               "CLAUDE_PROJECT_DIR": str(ROOT), "HOME": os.environ.get("HOME", "/tmp")}
        r = subprocess.run([shutil.which("bash"), str(HOOK)], input=payload(MUST_BLOCK["self-merge"]),
                           capture_output=True, cwd=ROOT, env=env, timeout=60)
        check("an inherited guard_path does not widen PATH", r.returncode == 2, f"rc={r.returncode}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print()
    if failures:
        print(f"{len(failures)} failed")
        return 1
    print("all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
