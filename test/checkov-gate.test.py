#!/usr/bin/env python3
"""
Tests for the IaC lane's gate, ci/scripts/checkov.sh. Refs: #59989, #60071

Runs the REAL script under bash with `checkov` (and `python -m pip`) stubbed on
PATH, so what is tested is the gate's own decisions, not a re-implementation:

  * a result that stands fails the lane;
  * a result silenced at the source (a Checkov skip comment, carried as a SARIF
    suppression) does NOT -- the platform's ingest drops it, and the lane went red
    on exactly that from 2026-10-08 (CKV_GHA_7, accepted risk #99);
  * a REJECTED suppression still stands;
  * a scan that performed no check FAILS (operator decision 2026-09-23) and still
    marks the SARIF `no_applicable_targets` for the upload;
  * a scan that performed checks and found nothing passes.

    python test/checkov-gate.test.py
"""
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "ci" / "scripts" / "checkov.sh"
failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def result(rule, suppression_status=None):
    r = {"ruleId": rule, "message": {"text": rule}, "level": "error"}
    if suppression_status is not None:
        s = {"kind": "inSource"}
        if suppression_status != "absent":
            s["status"] = suppression_status
        r["suppressions"] = [s]
    return r


def run(results, checks_performed):
    tmp = Path(tempfile.mkdtemp(prefix="checkov-gate-"))
    try:
        (tmp / "repo").mkdir()
        stubs = tmp / "stubs"
        stubs.mkdir()
        sarif = {"version": "2.1.0", "runs": [{"tool": {"driver": {"name": "checkov"}},
                                                "results": results}]}
        report = {"summary": {"passed": checks_performed, "failed": 0, "skipped": 0,
                              "resource_count": 0}}
        (tmp / "stub-sarif.json").write_text(json.dumps(sarif))
        (tmp / "stub-report.json").write_text(json.dumps(report))
        real_py = shutil.which("python3") or sys.executable
        (stubs / "checkov").write_text(
            "#!/usr/bin/env bash\n"
            'if [ "${1:-}" = "--version" ]; then echo "checkov-stub"; exit 0; fi\n'
            "mkdir -p iac-results\n"
            f'cp "{(tmp / "stub-sarif.json").as_posix()}" iac-results/results_sarif.sarif\n'
            f'cp "{(tmp / "stub-report.json").as_posix()}" iac-results/results_json.json\n'
            "exit 1\n")  # checkov exits non-zero with findings; the script must not care
        (stubs / "python").write_text(
            "#!/usr/bin/env bash\n"
            'if [ "${1:-}" = "-m" ] && [ "${2:-}" = "pip" ]; then exit 0; fi\n'
            f'exec "{Path(real_py).as_posix()}" "$@"\n')
        for f in stubs.iterdir():
            f.chmod(f.stat().st_mode | stat.S_IEXEC)
        env = dict(os.environ, CHECKOV_VERSION="0.0.0-test",
                   PATH=stubs.as_posix() + os.pathsep + os.environ.get("PATH", ""))
        p = subprocess.run(["bash", SCRIPT.as_posix()], cwd=tmp, env=env,
                           capture_output=True, text=True, timeout=60)
        out_sarif = tmp / "iac-results" / "results_sarif.sarif"
        doc = json.loads(out_sarif.read_text()) if out_sarif.is_file() else {}
        return p.returncode, p.stdout + p.stderr, doc
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def marker(doc):
    return [((r.get("properties") or {}).get("mykronos") or {}).get("scanStatus")
            for r in doc.get("runs", [])]


print("checkov gate")

rc, out, _ = run([result("CKV_X_1")], checks_performed=10)
check("a standing finding fails the lane", rc == 1, f"rc={rc}")

rc, out, _ = run([result("CKV_GHA_7", "accepted")], checks_performed=716)
check("a finding suppressed at the source does not fail the lane", rc == 0, f"rc={rc}\n{out[-400:]}")
check("and the log says it was suppressed, not absent", "1 suppressed at the source" in out)

rc, out, _ = run([result("CKV_GHA_7", "absent")], checks_performed=716)
check("a suppression with no status counts as accepted (SARIF default)", rc == 0, f"rc={rc}")

rc, out, _ = run([result("CKV_X_2", "rejected")], checks_performed=10)
check("a REJECTED suppression still stands and fails the lane", rc == 1, f"rc={rc}")

rc, out, doc = run([], checks_performed=0)
check("a scan that performed no check FAILS (no vacuous pass)", rc == 1, f"rc={rc}")
check("and the SARIF still says no_applicable_targets for the upload",
      marker(doc) == ["no_applicable_targets"], f"marker={marker(doc)}")

rc, out, doc = run([], checks_performed=715)
check("checks performed and nothing found passes", rc == 0, f"rc={rc}\n{out[-400:]}")
check("and is not marked no_applicable_targets", marker(doc) == [None], f"marker={marker(doc)}")

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)
print("\nall passed")
