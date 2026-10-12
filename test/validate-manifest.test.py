#!/usr/bin/env python3
"""
Tests that scripts/validate-manifest.py refuses to pass having checked nothing.
Refs: #111

The validator reads `git ls-files`. Where git sees no repository -- a container
that cannot read a worktree's .git, a tarball, a fresh `git init` -- that list is
empty, and the validator used to print "0 tracked files" followed by "[ok]". A
check that examined nothing must not report success.

Each case copies the repository, minus .git, into a throwaway directory and runs
the REAL script there (it finds its root from its own location):

  * a directory that is not a git repository fails, saying why;
  * a git repository with nothing tracked fails, saying why;
  * the real repository still passes.

Needs PyYAML (ci/requirements.txt) and git.

    python test/validate-manifest.test.py
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "validate-manifest.py"
failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def run_in_copy(init_git):
    with tempfile.TemporaryDirectory() as tmp:
        # The whole tree without .git: every path the manifest lists exists, and
        # git sees nothing -- the exact shape of the run that passed vacuously.
        root = Path(tmp) / "tree"
        shutil.copytree(ROOT, root, ignore=shutil.ignore_patterns(".git"))
        if init_git:
            subprocess.run(["git", "init", "-q", str(root)], check=True)
        proc = subprocess.run([sys.executable, str(root / "scripts" / SCRIPT.name)],
                              capture_output=True, text=True, encoding="utf-8",
                              errors="replace")
        return proc.returncode, proc.stdout + proc.stderr


rc, out = run_in_copy(init_git=False)
check("outside a git repository it fails", rc != 0, f"rc={rc}\n{out[-400:]}")
check("and says it checked nothing", "no tracked files" in out, out[-400:])
check("and does not print [ok]", "[ok]" not in out, out[-400:])

rc, out = run_in_copy(init_git=True)
check("in a git repository with nothing tracked it fails", rc != 0, f"rc={rc}\n{out[-400:]}")
check("and says it checked nothing", "no tracked files" in out, out[-400:])

proc = subprocess.run([sys.executable, str(SCRIPT)], capture_output=True, text=True,
                      encoding="utf-8", errors="replace")
check("the real repository still passes", proc.returncode == 0, proc.stdout[-400:])

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)
print("\nall passed")
