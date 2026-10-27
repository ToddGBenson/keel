#!/usr/bin/env python3
"""
keel's own wiring of the POA&M due-date check. Refs: TheHub #60977, keel #146 review

PROJECT-OWNED, unlike test/poam.test.py. These checks read ci/ (merge_required:
a fork adapts its pipeline), and a platform-owned test must open no ci/ or
.github/ file (test/supply-chain.test.py enforces that), so a fork can edit this
one when it moves the lane.

  * the platform-integrity job is triggered by daily-0600 and runs
    ci/tasks/platform-integrity.yml, which runs ci/scripts/platform-integrity.sh;
  * that script runs `scripts/poam.py --check --history`, so an overdue open
    High/Critical turns the lane red the next morning, and lowering its Risk does
    not get it past the lane (keel #146 review).

    python test/poam-wiring.test.py
"""
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


pipeline = (ROOT / "ci" / "pipeline.yml").read_text(encoding="utf-8")
m = re.search(r"^  - name: platform-integrity\n(.*?)(?=^  - name: |\Z)", pipeline, re.M | re.S)
job = m.group(1) if m else ""
check("platform-integrity is triggered by daily-0600",
      re.search(r"get: daily-0600\s*\n\s*trigger: true", job) is not None, job)
check("platform-integrity runs ci/tasks/platform-integrity.yml",
      "file: repo/ci/tasks/platform-integrity.yml" in job)
task = (ROOT / "ci" / "tasks" / "platform-integrity.yml").read_text(encoding="utf-8")
check("that task runs ci/scripts/platform-integrity.sh",
      "repo/ci/scripts/platform-integrity.sh" in task)
script = (ROOT / "ci" / "scripts" / "platform-integrity.sh").read_text(encoding="utf-8")
live = [ln for ln in script.splitlines() if not ln.lstrip().startswith("#")]
check("platform-integrity.sh runs `scripts/poam.py --check --history`",
      any(re.search(r"\bscripts/poam\.py --check --history\b", ln) for ln in live))

print()
if failures:
    print(f"{len(failures)} FAILED")
    sys.exit(1)
print("all passed")
