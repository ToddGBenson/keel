#!/usr/bin/env python3
"""
guard-write.sh fails CLOSED, as guard-bash.sh does since TheHub #61794. Refs: TheHub #61844

guard-write.sh had the three defects #61794 fixed in guard-bash.sh:

1. `printf ... | grep -q` under pipefail. grep -q exits at its first match, the writer
   dies of SIGPIPE, the pipeline returns 141, and the `if` reads a MATCH as "no match".
   Content past the pipe buffer (~64 KB) with a credential near its start was ALLOWED.
2. Nothing checked that its helpers ran. A grep, jq or python that errored or was killed
   left a capture empty or a test false, and the hook reached `exit 0`.
3. Claude Code blocks only on exit 2 and runs the call on any other code, so a crash, an
   unbound variable or a failed fork was an allow.

Each section below is red on the hook before the fix:

- padded content: a credential or private-key header followed by ~400 KB is still blocked,
  with jq and with the python fallback;
- one helper fails (exit 2, or killed): the must-block writes are still blocked, and even a
  harmless write is refused, saying it was an internal error;
- a line injected after the EXIT trap (exit 1, exit 127, an unbound variable, the fault file
  emptied or removed) blocks even a harmless write, as an internal error.

With no fault, the rules decide: each must-block write is blocked by its rule and a
harmless one is allowed.

    python test/hook-write-fail-closed.test.py
"""
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOOK = ROOT / ".claude" / "hooks" / "guard-write.sh"
# The tools guard-write.sh runs, and what the shims and the test need around them.
TOOLS = ("bash", "sh", "cat", "grep", "mktemp", "rm", "python3", "python", "env", "jq")
# Helpers the hook reads the payload or the content with.
FAULTY = ("grep", "cat", "jq", "python3")
# Credential-shaped values are built from parts so that this file holds no contiguous
# literal for guard-write.sh or gitleaks to trip on (the trick selftest.sh's AKIA_FAKE uses).
AKIA = "AKI" "A" "ABCDEFGHIJKLMNOP"
ASSIGN = "api" + "_k" + "ey = " + "abcdefghij" + "0123456789"
PEM = "-----BEGIN RSA PRIVATE " "KEY-----\nMIIEow\n"
MUST_BLOCK = {
    "a cloud key literal": ("src/config.py", AKIA),
    "a credential assignment": ("src/settings.py", ASSIGN),
    "a private key header": ("deploy/id_rsa", PEM),
    "hand-edited generated evidence": ("evidence/142/g4/scan.sarif", "{}"),
}
HARMLESS = ("src/drafts.py", "def save():\n    pass\n")
# 5000 comment lines of 80 characters, about 400 KB, after the credential.
PAD = "".join(f"\n# padding line {i:05d} " + "x" * 58 for i in range(5000))
LARGE = {f"{name}, padded to {len(text + PAD) // 1024} KB": (path, text + PAD)
         for name, (path, text) in MUST_BLOCK.items() if not path.startswith("evidence/")}
SHIMS = {
    "exits 2": "#!/bin/sh\nexit 2\n",
    "is killed": "#!/bin/sh\nkill -9 $$\n",
}
failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def payload(path, content, tool="Write"):
    ti = {"file_path": path, "content": content} if tool == "Write" else \
         {"file_path": path, "old_string": "x", "new_string": content}
    return json.dumps({"session_id": "write-fail-closed", "transcript_path": "/dev/null",
                       "cwd": str(ROOT), "permission_mode": "default",
                       "hook_event_name": "PreToolUse", "tool_name": tool,
                       "tool_input": ti}).encode()


def tool_dir(tmp: Path, faulty=None, shim=None, with_jq=True):
    d = Path(tempfile.mkdtemp(dir=tmp))
    for t in TOOLS:
        if t == "jq" and not with_jq:
            continue
        if t == faulty or (faulty == "python3" and t == "python"):
            p = d / t
            p.write_text(shim, encoding="utf-8")
            p.chmod(p.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
            continue
        real = shutil.which(t)
        if real:
            os.symlink(real, d / t)
    return d


def run(path, content, path_dir, tool="Write", hook=HOOK):
    env = {"PATH": str(path_dir), "CLAUDE_PROJECT_DIR": str(ROOT), "HOME": os.environ.get("HOME", "/tmp")}
    r = subprocess.run([shutil.which("bash"), str(hook)], input=payload(path, content, tool),
                       capture_output=True, cwd=ROOT, env=env, timeout=60)
    return r.returncode, r.stderr.decode("utf-8", "replace")


def main():
    if not shutil.which("bash") or not (shutil.which("python3") or shutil.which("jq")):
        print("bash, and jq or python3, are required")
        return 1
    tmp = Path(tempfile.mkdtemp(prefix="write-fail-closed-"))
    try:
        have_jq = bool(shutil.which("jq"))
        modes = [True, False] if have_jq else [False]
        if not have_jq:
            print("  (no jq on this host: only the python fallback is exercised)")

        print("no fault: the rules decide")
        for with_jq in modes:
            mode = "jq" if with_jq else "python"
            clean = tool_dir(tmp, with_jq=with_jq)
            for name, (path, text) in MUST_BLOCK.items():
                for tool in ("Write", "Edit"):
                    rc, err = run(path, text, clean, tool)
                    check(f"{mode} {tool}: {name} is blocked by its rule",
                          rc == 2 and "internal error" not in err, f"rc={rc} {err[:200]}")
            rc, err = run(*HARMLESS, clean)
            check(f"{mode}: a harmless write is allowed", rc == 0, f"rc={rc} {err[:200]}")

        print("large content: a match is still a match")
        for with_jq in modes:
            mode = "jq" if with_jq else "python"
            clean = tool_dir(tmp, with_jq=with_jq)
            for name, (path, text) in LARGE.items():
                for tool in ("Write", "Edit"):
                    rc, err = run(path, text, clean, tool)
                    check(f"{mode} {tool}: {name} is blocked", rc == 2, f"rc={rc} ALLOWED")

        print("one helper fails: the hook refuses")
        for faulty in FAULTY:
            fmodes = [True] if faulty == "jq" else modes
            if faulty == "python3":
                fmodes = [False]   # python runs only when there is no jq
            for with_jq in fmodes:
                mode = "jq" if with_jq else "python"
                for how, shim in SHIMS.items():
                    d = tool_dir(tmp, faulty=faulty, shim=shim, with_jq=with_jq)
                    for name, (path, text) in MUST_BLOCK.items():
                        rc, err = run(path, text, d)
                        check(f"{faulty} {how} ({mode}): {name} is still blocked",
                              rc == 2, f"rc={rc} ALLOWED\n{err[:300]}")
                    rc, err = run(*HARMLESS, d)
                    check(f"{faulty} {how} ({mode}): even a harmless write is refused, and says why",
                          rc == 2 and "internal error" in err, f"rc={rc} {err[:300]}")

        # The hook allows only by exiting 0. A copy of it with one line injected after the
        # trap is installed stands in for a crash, an unbound variable, a failed fork's 127,
        # or a fault file emptied behind its back. Before the fix there is no trap, so the
        # line goes after `set -uo pipefail`.
        print("any exit but 0 and 2 is a block; the fault file cannot be emptied")
        text = HOOK.read_text(encoding="utf-8")
        anchor = "trap guard_exit EXIT\n"
        check("the hook installs its EXIT trap", anchor in text)
        if anchor not in text:
            anchor = "set -uo pipefail\n"
        injections = {
            "exit 1 (an error)": "exit 1",
            "exit 127 (a failed command or fork)": "exit 127",
            "an unbound variable under set -u": ': "$guard_no_such_variable"',
            "the fault file emptied": ': > "${guard_faults:-/dev/null}"',
            "the fault file removed": 'command rm -f "${guard_faults:-/nonexistent}"',
        }
        clean = tool_dir(tmp, with_jq=have_jq)
        for name, line in injections.items():
            hook = tmp / "guard-write.sh"
            hook.write_text(text.replace(anchor, anchor + line + "\n", 1), encoding="utf-8")
            rc, err = run(*HARMLESS, clean, hook=hook)
            check(f"{name}: even a harmless write is blocked, as an internal error",
                  rc == 2 and "internal error" in err, f"rc={rc} {err[:200]}")
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
