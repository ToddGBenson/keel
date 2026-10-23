#!/usr/bin/env python3
"""The one list of test files, and the one runner for it. Refs: TheHub #60980

`./keel check` said "if it is green, CI is green" while running 2 of the 11 test
files ci/scripts/ci-stage.sh ran, and ci-stage.sh named its 11 by hand. A new
test/*.test.py that nobody wired in ran nowhere, and nothing said so.

Now test/manifest.txt names every test file once, with the CI stage that runs
it, and both ci-stage.sh and `./keel check` read it through this script:

    python scripts/test-manifest.py check              # CI fails on drift
    python scripts/test-manifest.py list [--stage S]   # the files, one per line
    python scripts/test-manifest.py run  [--stage S]   # run them

test/manifest.txt
-----------------
One entry per line. A line starting with `#` is a comment (a `#` later in a
line is part of the description, which cites issue numbers).

    <path>  <tags>  <description>

    test/dashboard.test.py   test,quick   dashboard generator tests

`tags` is comma-separated: exactly one stage (`lint` or `test`, the
ci-stage.sh stage that runs the file), and optionally `quick`, which puts the
file in `./keel check --quick`. The description is the header CI prints.

check
-----
Exits 1, naming each offender, when: a test/*.test.py or test/*.test.js is not
listed (it would run nowhere); an entry names a file that does not exist (it
would be a hole in CI that reads as coverage); a file is listed twice (it would
run twice); an entry has no stage, two stages or an unknown tag (it would run in
no stage, or in two); or there is no manifest.

run
---
Runs each selected entry: .py with this interpreter, .js with node. A failure
does not stop the files after it; the summary names every failure and the exit
is 1. With no node, `--node-missing skip` (Concourse's Python image) says so and goes
on; `--node-missing fail` (`./keel check`) prints `warn: node missing, skipped
<file>` and fails, because a local mirror that skips a test is not green.
`--quiet` prints one ok/warn line per file instead of each file's output.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

STAGES = ("lint", "test")
TAGS = set(STAGES) | {"quick"}
MANIFEST = Path("test") / "manifest.txt"
PATTERNS = ("*.test.py", "*.test.js")


class Entry:
    def __init__(self, path: str, tags: list[str], desc: str, line: int):
        self.path, self.tags, self.desc, self.line = path, tags, desc, line

    @property
    def stage(self) -> str | None:
        found = [t for t in self.tags if t in STAGES]
        return found[0] if len(found) == 1 else None


def parse(root: Path) -> tuple[list[Entry], list[str]]:
    """The manifest's entries, and every problem found reading them."""
    f = root / MANIFEST
    if not f.is_file():
        return [], [f"{MANIFEST.as_posix()} does not exist: it must name every test "
                    f"file (test/*.test.py, test/*.test.js) and the stage that runs it"]
    entries, problems = [], []
    for n, raw in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 2)
        if len(parts) < 2:
            problems.append(f"{MANIFEST.as_posix()}:{n}: '{line}' has no stage "
                            f"(expected: <path> <lint|test>[,quick] <description>)")
            continue
        path, tags = parts[0], [t for t in parts[1].split(",") if t]
        desc = parts[2] if len(parts) > 2 else path
        e = Entry(path, tags, desc, n)
        unknown = [t for t in tags if t not in TAGS]
        if unknown:
            problems.append(f"{MANIFEST.as_posix()}:{n}: {path}: unknown tag(s) "
                            f"{', '.join(unknown)} (known: {', '.join(sorted(TAGS))})")
        elif e.stage is None:
            problems.append(f"{MANIFEST.as_posix()}:{n}: {path}: needs exactly one "
                            f"stage of {', '.join(STAGES)}, has {parts[1]}")
        entries.append(e)
    return entries, problems


def check(root: Path) -> int:
    entries, problems = parse(root)
    if not (root / MANIFEST).is_file():
        return report(problems)
    seen: dict[str, int] = {}
    for e in entries:
        if e.path in seen:
            problems.append(f"{MANIFEST.as_posix()}:{e.line}: {e.path} is already listed "
                            f"on line {seen[e.path]}; it would run twice")
        else:
            seen[e.path] = e.line
        if not (root / e.path).is_file():
            problems.append(f"{MANIFEST.as_posix()}:{e.line}: {e.path} is listed but "
                            f"does not exist")
    on_disk = sorted({p.relative_to(root).as_posix()
                      for pat in PATTERNS for p in (root / "test").glob(pat)})
    for f in on_disk:
        if f not in seen:
            problems.append(f"{f} is not in {MANIFEST.as_posix()}, so no CI stage and "
                            f"not ./keel check runs it; add it with its stage")
    if not problems:
        print(f"[ok] {MANIFEST.as_posix()}: {len(entries)} test file(s), every "
              f"test/*.test.py and test/*.test.js listed once, every entry exists")
    return report(problems)


def report(problems: list[str]) -> int:
    for p in problems:
        print(f"ERROR: {p}", file=sys.stderr)
    return 1 if problems else 0


def select(entries: list[Entry], stage: str | None, quick: bool) -> list[Entry]:
    out = entries
    if stage:
        out = [e for e in out if e.stage == stage]
    if quick:
        out = [e for e in out if "quick" in e.tags]
    return out


def run(root: Path, chosen: list[Entry], node_missing: str, quiet: bool) -> int:
    node = shutil.which("node")
    failed, skipped, not_run = [], [], []
    for e in chosen:
        js = e.path.endswith(".js")
        if js and not node:
            if node_missing == "fail":
                print(f"  ! warn: node missing, skipped {e.path}")
                skipped.append(e.path)
            else:
                print(f"── {e.desc} ──")
                print(f"node is not installed here: {e.path} NOT RUN in this stage. It "
                      f"runs where node is: GitHub Actions 'Unit suites' (unit-results.yml) and ./keel check.")
                not_run.append(e.path)
            continue
        argv = [node, e.path] if js else [sys.executable, e.path]
        if quiet:
            p = subprocess.run(argv, cwd=root, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL)
        else:
            print(f"── {e.desc} ({e.path}) ──", flush=True)
            p = subprocess.run(argv, cwd=root)
        if p.returncode == 0:
            if quiet:
                print(f"  ✓ ok: {e.path}")
        else:
            failed.append(e.path)
            if quiet:
                runner = "node" if js else "python"
                print(f"  ! warn: {e.path} FAILED — run: {runner} {e.path}")
        sys.stdout.flush()
    if not quiet:
        print()
        for f in failed:
            print(f"FAILED: {f}")
        passed = len(chosen) - len(failed) - len(skipped) - len(not_run)
        print(f"{passed} of {len(chosen)} test file(s) passed"
              + (f", {len(failed)} FAILED" if failed else "")
              + (f", {len(not_run)} not run (no node)" if not_run else ""))
    return 1 if failed or skipped else 0


def main(argv: list[str]) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("check", "list", "run"):
        sp = sub.add_parser(name)
        sp.add_argument("--root", default=str(Path(__file__).resolve().parent.parent),
                        help="repository root (default: this script's repository)")
        if name != "check":
            sp.add_argument("--stage", choices=STAGES)
            sp.add_argument("--quick", action="store_true",
                            help="only entries tagged quick")
        if name == "run":
            sp.add_argument("--node-missing", choices=("skip", "fail"), default="fail")
            sp.add_argument("--quiet", action="store_true")
    a = ap.parse_args(argv)
    root = Path(a.root)
    if a.cmd == "check":
        return check(root)
    entries, problems = parse(root)
    if problems:
        return report(problems)
    chosen = select(entries, a.stage, a.quick)
    if a.cmd == "list":
        for e in chosen:
            print(e.path)
        return 0
    if not chosen:
        print(f"ERROR: no test files selected from {MANIFEST.as_posix()}; "
              f"a stage that runs nothing is not a pass", file=sys.stderr)
        return 1
    return run(root, chosen, a.node_missing, a.quiet)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
