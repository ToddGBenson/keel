#!/usr/bin/env python3
"""
Feed every known bypass of the agent guard hooks through the hooks themselves, and
fail if any of them gets through. Refs: TheHub #60818, keel#93, binnacle#14

Why this exists
---------------
Four bypasses of .claude/hooks/guard-bash.sh were found and fixed in keel#93 and
binnacle#14 (self-merge, self-approve and release through `gh api`, and branch
protection removed with `--method DELETE` / `-XDELETE`). Both repositories'
selftest.sh was green the whole time the bypasses worked: selftest proves the rules
do what their author meant, and nothing proved they hold against the spellings an
attacker -- or a confused model -- would actually try.

test/hook-bypass-corpus.yml is that list. Each entry is one attempt, the hook it is
aimed at, and its bypass class. This runner builds the PreToolUse payload Claude Code
sends, pipes it into the real hook with `bash`, and reads the exit code exactly the
way Claude Code does: exit 2 blocks, ANY other exit lets the call run. A hook that
crashes is a hook that allowed.

Two parser modes
----------------
guard-bash.sh reads the command with jq when jq is installed and with a sed fallback
when it is not, and the two see different text: sed does not decode JSON, so `\\"`
and `\\n` reach the rules as two characters. Every entry runs in both modes:

  jq     the real jq if it is on PATH, otherwise a shim (this file, --jq-shim) that
         evaluates the two filters the hooks use and refuses any other, so a hook
         that changes its filter breaks this test loudly instead of silently.
  no-jq  PATH without jq. When jq is installed, a directory of symlinks to the
         tools the hooks call; if symlinks cannot be made the mode is SKIPPED and
         says so.

Two tools
---------
Claude Code runs a shell command through its Bash tool and, on Windows hosts, its
PowerShell tool, and both send the command as tool_input.command. A guard bound to
Bash alone is bypassed by sending the same command to PowerShell (TheHub #61064).
So every guard-bash.sh entry runs once per tool in BASH_TOOLS (an entry may pin one
with `tool:`), and before anything runs, .claude/settings.json is read and the
PreToolUse matcher that runs guard-bash.sh must cover every one of those tools: a hook
the harness never calls blocks nothing, whatever this runner sees when it calls the
hook itself.

Verdicts
--------
  enforced entry, blocked          ok
  enforced entry, allowed          FAIL  -- a known bypass works again
  open entry (open_in), allowed    OPEN  -- a known, recorded gap; reported, not failed
  open entry, blocked              FAIL  -- the gap is closed: move the entry to
                                          enforced (delete open_in) so it stays closed

The last rule is a ratchet. A fix for an open gap must update the corpus in the same
change, which is what turns it into a regression test.

Needs PyYAML (ci/requirements.txt) and bash.

    python test/hook-bypass-corpus.test.py            # every entry, both modes
    python test/hook-bypass-corpus.test.py -v         # also print each hook's stderr
"""
from __future__ import annotations

import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "test" / "hook-bypass-corpus.yml"
HOOKS = ROOT / ".claude" / "hooks"

# The only jq filters the hooks use. Anything else is refused by the shim.
JQ_FILTERS = {
    ".tool_input.command // empty": lambda ti: ti.get("command"),
    ".tool_input.file_path // .tool_input.notebook_path // empty":
        lambda ti: ti.get("file_path") or ti.get("notebook_path"),
    '[.tool_input.content, .tool_input.new_string, .tool_input.new_source, (.tool_input.edits // [] | .[]? | .new_string?)] | map(select(type == "string")) | join("\\n")':
        lambda ti: "\n".join(s for s in [ti.get("content"), ti.get("new_string"), ti.get("new_source")]
                             + [e.get("new_string") for e in (ti.get("edits") or []) if isinstance(e, dict)]
                             if isinstance(s, str)),
}
MODES = ("jq", "no-jq")
HOOK_NAMES = ("guard-bash.sh", "guard-write.sh")
WRITE_TOOLS = ("Write", "Edit", "MultiEdit", "NotebookEdit")
# The tools that send a shell command to guard-bash.sh (TheHub #61064).
BASH_TOOLS = ("Bash", "PowerShell")
SETTINGS = ROOT / ".claude" / "settings.json"
# Tools the hooks invoke. The no-jq shim directory links exactly these.
HOOK_TOOLS = ("bash", "sh", "cat", "grep", "sed", "tr", "head", "mktemp", "rm", "awk",
              "python3", "python", "env", "sleep")


def jq_shim(argv: list[str]) -> int:
    """`jq -r FILTER` for the filters in JQ_FILTERS, reading JSON on stdin."""
    args = [a for a in argv if a != "-r"]
    if len(args) != 1 or args[0] not in JQ_FILTERS:
        print(f"jq shim: unsupported invocation {argv!r} -- the hook changed its "
              "jq filter; teach test/hook-bypass-corpus.test.py the new one",
              file=sys.stderr)
        return 3
    data = json.load(sys.stdin)
    val = JQ_FILTERS[args[0]](data.get("tool_input") or {})
    if val is None or val is False:
        return 0
    out = val if isinstance(val, str) else json.dumps(val)
    sys.stdout.buffer.write(out.encode("utf-8") + b"\n")
    return 0


def load_corpus() -> tuple[list[dict], list[str]]:
    import yaml

    errors: list[str] = []
    doc = yaml.safe_load(CORPUS.read_text(encoding="utf-8"))
    if not isinstance(doc, dict) or doc.get("version") != 1:
        return [], ["corpus: expected a mapping with version: 1"]
    classes = doc.get("classes") or {}
    entries = doc.get("entries") or []
    seen: set[str] = set()
    for i, e in enumerate(entries):
        where = f"entry #{i + 1} ({e.get('id', '?')})"
        eid = e.get("id")
        if not eid or eid in seen:
            errors.append(f"{where}: missing or duplicate id")
        seen.add(eid)
        if e.get("hook") not in HOOK_NAMES:
            errors.append(f"{where}: hook must be one of {HOOK_NAMES}")
        if e.get("class") not in classes:
            errors.append(f"{where}: class {e.get('class')!r} is not declared under classes:")
        if e.get("expect") != "block":
            errors.append(f"{where}: expect must be 'block' -- this is a bypass corpus; "
                          "must-allow cases belong in .claude/hooks/selftest.sh")
        if not e.get("why"):
            errors.append(f"{where}: why is required (what the attempt actually achieves)")
        open_in = e.get("open_in")
        if open_in is not None:
            if not open_in or any(m not in MODES for m in open_in):
                errors.append(f"{where}: open_in must be a non-empty subset of {MODES}")
            if not e.get("gap"):
                errors.append(f"{where}: an open entry needs gap: (why the hook misses it)")
        if e.get("hook") == "guard-bash.sh":
            if e.get("tool", "Bash") not in BASH_TOOLS:
                errors.append(f"{where}: tool must be one of {BASH_TOOLS}")
            if not isinstance(e.get("command"), str) and not isinstance(e.get("command_parts"), list):
                errors.append(f"{where}: guard-bash.sh entries need command or command_parts")
        elif e.get("hook") == "guard-write.sh":
            if e.get("tool", "Write") not in WRITE_TOOLS:
                errors.append(f"{where}: tool must be one of {WRITE_TOOLS}")
            if not e.get("file_path"):
                errors.append(f"{where}: guard-write.sh entries need file_path")
    if not entries:
        errors.append("corpus: no entries -- an empty corpus is a vacuous pass")
    for name, c in classes.items():
        if not any(e.get("class") == name for e in entries):
            errors.append(f"class {name}: declared but no entry exercises it")
    return entries, errors


def matcher_covers(matcher: str, tool: str) -> bool:
    """Whether a PreToolUse matcher selects this tool, as Claude Code reads it: a plain
    name list (letters, digits, _ and |) is an exact match on one of the names, and
    anything else is a regular expression. An empty matcher or "*" selects every tool."""
    import re

    if matcher in ("", "*"):
        return True
    if re.fullmatch(r"[A-Za-z0-9_|]+", matcher):
        return tool in matcher.split("|")
    try:
        return re.search(matcher, tool) is not None
    except re.error:
        return False


def binding_errors() -> list[str]:
    """guard-bash.sh must be bound to every tool in BASH_TOOLS (TheHub #61064), and
    guard-write.sh to every tool in WRITE_TOOLS (TheHub #61391)."""
    try:
        settings = json.loads(SETTINGS.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        return [f"{SETTINGS.name}: cannot read it ({exc})"]
    errors: list[str] = []
    for hook, tools, what in (("guard-bash.sh", BASH_TOOLS, "command"), ("guard-write.sh", WRITE_TOOLS, "write")):
        bound: list[str] = []
        for group in (settings.get("hooks") or {}).get("PreToolUse") or []:
            if any(hook in (h.get("command") or "") for h in group.get("hooks") or []):
                bound.append(group.get("matcher", ""))
        if not bound:
            errors.append(f"{SETTINGS.name}: no PreToolUse hook runs {hook}")
            continue
        errors += [f"{SETTINGS.name}: {hook} is not bound to the {tool} tool "
                   f"(matchers: {bound!r}); a {tool} {what} reaches no rule"
                   for tool in tools if not any(matcher_covers(m, tool) for m in bound)]
    return errors


def runs(entries: list[dict]) -> list[tuple[dict, str]]:
    """(entry, tool) pairs: a guard-bash.sh entry once per tool unless it names one."""
    out: list[tuple[dict, str]] = []
    for e in entries:
        if e["hook"] == "guard-bash.sh":
            tools = (e["tool"],) if "tool" in e else BASH_TOOLS
        else:
            tools = (e.get("tool", "Write"),)
        out.extend((e, t) for t in tools)
    return out


def joined(e: dict, key: str) -> str:
    # *_parts lets credential-shaped fixtures live in this repository without the
    # literal ever being contiguous, so neither guard-write.sh nor gitleaks trips on
    # the corpus itself (the same trick as selftest.sh's AKIA_FAKE).
    if f"{key}_parts" in e:
        return "".join(e[f"{key}_parts"])
    return e.get(key, "")


def payload(e: dict, tool: str) -> bytes:
    base = {
        "session_id": "hook-bypass-corpus",
        "transcript_path": "/dev/null",
        "cwd": str(ROOT),
        "permission_mode": "default",
        "hook_event_name": "PreToolUse",
    }
    if e["hook"] == "guard-bash.sh":
        base["tool_name"] = tool
        base["tool_input"] = {"command": joined(e, "command"),
                              "description": "bypass corpus entry"}
    else:
        content = joined(e, "content")
        base["tool_name"] = tool
        if tool == "Write":
            ti = {"file_path": e["file_path"], "content": content}
        elif tool == "Edit":
            ti = {"file_path": e["file_path"], "old_string": e.get("old_string", "x"),
                  "new_string": content}
        elif tool == "MultiEdit":
            ti = {"file_path": e["file_path"],
                  "edits": [{"old_string": "x", "new_string": content}]}
        else:  # NotebookEdit
            ti = {"notebook_path": e["file_path"], "new_source": content}
        base["tool_input"] = ti
    # Claude Code is a Node process: JSON.stringify does not escape non-ASCII, so
    # neither do we -- a unicode entry must reach the sed fallback as the raw bytes.
    return json.dumps(base, ensure_ascii=False).encode("utf-8")


def make_env(mode: str, tmp: Path) -> dict | None:
    env = dict(os.environ)
    env["CLAUDE_PROJECT_DIR"] = str(ROOT)
    real_jq = shutil.which("jq")
    if mode == "jq":
        if real_jq:
            return env
        shim_dir = tmp / "jq-shim"
        shim_dir.mkdir(exist_ok=True)
        shim = shim_dir / "jq"
        py = Path(sys.executable).as_posix()
        me = Path(__file__).resolve().as_posix()
        shim.write_text(f'#!/bin/sh\nexec "{py}" "{me}" --jq-shim "$@"\n', encoding="utf-8")
        shim.chmod(shim.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        env["PATH"] = str(shim_dir) + os.pathsep + env.get("PATH", "")
        return env
    # no-jq
    if not real_jq:
        return env
    link_dir = tmp / "no-jq"
    link_dir.mkdir(exist_ok=True)
    try:
        for t in HOOK_TOOLS:
            p = shutil.which(t)
            if p:
                os.symlink(p, link_dir / t)
    except OSError as exc:
        print(f"  [skip] no-jq mode: cannot build a PATH without jq ({exc})")
        return None
    env["PATH"] = str(link_dir)
    return env


# [TheHub #61843] guard-bash.sh pins PATH to system directories, so a shim directory on
# PATH no longer reaches it. The tests run a COPY whose one marked line is replaced by a
# no-op, so the copy keeps the PATH this test gives it (bash converts a Windows PATH at
# startup, which a literal written into the copy would skip). The live hook has no such
# seam. A hook without the marked line (before #61843) runs as it is.
PIN_RE = re.compile(r"^PATH=.*# guard-path-pin\b.*$", re.M)


def unpinned_copy(hook: Path, dest_dir: Path) -> Path:
    text = hook.read_text(encoding="utf-8")
    new, n = PIN_RE.subn(": # guard-path-pin (test copy: PATH is the test's)", text)
    if n == 0:
        return hook
    out = dest_dir / f"{hook.stem}.test-copy{hook.suffix}"
    if not out.exists() or out.read_text(encoding="utf-8") != new:
        out.write_text(new, encoding="utf-8")
    return out


def run_one(e: dict, tool: str, env: dict, bash: str, hooks: dict) -> tuple[int, str]:
    try:
        r = subprocess.run([bash, str(hooks[e["hook"]])], input=payload(e, tool),
                           capture_output=True, cwd=ROOT, env=env, timeout=60)
    except subprocess.TimeoutExpired:
        # Claude Code would time the hook out and run the call.
        return -1, "timed out"
    return r.returncode, r.stderr.decode("utf-8", "replace")


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--jq-shim":
        return jq_shim(sys.argv[2:])
    verbose = "-v" in sys.argv[1:]
    # Corpus text may be non-ASCII; a Windows console (cp1252) must not crash on it.
    sys.stdout.reconfigure(errors="replace")

    entries, errors = load_corpus()
    if errors:
        print("Corpus is malformed:")
        for err in errors:
            print(f"  [FAIL] {err}")
        return 1

    bound = binding_errors()
    if bound:
        print("The guard hooks are not bound to every tool the corpus runs them for:")
        for err in bound:
            print(f"  [FAIL] {err}")
        return 1

    bash = shutil.which("bash")
    if not bash:
        print("  [FAIL] bash not found -- the hooks cannot be exercised, which is not a pass")
        return 1

    failures: list[str] = []
    opened: list[str] = []
    ran = 0
    with tempfile.TemporaryDirectory() as td:
        for mode in MODES:
            env = make_env(mode, Path(td))
            if env is None:
                continue
            jq_kind = ("real jq" if shutil.which("jq") else "jq shim") if mode == "jq" else "sed/python fallback"
            print(f"\n-- mode: {mode} ({jq_kind}) " + "-" * max(0, 50 - len(mode) - len(jq_kind)))
            todo = runs(entries)
            with ThreadPoolExecutor(max_workers=8) as pool:
                copies = Path(td) / f"hooks-{mode}"
                copies.mkdir(exist_ok=True)
                hooks = {h: unpinned_copy(HOOKS / h, copies) for h in HOOK_NAMES}
                results = list(pool.map(lambda r: run_one(r[0], r[1], env, bash, hooks), todo))
            for (e, tool), (rc, err) in zip(todo, results):
                ran += 1
                blocked = rc == 2
                is_open = mode in (e.get("open_in") or [])
                tag = f"{e['id']:<8} {tool:<10} {e['class']:<22}"
                if blocked and not is_open:
                    print(f"  [ok]   {tag} blocked")
                elif not blocked and is_open:
                    print(f"  [OPEN] {tag} allowed (known gap: {e['gap']})")
                    opened.append(f"{mode}:{tool}:{e['id']}")
                elif not blocked:
                    print(f"  [FAIL] {tag} ALLOWED (exit {rc}) -- {e['why']}")
                    failures.append(f"{mode}:{tool}:{e['id']}")
                else:
                    print(f"  [FAIL] {tag} blocked, but the corpus records it as an open gap"
                          f" in {mode} -- remove '{mode}' from open_in so it stays closed")
                    failures.append(f"{mode}:{tool}:{e['id']}")
                wrong = (not blocked and not is_open) or (blocked and is_open)
                if err.strip() and (wrong or verbose):
                    # [TheHub #61794] A wrong verdict prints what the hook said, so an
                    # intermittent one can be diagnosed from the log it happened in.
                    lines = err.strip().splitlines()
                    for line in (lines[:12] if wrong else lines[:1]):
                        print("         | " + line)
                elif wrong:
                    print("         | (the hook wrote nothing to stderr)")

    print("\n" + "-" * 62)
    print(f"  {len(entries)} corpus entries, {ran} hook runs, "
          f"{len(failures)} failed, {len(opened)} open (known gaps)")
    if failures:
        print("\n  A known bypass of the guard hooks is no longer handled as recorded.")
        print("  This is a CONTROL FAILURE -- fix the hook or, for a closed gap, the")
        print("  corpus. Do not delete the entry to make this pass.")
        return 1
    print("  Every enforced bypass is blocked.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
