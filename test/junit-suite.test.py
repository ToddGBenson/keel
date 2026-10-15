#!/usr/bin/env python3
"""
Tests for scripts/junit-suite.py — the wrapper that turns this repository's own
test output into the JUnit XML MyKronos's `unit` capability reads.

The property that matters is the negative one: **a suite that did not run must
never read as a suite that passed.** MyKronos counts testcases and failures; a
report with zero failures is green. So every way a suite can fail to produce
evidence — the command is missing, the interpreter is missing, the suite crashes
part-way, the suite exits 0 having printed nothing — is a case here, and each
must surface as a failure or an error in the XML.

    python test/junit-suite.test.py
"""
import os
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "junit-suite.py"

failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def run(name, argv, out):
    """Run the wrapper; return (exit code, parsed <testsuite> or None)."""
    proc = subprocess.run(
        [sys.executable, str(SCRIPT), "--name", name, "--out", str(out), "--", *argv],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    path = Path(out) / f"{name}.xml"
    try:
        suite = ET.parse(path).getroot() if path.exists() else None
    except ET.ParseError:
        suite = None  # unparseable is as useless to MyKronos as absent
    return proc.returncode, suite


def counts(suite):
    return {k: int(suite.get(k, "0")) for k in ("tests", "failures", "errors", "skipped")}


def py(code):
    """A child suite, written as a python one-liner so the test needs no fixtures."""
    return [sys.executable, "-c", code]


print("junit-suite wrapper")

with tempfile.TemporaryDirectory() as tmp:
    check("the wrapper script exists", SCRIPT.is_file(), str(SCRIPT))

    # ── a passing suite ──────────────────────────────────────────────────────
    rc, s = run("green", py("print('  [ok]   one'); print('  [ok]   two')"), tmp)
    check("passing suite: XML written", s is not None)
    if s is not None:
        c = counts(s)
        check("passing suite: two cases, none failing",
              c == {"tests": 2, "failures": 0, "errors": 0, "skipped": 0}, str(c))
        check("passing suite: suite is named", s.get("name") == "green", s.get("name"))
    check("passing suite: wrapper exits 0", rc == 0, f"rc={rc}")

    # ── a failing case is a failing case ─────────────────────────────────────
    rc, s = run("red", py(
        "import sys; print('  [ok]   fine'); print('  [FAIL] broken expected x');"
        " sys.exit(1)"), tmp)
    if s is not None:
        c = counts(s)
        check("failing case: counted as a failure", c["failures"] >= 1, str(c))
        names = [tc.get("name") for tc in s.iter("testcase") if tc.find("failure") is not None]
        check("failing case: the failing case is named", any("broken" in n for n in names), str(names))
    else:
        check("failing case: XML written", False)
    check("failing case: wrapper exits non-zero", rc != 0, f"rc={rc}")

    # ── a crash after some passes is not a pass ──────────────────────────────
    rc, s = run("crash", py(
        "import sys; print('  [ok]   first'); sys.stderr.write('Traceback: boom\\n'); sys.exit(3)"),
        tmp)
    if s is not None:
        c = counts(s)
        check("crash: non-zero exit is a failure even with every printed case ok",
              c["failures"] + c["errors"] >= 1, str(c))
    else:
        check("crash: XML written", False)
    check("crash: wrapper exits non-zero", rc != 0, f"rc={rc}")

    # ── the command does not exist ───────────────────────────────────────────
    rc, s = run("missing", ["definitely-not-a-command-keel-junit"], tmp)
    if s is not None:
        c = counts(s)
        check("missing command: an error, not a pass", c["failures"] + c["errors"] >= 1, str(c))
        check("missing command: at least one testcase (zero cases reads as 'nothing ran')",
              c["tests"] >= 1, str(c))
    else:
        check("missing command: XML still written", False)
    check("missing command: wrapper exits non-zero", rc != 0, f"rc={rc}")

    # ── the test file does not exist (a glob that matched nothing) ───────────
    rc, s = run("nofile", [sys.executable, "test/no-such-file.test.py"], tmp)
    if s is not None:
        c = counts(s)
        check("missing test file: an error, not a pass", c["failures"] + c["errors"] >= 1, str(c))
    else:
        check("missing test file: XML still written", False)

    # ── exit 0 with no cases printed is not evidence ─────────────────────────
    rc, s = run("silent", py("pass"), tmp)
    if s is not None:
        c = counts(s)
        check("silent exit 0: reported as an error", c["errors"] >= 1, str(c))
    else:
        check("silent exit 0: XML still written", False)
    check("silent exit 0: wrapper exits non-zero", rc != 0, f"rc={rc}")

    # ── the evals' tick format, with colour codes ────────────────────────────
    rc, s = run("ticks", py(
        "print('  \\x1b[32m\\u2713\\x1b[0m developer.md: test-first');"
        " print('  \\x1b[31m\\u2717\\x1b[0m qa.md: lost a control'); import sys; sys.exit(1)"), tmp)
    if s is not None:
        c = counts(s)
        check("tick format: one pass and one failure", c["tests"] >= 2 and c["failures"] >= 1, str(c))
        names = [tc.get("name") for tc in s.iter("testcase")]
        check("tick format: ANSI colour stripped from names",
              not any("\x1b" in (n or "") for n in names), str(names))
    else:
        check("tick format: XML written", False)

    # ── output that would break XML ──────────────────────────────────────────
    rc, s = run("hostile", py(
        "print('  [ok]   <script>&\"\\x07</script>')"), tmp)
    check("hostile output: still parseable XML", s is not None)

print()
if failures:
    print(f"  {len(failures)} FAILED")
    sys.exit(1)
print("  all passed")
