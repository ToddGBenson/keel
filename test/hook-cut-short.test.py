#!/usr/bin/env python3
"""
A guard hook whose file is cut short blocks; it never allows. Refs: TheHub #62264

bash reads a script while it runs it. When .claude/hooks/guard-bash.sh or guard-write.sh is
rewritten while a run starts (a branch switch or a platform sync in a shared checkout), bash
can read an empty or partial file and exit 0 at the cut, and Claude Code treats exit 0 as an
allow: the fuzz of keel #212 / binnacle #108 allowed 106 of 120 such runs.

So an allow must be proven, twice over:
  - the settings entry (.claude/settings.json) allows only when the hook exits 0 AND its whole
    stdout is the line "guard-verdict: allow"; anything else (no line, any other exit) blocks;
  - each hook prints that line only from guard_allow, the last line of the file (and an empty
    command or path), so a run that ends at a cut, with no verdict, blocks. guard-bash.sh's
    supervisor also requires its worker to have written a per-run nonce line before passing an
    allow on, because the worker reads the file again.

This test runs the REAL settings entries, as Claude Code does (the command through bash, with
CLAUDE_PROJECT_DIR set), against copies of each hook cut at several points: empty, inside its
first lines, inside guard-bash.sh's supervisor, half way, near the end, and every line but the
last. Every cut must block a command the complete hook allows. The complete hook must still
allow it and still block a command it blocks.

    python test/hook-cut-short.test.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOOKS = ROOT / ".claude" / "hooks"
SETTINGS = ROOT / ".claude" / "settings.json"
failures = []

PAYLOADS = {
    "guard-bash.sh": (
        {"tool_name": "Bash", "tool_input": {"command": "git status"}},
        {"tool_name": "Bash", "tool_input": {"command": "gh pr merge 1"}},
    ),
    "guard-write.sh": (
        {"tool_name": "Write", "tool_input": {"file_path": "src/a.py", "content": "x = 1\n"}},
        {"tool_name": "Write", "tool_input": {"file_path": "evidence/1/a.sarif", "content": "{}"}},
    ),
}


def check(name, cond, detail=""):
    print(f"  [{'ok' if cond else 'FAIL'}]   {name}" + ("" if cond else f"  {detail}"))
    if not cond:
        failures.append(name)


def entry(hook):
    settings = json.loads(SETTINGS.read_text(encoding="utf-8"))
    for group in settings["hooks"]["PreToolUse"]:
        for h in group.get("hooks") or []:
            if hook in (h.get("command") or ""):
                return h["command"]
    return None


def run(cmd, project, payload):
    env = dict(os.environ, CLAUDE_PROJECT_DIR=project.as_posix())
    r = subprocess.run([shutil.which("bash"), "-c", cmd], input=json.dumps(payload).encode(),
                       capture_output=True, cwd=project, env=env, timeout=120)
    return r.returncode, r.stderr.decode("utf-8", "replace")


def cuts(text):
    """(name, prefix) pairs: the states a reader can meet while the file is being written."""
    lines = text.splitlines(keepends=True)
    out = [("empty", ""), ("its first line", lines[0]), ("its first 10 lines", "".join(lines[:10]))]
    sup = next((i for i, l in enumerate(lines) if l.startswith("fi") and "--guard-worker" in "".join(lines[:i])), None)
    if sup is not None:
        out.append(("just after the supervisor", "".join(lines[:sup + 1])))
        out.append(("inside the supervisor", "".join(lines[:sup - 5])))
    for frac in (0.5, 0.9):
        out.append((f"{int(frac * 100)}% of its lines", "".join(lines[:int(len(lines) * frac)])))
    out.append(("every line but the last", "".join(lines[:-1])))
    out.append(("mid-way through its last line", "".join(lines[:-1]) + lines[-1][: len(lines[-1]) // 2]))
    return out


def main():
    if not shutil.which("bash"):
        print("bash is required")
        return 1
    tmp = Path(tempfile.mkdtemp(prefix="hook-cut-"))
    try:
        for hook, (allowed, blocked) in PAYLOADS.items():
            cmd = entry(hook)
            check(f"settings.json runs {hook} from a PreToolUse entry", cmd is not None)
            if cmd is None:
                continue
            print(f"{hook}:")
            full = (HOOKS / hook).read_text(encoding="utf-8")
            project = tmp / hook
            (project / ".claude" / "hooks").mkdir(parents=True)
            target = project / ".claude" / "hooks" / hook
            target.write_text(full, encoding="utf-8", newline="\n")
            rc, err = run(cmd, project, allowed)
            check(f"the complete {hook} allows an ordinary call (exit 0)", rc == 0, f"rc={rc} {err[:300]}")
            rc, err = run(cmd, project, blocked)
            check(f"the complete {hook} still blocks (exit 2)", rc == 2, f"rc={rc}")
            for name, text in cuts(full):
                target.write_text(text, encoding="utf-8", newline="\n")
                rc, err = run(cmd, project, allowed)
                check(f"{hook} cut short ({name}): blocks, never allows", rc == 2, f"rc={rc} {err[:300]}")
            target.write_text(full, encoding="utf-8", newline="\n")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print()
    if failures:
        print(f"{len(failures)} FAILED")
        return 1
    print("all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
