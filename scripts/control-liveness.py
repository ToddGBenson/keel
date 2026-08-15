#!/usr/bin/env python3
"""Has each control ever actually fired? Refs: #67

A control that has never rejected anything is indistinguishable from a control
that CANNOT reject anything. Both look identical on an assessment: green, quiet,
apparently working. The difference only appears the day something bad reaches
the gate, which is the worst possible moment to discover it.

This repository ran that experiment on itself without meaning to. Six gates are
documented; five have never produced a single record. Fourteen controls in the
NIST map were marked satisfied on the strength of gates that had never run
(POAM-018). Nothing detected that, because nothing was measuring *use* — only
existence.

    python scripts/control-liveness.py           # report
    python scripts/control-liveness.py --check    # regression gate (CI)

WHAT THE ZEROS MEAN IN A TEMPLATE (read this before "fixing" them)
------------------------------------------------------------------
keel ships no product, so G2 and G4 have nothing to design or verify. Those
zeros are structural, not neglect — the same property that makes container-scan
inert here and live in a fork that ships an image (ADR-0004 §D3, L0017).

**Do not make this number go up by adding product code to the platform.** That
does not exercise the gates; it ends the template. If a metric can only be
improved by destroying the thing it measures, it is measuring the wrong subject.

The zeros close when a reference fork's gate evidence exists and the control map
is scoped to say "provided here, demonstrated downstream". Until then this check
has one job: stop the pile growing.

WHY THIS DOES NOT FAIL ON THE EXISTING ZEROS
--------------------------------------------
A check that is red from the day it is introduced gets muted, and then the
signal is worse than nothing (docs/lessons/0007). The zeros here are known,
accepted and recorded in POAM-018 — printing them loudly is the point, failing
on them is theatre.

So `--check` fails on REGRESSION against `.control-liveness.json`:

  * a gate that had evidence and now has none
  * a NEW control claim citing a gate that has never fired
  * the baseline going stale (someone stopped looking)

Ratchet, not alarm. The zeros are allowed to persist and are NOT allowed to grow.
"""

from __future__ import annotations

import argparse
import glob
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / ".control-liveness.json"
CONTROL_MAP = ROOT / "docs" / "compliance" / "nist-800-53-control-map.md"
GATES = ["g0", "g1", "g2", "g3", "g4", "g5"]
GATE_NAMES = {
    "g0": "Intake", "g1": "Ready", "g2": "Designed",
    "g3": "Code Complete", "g4": "Verified", "g5": "Release Authorized",
}
# A baseline older than this means nobody has looked; that is itself the finding.
STALE_DAYS = 120


def gate_liveness() -> dict[str, int]:
    """Evidence records per gate. The only fully local signal, and the sharpest."""
    return {g: len(glob.glob(str(ROOT / "evidence" / "*" / g))) for g in GATES}


def claims_on_dead_gates(dead: set[str]) -> list[tuple[str, str]]:
    """Control rows whose justification cites a gate that has never fired.

    Matches on the row's Implementation and Evidence columns, not the whole
    line, so a control merely *named* in a gate's header does not count.
    """
    if not CONTROL_MAP.exists():
        return []
    pattern = re.compile("|".join(rf"\b{g.upper()}\b" for g in sorted(dead))) if dead else None
    found = []
    for line in CONTROL_MAP.read_text(encoding="utf-8").splitlines():
        if not line.startswith("| ") or not re.match(r"^\| [A-Z]{2}-", line):
            continue
        cols = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cols) < 5:
            continue
        control, _req, impl, evidence, status = cols[0], cols[1], cols[2], cols[3], cols[4]
        if pattern and pattern.search(f"{impl} {evidence}"):
            found.append((control, status))
    return found


def git_days_since(path: Path) -> int | None:
    """Days since a file was last committed — used for baseline staleness."""
    out = subprocess.run(
        ["git", "log", "-1", "--format=%cr", "--", str(path.relative_to(ROOT))],
        cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
    text = out.stdout.strip()
    if not text:
        return None
    m = re.match(r"(\d+)\s+(day|week|month|year)", text)
    if not m:
        return 0  # "2 hours ago" and similar
    n, unit = int(m.group(1)), m.group(2)
    return n * {"day": 1, "week": 7, "month": 30, "year": 365}[unit]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="Fail on regression against the baseline (for CI).")
    ap.add_argument("--update-baseline", action="store_true",
                    help="Record today's numbers as the new baseline.")
    args = ap.parse_args()

    gates = gate_liveness()
    dead = {g for g, n in gates.items() if n == 0}
    claims = claims_on_dead_gates(dead)
    overstated = [c for c, status in claims if "✅" in status]

    print("Control liveness")
    print("  A control that has never rejected anything is indistinguishable from")
    print("  one that cannot.\n")
    print("  Gate                      Records   Ever fired?")
    for g in GATES:
        n = gates[g]
        mark = "yes" if n else "** NEVER **"
        print(f"  {g.upper()} {GATE_NAMES[g]:<22}{n:>5}   {mark}")

    print(f"\n  {len(claims)} control claim(s) cite a gate that has never fired.")
    if overstated:
        shown = ", ".join(overstated[:8]) + ("..." if len(overstated) > 8 else "")
        print(f"  {len(overstated)} of those are still marked satisfied: {shown}")

    baseline = json.loads(BASELINE.read_text(encoding="utf-8")) if BASELINE.exists() else None

    if args.update_baseline:
        BASELINE.write_text(json.dumps(
            {"gates": gates, "overstated": sorted(overstated)}, indent=2) + "\n",
            encoding="utf-8")
        print(f"\n  baseline written: {BASELINE.name}")
        return 0

    if not args.check:
        print("\n  Reporting only. Run with --check for the regression gate.")
        return 0

    # ---- regression gate ----------------------------------------------------
    errors: list[str] = []
    if baseline is None:
        errors.append(
            f"no baseline at {BASELINE.name}. Create it with --update-baseline; "
            f"without one this check cannot tell improvement from decay.")
    else:
        for g in GATES:
            was, now = baseline["gates"].get(g, 0), gates[g]
            if was > 0 and now == 0:
                errors.append(
                    f"{g.upper()} had {was} evidence record(s) and now has none. A gate that "
                    f"stops firing is a gate that stopped being used.")
        new_claims = sorted(set(overstated) - set(baseline.get("overstated", [])))
        if new_claims:
            errors.append(
                f"new control claim(s) marked satisfied on a gate that has never fired: "
                f"{', '.join(new_claims)}. Either run the gate or mark it partial "
                f"with a POA&M reference — do not add to the pile.")

        days = git_days_since(BASELINE)
        if days is not None and days > STALE_DAYS:
            errors.append(
                f"the baseline has not been touched in ~{days} days. Nobody is looking, "
                f"which is the condition this check exists to detect.")

    for e in errors:
        print(f"\n  [ERROR] {e}")
    if errors:
        print(f"\n  {len(errors)} regression(s).")
        return 1

    print("\n  [ok]    no regression: no gate went dark, no new claim rests on a dead gate")
    if overstated:
        print(f"  [warn]  {len(overstated)} pre-existing overstated claim(s) remain "
              f"(POAM-018). Accepted, not fixed — and not allowed to grow.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
