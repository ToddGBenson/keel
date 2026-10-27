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
    ".tool_input.file_path // empty": lambda ti: ti.get("file_path"),
    '(.tool_input.content // .tool_input.new_string // "")':
        lambda ti: ti.get("content") or ti.get("new_string") or "",
}
MODES = ("jq", "no-jq")
HOOK_NAMES = ("guard-bash.sh", "guard-write.sh")
WRITE_TOOLS = ("Write", "Edit", "MultiEdit", "NotebookEdit")
# Tools the hooks invoke. The no-jq shim directory links exactly these.
HOOK_TOOLS = ("bash", "sh", "cat", "grep", "sed", "tr", "head", "mktemp", "rm", "awk",
              "python3", "python", "env")


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


def joined(e: dict, key: str) -> str:
    # *_parts lets credential-shaped fixtures live in this repository without the
    # literal ever being contiguous, so neither guard-write.sh nor gitleaks trips on
    # the corpus itself (the same trick as selftest.sh's AKIA_FAKE).
    if f"{key}_parts" in e:
        return "".join(e[f"{key}_parts"])
    return e.get(key, "")


def payload(e: dict) -> bytes:
    base = {
        "session_id": "hook-bypass-corpus",
        "transcript_path": "/dev/null",
        "cwd": str(ROOT),
        "permission_mode": "default",
        "hook_event_name": "PreToolUse",
    }
    if e["hook"] == "guard-bash.sh":
        base["tool_name"] = "Bash"
        base["tool_input"] = {"command": joined(e, "command"),
                              "description": "bypass corpus entry"}
    else:
        tool = e.get("tool", "Write")
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


def run_one(e: dict, env: dict, bash: str) -> tuple[int, str]:
    try:
        r = subprocess.run([bash, str(HOOKS / e["hook"])], input=payload(e),
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
            with ThreadPoolExecutor(max_workers=8) as pool:
                results = list(pool.map(lambda e: run_one(e, env, bash), entries))
            for e, (rc, err) in zip(entries, results):
                ran += 1
                blocked = rc == 2
                is_open = mode in (e.get("open_in") or [])
                tag = f"{e['id']:<8} {e['class']:<22}"
                if blocked and not is_open:
                    print(f"  [ok]   {tag} blocked")
                elif not blocked and is_open:
                    print(f"  [OPEN] {tag} allowed (known gap: {e['gap']})")
                    opened.append(f"{mode}:{e['id']}")
                elif not blocked:
                    print(f"  [FAIL] {tag} ALLOWED (exit {rc}) -- {e['why']}")
                    failures.append(f"{mode}:{e['id']}")
                else:
                    print(f"  [FAIL] {tag} blocked, but the corpus records it as an open gap"
                          f" in {mode} -- remove '{mode}' from open_in so it stays closed")
                    failures.append(f"{mode}:{e['id']}")
                if verbose and err.strip():
                    print("         " + err.strip().splitlines()[0])

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
