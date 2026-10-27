#!/usr/bin/env python3
"""
Tests that scripts/validate-platform.py fails when a gate command names no
evidence/ path. Refs: TheHub #60981, POAM-018

/idea and /ready named no evidence path, so G0 and G1 could never be counted by
scripts/control-liveness.py: the gate could run every day and the record would
still say it never had. The validator now requires each gate-producing command
to name where its record goes.

The repository, minus .git, is copied into a throwaway directory once; each case
strips every `evidence/` reference from one command there, runs the REAL script
(it finds its root from its own location), and restores the file.

Needs PyYAML (ci/requirements.txt).

    python test/validate-platform.test.py
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "validate-platform.py"
COMMANDS = ["idea", "ready", "design", "self-review", "qa-gate", "security-gate", "ai-gate", "release"]
failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def run(root: Path):
    p = subprocess.run([sys.executable, str(root / "scripts" / SCRIPT.name)],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    return p.returncode, p.stdout + p.stderr


rc, out = run(ROOT)
check("the real repository passes", rc == 0, f"rc={rc}\n{out[-600:]}")

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp) / "tree"
    shutil.copytree(ROOT, root, ignore=shutil.ignore_patterns(".git"))
    rc, out = run(root)
    check("an unmodified copy passes", rc == 0, f"rc={rc}\n{out[-600:]}")

    for name in COMMANDS:
        path = root / ".claude" / "commands" / f"{name}.md"
        original = path.read_text(encoding="utf-8")
        path.write_text(original.replace("evidence/", "EVID/"), encoding="utf-8")
        try:
            rc, out = run(root)
            check(f"/{name} naming no evidence/ path fails the validator",
                  rc == 1 and f"{name}.md" in out and "evidence/" in out, f"rc={rc}\n{out[-400:]}")
        finally:
            path.write_text(original, encoding="utf-8")

    path = root / ".claude" / "commands" / "ready.md"
    original = path.read_text(encoding="utf-8")
    path.unlink()
    rc, out = run(root)
    check("a missing gate command fails the validator", rc == 1 and "ready.md" in out, f"rc={rc}\n{out[-400:]}")
    path.write_text(original, encoding="utf-8")

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)
print("\nall passed")
