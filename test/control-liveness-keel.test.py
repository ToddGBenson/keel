#!/usr/bin/env python3
"""
keel's own control-liveness numbers. Refs: TheHub #60981, POAM-018, keel #148 review

Project-owned, unlike test/control-liveness.test.py: these assertions are about
keel's evidence, which a fork does not have.

  * The G3 grandfather list (`.control-liveness-legacy.json`) is frozen at the
    15 self-reviews written before a record needed a `verdict:` line. The PO
    decided to keep it (keel #148 review); it must not grow.
  * The numbers POAM-018 states are the numbers the baseline holds. #148 wrote
    "G3 15" into POAM-018 while `.control-liveness.json` said 16.
  * POAM-018 does not claim that a committed record proves a gate ran.

    python test/control-liveness-keel.test.py
"""
import importlib.util
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


spec = importlib.util.spec_from_file_location("cl_keel", ROOT / "scripts" / "control-liveness.py")
cl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cl)

FROZEN = {"0", "13", "42", "44", "48", "50", "52", "56", "58", "61", "63", "65", "67", "70", "143"}

print("the G3 grandfather list")
legacy_file = ROOT / ".control-liveness-legacy.json"
try:
    legacy = set(json.loads(legacy_file.read_text(encoding="utf-8")).get("g3", []))
except (OSError, ValueError, AttributeError) as e:
    legacy = None
    check(f"{legacy_file.name} exists and is a JSON object", False, str(e))
if legacy is not None:
    check("it names exactly the 15 self-reviews that predate the verdict line (frozen)",
          legacy == FROZEN, f"extra={sorted(legacy - FROZEN)} missing={sorted(FROZEN - legacy)}")
    for k in sorted(FROZEN, key=int):
        d = ROOT / "evidence" / k / "g3"
        check(f"evidence/{k}/g3 holds a non-empty record", d.is_dir() and any(
            p.is_file() and p.stat().st_size > 0 for p in d.rglob("*.md")))

manifest = (ROOT / "platform" / "MANIFEST.yml").read_text(encoding="utf-8")
proj = manifest.split("project_owned:", 1)[1]
check(f"{legacy_file.name} is project-owned in platform/MANIFEST.yml",
      re.search(r"^\s*-\s+\.control-liveness-legacy\.json\s*(#.*)?$", proj, re.M) is not None)

print("\nPOAM-018 states the measured numbers")
measured = cl.gate_liveness()
baseline = json.loads((ROOT / ".control-liveness.json").read_text(encoding="utf-8"))["gates"]
# Not equality: a new record legitimately raises today's count above the
# baseline until somebody re-baselines, and --check already fails a drop.
check("today's G3 count is at least the baseline's (the legacy file loaded)",
      measured["g3"] >= baseline["g3"], f"measured={measured} baseline={baseline}")

poam = (ROOT / "docs" / "compliance" / "poam.md").read_text(encoding="utf-8")
section = poam.split("### POAM-018", 1)[1].split("\n### ", 1)[0]
paras = re.findall(r"^\*\*Re-measured[^\n]*(?:\n(?!\n)[^\n]*)*", section, re.M)
check("POAM-018 has a re-measured paragraph", bool(paras))
if paras:
    latest = paras[-1]
    stated = {}
    for g, n in re.findall(r"\bG([0-5])\** (\d+)\b", latest):
        stated.setdefault(f"g{g}", int(n))
    check("the latest re-measure in POAM-018 states all six gates", len(stated) == 6, str(stated))
    check("the numbers POAM-018 states are the baseline's numbers", stated == baseline,
          f"stated={stated} baseline={baseline}")

row = next((ln for ln in poam.splitlines() if ln.startswith("| POAM-018 ")), "")
check("POAM-018's register row exists", bool(row))
check("POAM-018's row says a committed record proves a record exists, not that the gate ran",
      "proves a record exists, not that the gate ran" in row, row[-300:])
check("POAM-018 no longer says a gate 'has fired' because a record was committed",
      not re.search(r"has fired|fired once", row + section), "")

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)
print("\nall passed")
