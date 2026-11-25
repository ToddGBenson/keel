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

Review of keel #218: a signal sent to the entry's own shell is a block; a hook rewritten in
place while it runs still judges what it read (each hook's body is one function, parsed
whole before it runs); and a hook from before #62264 under the new entry says how to recover.

    python test/hook-cut-short.test.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
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


def signalled_entry(cmd, project, payload, sig):
    """Send sig to the settings entry's own shell while the hook waits for its payload.
    Sent from bash (kill), so it is a real signal on Git Bash too."""
    pfile = project / "payload.json"
    pfile.write_text(json.dumps(payload), encoding="utf-8")
    driver = ('{ sleep 3; cat "$PFILE"; } | bash -c "$ENTRY" & pid=$!\n'
              'sleep 1; kill -' + sig + ' "$pid"\n'
              'wait "$pid"; echo "rc=$?"\n')
    env = dict(os.environ, CLAUDE_PROJECT_DIR=project.as_posix(), ENTRY=cmd, PFILE=pfile.as_posix())
    r = subprocess.run([shutil.which("bash"), "-c", driver], capture_output=True, cwd=project,
                       env=env, timeout=180)
    out = r.stdout.decode("utf-8", "replace")
    return int(out.rsplit("rc=", 1)[1].split()[0]) if "rc=" in out else None


def rewritten_in_place(cmd, project, target, payload, wait_s=8):
    """Start the entry, let the hook start and wait for its payload, then rewrite the hook
    in place with a file whose every line is the verdict call, then send the payload."""
    env = dict(os.environ, CLAUDE_PROJECT_DIR=project.as_posix())
    p = subprocess.Popen([shutil.which("bash"), "-c", cmd], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=project, env=env)
    time.sleep(wait_s)
    size = target.stat().st_size
    with open(target, "r+b") as f:   # the same file, not a new one
        f.seek(0)
        f.write(b"#!/usr/bin/env bash\n" + b"guard_allow\n" * (size // 12 + 1))
        f.truncate()
    try:
        _, err = p.communicate(json.dumps(payload).encode(), timeout=120)
    except subprocess.TimeoutExpired:
        p.kill()
        _, err = p.communicate()
    return p.returncode, err.decode("utf-8", "replace")


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

            # Review of keel #218 (1): the entry is a shell of its own. A signal to it must be a
            # block, as it is to the hook (TheHub #61973), never 128+N.
            for sig in ("TERM", "HUP", "USR1"):
                rc = signalled_entry(cmd, project, allowed, sig)
                check(f"{hook}: SIG{sig} sent to the settings entry is a block (exit 2)", rc == 2, f"rc={rc}")

            # Review of keel #218 (3): a hook rewritten IN PLACE (same inode, as cp or an editor
            # does) while a run waits for its payload. bash goes on reading at its byte offset in
            # the new text, so a file whose every line is the verdict call could hand it an allow.
            # The hook is parsed whole before any of it runs, so the run judges the file it started.
            rc, err = rewritten_in_place(cmd, project, target, blocked)
            check(f"{hook} rewritten in place while it runs: the run still judges what it read (exit 2)",
                  rc == 2, f"rc={rc} {err[:300]}")
            target.write_text(full, encoding="utf-8", newline="\n")

            # Review of keel #218 (2): a hook from before TheHub #62264 under this entry blocks every
            # call, so the message must say so and say how to recover, not only "retry".
            target.write_text("#!/usr/bin/env bash\ncat >/dev/null\nexit 0\n", encoding="utf-8", newline="\n")
            rc, err = run(cmd, project, allowed)
            check(f"{hook} from before #62264 under the new entry: blocked, and the message says how to recover",
                  rc == 2 and "predates TheHub #62264" in err and "switch" in err, f"rc={rc} {err[:400]}")
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
