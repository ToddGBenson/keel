#!/usr/bin/env python3
"""
Tests that scripts/control-liveness.py counts gate RECORDS, not directories.
Refs: TheHub #60981, POAM-018

The script used to count `glob(evidence/*/g<n>)`. Two consequences:

  * an empty `evidence/x/g1/` counted as a gate that fired, so `mkdir` was
    enough to make a dead gate look alive;
  * G5 could never count at all: /release writes
    `evidence/releases/<version>/change-record.md`, which `evidence/*/g5`
    never matches.

A gate now counts once per work item (or release) when a file under that gate's
directory carries a `verdict: pass|fail` line.

Each case copies the REAL script into a throwaway tree (it finds its root from
its own location), builds the evidence fixture there, and imports it.

    python test/control-liveness.test.py
"""
import importlib.util
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "control-liveness.py"
failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def load(root: Path):
    spec = importlib.util.spec_from_file_location(f"cl_{id(root)}", root / "scripts" / SCRIPT.name)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def counts(files: dict[str, str], dirs: tuple[str, ...] = ()) -> dict[str, int]:
    """Gate counts for a tree holding exactly `files` (path -> text) and `dirs`."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "scripts").mkdir()
        shutil.copy(SCRIPT, root / "scripts" / SCRIPT.name)
        (root / "evidence").mkdir()
        for d in dirs:
            (root / d).mkdir(parents=True, exist_ok=True)
        for rel, text in files.items():
            p = root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text, encoding="utf-8")
        return load(root).gate_liveness()


PASS = "# G1 - hub-1\n\nkey: hub-1\ndate: 2026-10-23\nverdict: pass\n"
FAIL = "# G1 - 7\n\nkey: 7\ndate: 2026-10-23\nverdict: fail\n"

print("empty and verdict-less directories")
c = counts({}, dirs=("evidence/12/g1", "evidence/hub-3/g0"))
check("an empty evidence/x/g1/ does not count", c["g1"] == 0, f"g1={c['g1']}")
check("an empty evidence/x/g0/ does not count", c["g0"] == 0, f"g0={c['g0']}")

c = counts({"evidence/12/g1/notes.md": "We talked about the verdict: maybe later.\n"})
check("a file with no verdict line does not count", c["g1"] == 0, f"g1={c['g1']}")

c = counts({"evidence/12/g1/ready.md": "verdict: maybe\n"})
check("a verdict other than pass|fail does not count", c["g1"] == 0, f"g1={c['g1']}")

print("\npopulated directories")
c = counts({"evidence/hub-1/g1/ready.md": PASS})
check("a g1 record with `verdict: pass` counts", c["g1"] == 1, f"g1={c['g1']}")

c = counts({"evidence/7/g1/ready.md": FAIL})
check("a g1 record with `verdict: fail` counts (a rejection is the gate firing)",
      c["g1"] == 1, f"g1={c['g1']}")

c = counts({"evidence/7/g1/ready.md": FAIL + "\n---\n\n" + PASS,
            "evidence/hub-1/g1/ready.md": PASS,
            "evidence/hub-1/g0/intake.md": PASS})
check("counts once per work item, not once per verdict line", c["g1"] == 2, f"g1={c['g1']}")
check("g0 counts independently of g1", c["g0"] == 1, f"g0={c['g0']}")

c = counts({"evidence/9/g4/qa/traceability.md": "verdict: pass\n"})
check("a record nested under the gate directory counts (g4/qa/)", c["g4"] == 1, f"g4={c['g4']}")

print("\nrelease records (G5)")
c = counts({"evidence/releases/1.2.0/change-record.md": "# Change record 1.2.0\n\nverdict: pass\n"})
check("evidence/releases/<v>/change-record.md counts toward g5", c["g5"] == 1, f"g5={c['g5']}")

c = counts({"evidence/releases/1.2.0/change-record.md": ""})
check("an empty change-record.md does not count", c["g5"] == 0, f"g5={c['g5']}")

c = counts({}, dirs=("evidence/releases/1.3.0",))
check("an empty release directory does not count", c["g5"] == 0, f"g5={c['g5']}")

c = counts({"evidence/releases/1.2.0/sbom-notes.md": "verdict: pass\n"})
check("only change-record.md is the release record", c["g5"] == 0, f"g5={c['g5']}")

print("\nG3 records written before verdict lines were required")
c = counts({"evidence/999/g3/self-review.md": "# Self-review\n\nno verdict line\n"})
check("a NEW g3 record without a verdict line does not count", c["g3"] == 0, f"g3={c['g3']}")

c = counts({"evidence/999/g3/self-review.md": "# Self-review\n\nverdict: pass\n"})
check("a NEW g3 record with a verdict line counts", c["g3"] == 1, f"g3={c['g3']}")

c = counts({"evidence/143/g3/.keep": ""}, dirs=("evidence/143/g3",))
check("a grandfathered key with only an empty file does not count", c["g3"] == 0, f"g3={c['g3']}")

real = load(ROOT)
legacy = getattr(real, "LEGACY_G3_KEYS", None)
check("the grandfathered g3 set is frozen at the 15 records that predate the rule",
      legacy is not None and len(legacy) == 15, f"legacy={legacy!r}")
c = real.gate_liveness()
check("the real repository still counts its 15 historical g3 records", c["g3"] == 15, f"g3={c['g3']}")

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)
print("\nall passed")
