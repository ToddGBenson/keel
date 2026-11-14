#!/usr/bin/env python3
"""
The AIC-12 behavioral record says what is true. Refs: TheHub #61208

docs/11-ai-agent-controls.md, docs/compliance/ai-inventory.md, evals/agents/README.md
and .claude/agents/ai-risk-officer.md all send the monthly behavioral agent-eval
results to evidence/ai-assurance/agent-evals/. Until TheHub #61208 that folder did
not exist, so the docs described a record nobody had ever written, and nothing
said so. These checks keep the record, the inventory and the eval run in step:

  * evidence/ai-assurance/agent-evals/README.md exists (the index of runs);
  * a run is a dated folder (YYYY-MM-DD) with at least one file in it;
  * with no run recorded, the README and AIC-12 in ai-inventory.md both say so
    and both name the same "First run due" date;
  * with a run recorded, neither says "not recorded yet", and AIC-12 names the
    latest run's date;
  * `bash evals/run-agent-evals.sh` prints the behavioral status: no run yet
    (and OVERDUE once the due date has passed), or the last run's date. The
    clock is pinned with AGENT_EVALS_TODAY, so this test does not change
    verdict as the real date moves.

PROJECT-OWNED: it reads keel's own evidence/ and ai-inventory.md, which a fork
replaces with its own.

    python test/agent-evals-record.test.py
"""
import datetime as dt
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RECORD = ROOT / "evidence" / "ai-assurance" / "agent-evals"
INDEX = RECORD / "README.md"
NOT_YET = "No behavioral run has been recorded yet"
failures = []
# The eval output has non-ASCII; a cp1252 console must not crash the report.
sys.stdout.reconfigure(errors="replace")


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def read(path):
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return ""


def due_date(text):
    m = re.search(r"First run due:\s*\**\s*(\d{4}-\d{2}-\d{2})", text)
    return m.group(1) if m else None


def run_evals(today):
    env = dict(os.environ, AGENT_EVALS_TODAY=today)
    p = subprocess.run(["bash", "evals/run-agent-evals.sh"], cwd=ROOT, env=env,
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    # The structural half may fail on a machine without PyYAML; the behavioral
    # status line is printed either way, and it is what this test is about.
    return p.stdout + p.stderr


check("evidence/ai-assurance/agent-evals/README.md exists", INDEX.is_file(), str(INDEX))
index = read(INDEX)

runs = sorted(d.name for d in RECORD.iterdir()
              if d.is_dir() and re.fullmatch(r"\d{4}-\d{2}-\d{2}", d.name)
              and any(f.is_file() for f in d.rglob("*"))) if RECORD.is_dir() else []

inventory = read(ROOT / "docs" / "compliance" / "ai-inventory.md")
m = re.search(r"\*\*Agent evaluation \(AIC-12\)\.\*\*(.*?)(?=\n\n|\Z)", inventory, re.S)
aic12 = m.group(1) if m else ""
check("ai-inventory.md has an AIC-12 agent evaluation paragraph", bool(aic12))
check("AIC-12 names the record folder",
      "evidence/ai-assurance/agent-evals/" in aic12, aic12)

if not runs:
    due = due_date(index)
    check(f"the record README says '{NOT_YET}'", NOT_YET in index)
    check("the record README names a 'First run due: YYYY-MM-DD' date", due is not None)
    check(f"AIC-12 says '{NOT_YET}'", NOT_YET in aic12, aic12)
    check("AIC-12 names the same first-run due date", due is not None and due in aic12,
          f"README due={due}")
    if due:
        d = dt.date.fromisoformat(due)
        before = run_evals((d - dt.timedelta(days=1)).isoformat())
        check("run-agent-evals.sh says no behavioral run is recorded yet",
              "no behavioral run recorded yet" in before, before[-600:])
        check("run-agent-evals.sh names the due date", due in before, before[-600:])
        check("run-agent-evals.sh is not OVERDUE the day before the due date",
              "OVERDUE" not in before, before[-600:])
        after = run_evals((d + dt.timedelta(days=1)).isoformat())
        check("run-agent-evals.sh says OVERDUE the day after the due date",
              "OVERDUE" in after, after[-600:])
else:
    latest = runs[-1]
    check(f"the record README no longer says '{NOT_YET}'", NOT_YET not in index)
    check(f"AIC-12 no longer says '{NOT_YET}'", NOT_YET not in aic12, aic12)
    check(f"AIC-12 names the latest run ({latest})", latest in aic12, aic12)
    check(f"the record README lists the latest run ({latest})", latest in index)
    out = run_evals(latest)
    check(f"run-agent-evals.sh names the last behavioral run ({latest})",
          f"last behavioral run: {latest}" in out, out[-600:])

print()
if failures:
    print(f"{len(failures)} FAILED")
    sys.exit(1)
print("all passed")
