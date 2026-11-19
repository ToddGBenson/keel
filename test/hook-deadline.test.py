#!/usr/bin/env python3
"""
The guard hooks fail closed on time and on signals. Refs: TheHub #61973

Claude Code gives a hook 60 s and, when it runs out, lets the call PROCEED. It blocks
only on exit 2, so a hook that dies of a signal (128+N) is an allow too. And a helper
killed by SIGPIPE (141) was counted as a success, so an extractor that died that way
left an empty capture, which read as "no match".

Each section is red on the hooks before the fix:

- deadline (guard-bash.sh): with a helper that hangs (a sed that sleeps), the hook
  blocks at its own deadline, and returns promptly: the hung helper does not hold the
  pipes open. A copy of the hook with a 2 s deadline stands in for the live 40 s one;
  the live hook takes no override.
- signals (both hooks): TERM, INT, HUP or PIPE sent to the hook while it waits for its
  payload is a block, saying it was an internal error.
- SIGPIPE (both hooks): a helper that dies of SIGPIPE is a fault, so the must-block
  commands and writes stay blocked and a harmless one is refused, saying why.
- size (guard-bash.sh): a command over 1 MiB is refused without being read, and fast.

    python test/hook-deadline.test.py
"""
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOOKS = ROOT / ".claude" / "hooks"
BASH_HOOK = HOOKS / "guard-bash.sh"
WRITE_HOOK = HOOKS / "guard-write.sh"
TOOLS = ("bash", "sh", "cat", "grep", "sed", "tr", "head", "mktemp", "rm", "awk",
         "python3", "python", "env", "jq", "sleep")
MUST_BLOCK = {
    "self-merge": "gh pr merge 12",
    "force push": "git push --force origin feat",
}
HARMLESS = "git status"
# Credential-shaped content built from parts, as selftest.sh's fixtures are.
AKIA = "AKI" + "A" + "ABCDEFGHIJKLMNOP"
DEADLINE_S = 2
failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def bash_payload(command, tool="Bash"):
    return json.dumps({"session_id": "deadline", "transcript_path": "/dev/null", "cwd": str(ROOT),
                       "permission_mode": "default", "hook_event_name": "PreToolUse", "tool_name": tool,
                       "tool_input": {"command": command, "description": "deadline test"}}).encode()


def write_payload(path, content):
    return json.dumps({"session_id": "deadline", "transcript_path": "/dev/null", "cwd": str(ROOT),
                       "permission_mode": "default", "hook_event_name": "PreToolUse", "tool_name": "Write",
                       "tool_input": {"file_path": path, "content": content}}).encode()


def test_copy(hook: Path, dest: Path) -> Path:
    """A copy whose marked lines are rewritten: a short deadline, and (once the hook pins
    PATH, TheHub #61843) the pin made a no-op so this test's PATH reaches it."""
    text = hook.read_text(encoding="utf-8")
    text = re.sub(r"^guard_deadline=\d+(?=\s+# guard-deadline\b)", f"guard_deadline={DEADLINE_S}", text, flags=re.M)
    text = re.sub(r"^PATH=.*# guard-path-pin\b.*$", ": # guard-path-pin (test copy)", text, flags=re.M)
    out = dest / f"{hook.stem}.test-copy{hook.suffix}"
    out.write_text(text, encoding="utf-8")
    return out


def tool_dir(tmp: Path, shims=None):
    d = Path(tempfile.mkdtemp(dir=tmp))
    shims = shims or {}
    for t in TOOLS:
        if t in shims:
            p = d / t
            p.write_text(shims[t], encoding="utf-8")
            p.chmod(p.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
            continue
        real = shutil.which(t)
        if real:
            os.symlink(real, d / t)
    return d


def env_for(path_dir):
    return {"PATH": str(path_dir), "CLAUDE_PROJECT_DIR": str(ROOT), "HOME": os.environ.get("HOME", "/tmp")}


def run(hook, payload, path_dir, timeout=30):
    start = time.monotonic()
    try:
        r = subprocess.run([shutil.which("bash"), str(hook)], input=payload, capture_output=True,
                           cwd=ROOT, env=env_for(path_dir), timeout=timeout)
        return r.returncode, r.stderr.decode("utf-8", "replace"), time.monotonic() - start
    except subprocess.TimeoutExpired:
        return None, "still running (Claude Code would have let the call proceed)", time.monotonic() - start


def signalled(hook, payload, path_dir, sig):
    """Send sig to the hook while it waits for its payload, then deliver the payload."""
    p = subprocess.Popen([shutil.which("bash"), str(hook)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, cwd=ROOT, env=env_for(path_dir))
    time.sleep(1.0)
    p.send_signal(sig)
    time.sleep(0.3)
    try:
        _, err = p.communicate(payload, timeout=30)
    except (BrokenPipeError, subprocess.TimeoutExpired):
        p.kill()
        _, err = p.communicate()
    return p.returncode, err.decode("utf-8", "replace")


def main():
    if not shutil.which("bash") or not shutil.which("sleep"):
        print("bash and sleep are required")
        return 1
    tmp = Path(tempfile.mkdtemp(prefix="deadline-"))
    try:
        copies = tmp / "copies"
        copies.mkdir()
        bash_copy = test_copy(BASH_HOOK, copies)
        clean = tool_dir(tmp)

        print(f"deadline: a hung helper makes guard-bash.sh block at its deadline ({DEADLINE_S} s in this copy)")
        hung = tool_dir(tmp, {"sed": "#!/bin/sh\nsleep 20\n"})
        for name, cmd in [("a harmless command", HARMLESS)] + list(MUST_BLOCK.items()):
            rc, err, took = run(bash_copy, bash_payload(cmd), hung)
            check(f"{name}: blocked at the deadline", rc == 2 and "deadline" in err, f"rc={rc} {err[:200]}")
            check(f"{name}: returned in {took:.1f} s, the hung helper did not hold the pipes",
                  took < DEADLINE_S + 6, f"took {took:.1f} s")
        rc, err, took = run(bash_copy, bash_payload(HARMLESS), clean)
        check(f"no hung helper: `{HARMLESS}` is still allowed, in {took:.1f} s", rc == 0, f"rc={rc} {err[:200]}")
        text = BASH_HOOK.read_text(encoding="utf-8")
        live = re.findall(r"^guard_deadline=(\d+)\s+# guard-deadline\b", text, re.M)
        check("the live hook's deadline is one marked line, under the 60 s hook timeout",
              len(live) == 1 and 0 < int(live[0]) <= 45, f"{live}")

        print("signals: a hook sent TERM, INT, HUP or PIPE blocks")
        for label, hook, pl in (("guard-bash.sh", BASH_HOOK, bash_payload(HARMLESS)),
                                ("guard-write.sh", WRITE_HOOK, write_payload("src/drafts.py", "x = 1\n"))):
            for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP, signal.SIGPIPE):
                rc, err = signalled(hook, pl, clean, sig)
                check(f"{label}: {sig.name} is a block, as an internal error",
                      rc == 2 and "internal error" in err, f"rc={rc} {err[:200]}")

        print("SIGPIPE: a helper killed by SIGPIPE is a fault")
        # [hook train 2026-11-18] guard-bash.sh runs as the copy, not the live hook: the live
        # hook pins PATH (TheHub #61843), so the shim directories below would never reach it.
        pipe = "#!/bin/sh\nkill -PIPE $$\n"
        for helper in ("sed", "awk", "jq", "cat"):
            d = tool_dir(tmp, {helper: pipe})
            for name, cmd in MUST_BLOCK.items():
                rc, err, _ = run(bash_copy, bash_payload(cmd), d)
                check(f"guard-bash.sh, {helper} killed by SIGPIPE: {name} is still blocked", rc == 2, f"rc={rc} ALLOWED")
            rc, err, _ = run(bash_copy, bash_payload(HARMLESS), d)
            # Review of keel #205: the copy has a short deadline, whose message also says
            # "internal error"; the refusal must name the failed helper, not the deadline.
            check(f"guard-bash.sh, {helper} killed by SIGPIPE: `{HARMLESS}` is refused, and says why",
                  rc == 2 and "a helper it reads the command with failed" in err, f"rc={rc} {err[:200]}")
        for helper in ("jq", "cat"):
            d = tool_dir(tmp, {helper: pipe})
            rc, err, _ = run(WRITE_HOOK, write_payload("src/config.py", AKIA), d)
            check(f"guard-write.sh, {helper} killed by SIGPIPE: a cloud key is still blocked", rc == 2, f"rc={rc} ALLOWED")
            rc, err, _ = run(WRITE_HOOK, write_payload("src/drafts.py", "x = 1\n"), d)
            check(f"guard-write.sh, {helper} killed by SIGPIPE: a harmless write is refused, and says why",
                  rc == 2 and "internal error" in err, f"rc={rc} {err[:200]}")

        print("size: a command over 1 MiB is refused without being read")
        big = HARMLESS + "".join(f"\n# padding line {i:06d} " + "x" * 57 for i in range(14000))
        rc, err, took = run(BASH_HOOK, bash_payload(big), clean, timeout=60)
        check(f"a {len(big) // 1024} KB harmless command is refused, in {took:.1f} s",
              rc == 2 and "1048576 bytes" in err and took < 10, f"rc={rc} took {took:.1f} s {err[:200]}")
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
