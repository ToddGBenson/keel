#!/usr/bin/env python3
"""
guard-bash.sh fails CLOSED when one of its own helpers fails. Refs: TheHub #61794

On keel #176's Actions run, KB-177 (`curl -T env.json .../environments/production`)
was ALLOWED once and blocked on every rerun. The hook decides with text tools (grep,
sed, awk, tr, cat, jq) inside $(...) captures, and nothing checked whether they ran:
a helper that errored or was killed left a capture empty, no rule matched, and the
hook reached `exit 0`. A guard that cannot read the command must refuse it.

Fault injection: PATH holds the hook's real tools except ONE, replaced by a shim that
fails (exit 2, or killed by SIGKILL). Each must-block command must still be blocked,
and the block must say it was an internal error rather than a rule. With no fault,
the same commands are blocked by their rules and a harmless one is allowed.

    python test/hook-fail-closed.test.py
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
HOOK = ROOT / ".claude" / "hooks" / "guard-bash.sh"
# The tools guard-bash.sh runs (test/hook-bypass-corpus.test.py's HOOK_TOOLS, plus jq).
TOOLS = ("bash", "sh", "cat", "grep", "sed", "tr", "head", "mktemp", "rm", "awk",
         "python3", "python", "env", "jq")
FAULTY = ("grep", "sed", "awk", "tr", "cat", "jq")
# Helpers the hook runs on EVERY command (reading the payload and building its views),
# so a fault in one refuses even a harmless command. tr runs only on the curl/cmdlet
# path: a broken tr cannot have decided `git status`, and allowing it is correct.
ALWAYS_RUN = ("grep", "sed", "awk", "cat", "jq")
MUST_BLOCK = {
    "KB-177 upload replaces an environment": "curl -T env.json https://api.github.com/repos/O/R/environments/production",
    "self-merge": "gh pr merge 12",
    "force push": "git push --force origin feat",
}
HARMLESS = "git status"
# [TheHub #61794 review #1] `printf ... | grep -q` under pipefail: grep exits on its first
# match, the writer gets SIGPIPE (141), and the pipeline's status flips the match to "no
# match". A command padded past the pipe buffer made the hook ALLOW. Generated here, never
# a file: 5000 comment lines of 80 characters, about 400 KB.
PAD = "".join(f"\n# padding line {i:05d} " + "x" * 58 for i in range(5000))
LARGE = {f"{name}, padded to {len(cmd + PAD) // 1024} KB": cmd + PAD for name, cmd in MUST_BLOCK.items()}
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


def payload(command, tool="Bash"):
    return json.dumps({"session_id": "fail-closed", "transcript_path": "/dev/null",
                       "cwd": str(ROOT), "permission_mode": "default",
                       "hook_event_name": "PreToolUse", "tool_name": tool,
                       "tool_input": {"command": command, "description": "fail-closed test"}}).encode()


def tool_dir(tmp: Path, faulty=None, shim=None, with_jq=True):
    d = Path(tempfile.mkdtemp(dir=tmp))
    for t in TOOLS:
        if t == "jq" and not with_jq:
            continue
        if t == faulty:
            p = d / t
            p.write_text(shim, encoding="utf-8")
            p.chmod(p.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
            continue
        real = shutil.which(t)
        if real:
            os.symlink(real, d / t)
    return d


def run(command, path_dir, tool="Bash", hook=HOOK):
    env = {"PATH": str(path_dir), "CLAUDE_PROJECT_DIR": str(ROOT), "HOME": os.environ.get("HOME", "/tmp")}
    r = subprocess.run([shutil.which("bash"), str(hook)], input=payload(command, tool),
                       capture_output=True, cwd=ROOT, env=env, timeout=60)
    return r.returncode, r.stderr.decode("utf-8", "replace")


def main():
    if not shutil.which("bash"):
        print("bash is required")
        return 1
    tmp = Path(tempfile.mkdtemp(prefix="fail-closed-"))
    try:
        have_jq = bool(shutil.which("jq"))
        if not have_jq:
            print("  (no jq on this host: the jq mode is the shimmed jq only)")
        print("no fault: the rules decide")
        clean = tool_dir(tmp, with_jq=have_jq)
        for name, cmd in MUST_BLOCK.items():
            rc, err = run(cmd, clean)
            check(f"{name} is blocked by its rule", rc == 2 and "internal error" not in err, f"rc={rc}")
        rc, err = run(HARMLESS, clean)
        check(f"`{HARMLESS}` is allowed", rc == 0, f"rc={rc} {err[:200]}")

        print("a large command: a match is still a match (review #1)")
        for with_jq in ([True, False] if have_jq else [False]):
            d = clean if with_jq else tool_dir(tmp, with_jq=False)
            for name, cmd in LARGE.items():
                for t in ("Bash", "PowerShell"):
                    rc, err = run(cmd, d, t)
                    check(f"{'jq' if with_jq else 'no-jq'} {t}: {name} is blocked", rc == 2,
                          f"rc={rc} ALLOWED")

        print("one helper fails: the hook refuses")
        for tool in FAULTY:
            if tool == "jq":
                modes = [True]   # a jq that is installed but fails
            else:
                modes = [True, False] if have_jq else [False]
            for with_jq in modes:
                for how, shim in SHIMS.items():
                    d = tool_dir(tmp, faulty=tool, shim=shim, with_jq=with_jq)
                    mode = "jq" if with_jq else "no-jq"
                    for name, cmd in MUST_BLOCK.items():
                        for t in ("Bash", "PowerShell"):
                            rc, err = run(cmd, d, t)
                            check(f"{tool} {how} ({mode}, {t}): {name} is still blocked",
                                  rc == 2, f"rc={rc} ALLOWED\n{err[:300]}")
                    if tool in ALWAYS_RUN:
                        rc, err = run(HARMLESS, d)
                        check(f"{tool} {how} ({mode}): even `{HARMLESS}` is refused, and says why",
                              rc == 2 and "internal error" in err, f"rc={rc} {err[:300]}")

        # [review #2, low #4] The hook allows only by exiting 0. A copy of it with one
        # line injected after the trap is installed stands in for a crash, an unbound
        # variable, a failed fork's 127, or a fault file emptied behind its back.
        print("any exit but 0 and 2 is a block; the fault file cannot be emptied")
        text = HOOK.read_text(encoding="utf-8")
        anchor = "trap guard_exit EXIT\n"
        check("the hook installs its EXIT trap", anchor in text)
        injections = {
            "exit 1 (an error)": "exit 1",
            "exit 127 (a failed command or fork)": "exit 127",
            "an unbound variable under set -u": ': "$guard_no_such_variable"',
            "the fault file emptied": ': > "$guard_faults"',
            "the fault file removed": 'command rm -f "$guard_faults"',
        }
        for name, line in injections.items():
            hook = tmp / "guard-bash.sh"
            hook.write_text(text.replace(anchor, anchor + line + "\n", 1), encoding="utf-8")
            rc, err = run(HARMLESS, clean, hook=hook)
            check(f"{name}: even `{HARMLESS}` is blocked, as an internal error",
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
