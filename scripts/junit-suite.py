#!/usr/bin/env python3
"""
Run one of this repository's test suites and write what it did as JUnit XML.

    python scripts/junit-suite.py --name selftest --out "$DIR" -- bash .claude/hooks/selftest.sh

Writes <out>/<name>.xml and exits with the suite's own exit code (or 1 if the
suite's evidence is unusable), so a caller can run it under `continue-on-error`
and still know the outcome. Tested by test/junit-suite.test.py.

WHY THIS EXISTS. MyKronos's `unit` capability reads JUnit XML (MyKronos D-046)
and records a run, its case count and its failures — never findings. None of
this repository's suites emits JUnit: they print one line per assertion in a
shared convention,

    [ok]   <name>           test/*.test.py, test/*.test.js, .claude/hooks/selftest.sh
    [FAIL] <name> <detail>
    ✓ <name> / ✗ <name>     evals/run-agent-evals.sh

so this reads those lines rather than asking each suite to change how it
reports. Adding a JUnit writer to every suite would be four edits to keep in
step; this is one.

THE RULE IT IS BUILT AROUND: a suite that did not run must never read as a
suite that passed. MyKronos counts failures, so a report with zero of them is
green. Hence, beyond the per-line cases:

  - a non-zero exit is always a failing testcase, even if every printed line
    was [ok] -- a crash after the tenth assertion is not ten passes;
  - a command that cannot start (missing interpreter, missing file) is an
    error testcase, never an absent report;
  - an exit of 0 with no case lines is an ERROR: "ran and asserted nothing"
    is not evidence, and an empty report would be recorded as
    no_applicable_targets, which reads as "nothing to test" rather than
    "something is wrong".

If this script itself cannot run, no XML is written, and the MyKronos uploader
records the run as FAILURE ("no *.xml files ... produced no output") -- which
is the right answer for that case too.
"""
import argparse
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
# Characters XML 1.0 cannot carry at all, escaped or not. A test that prints a
# bell character must not make the whole report unparseable.
# A translate table, not a regex character range: CodeQL's py/overly-large-range
# reads the 0x0E-0x1F span as a suspicious range and fails the sast gate on it.
XML_ILLEGAL = dict.fromkeys(
    [*range(0x00, 0x09), 0x0B, 0x0C, *range(0x0E, 0x20), 0xFFFE, 0xFFFF], "?"
)

PASS_LINE = re.compile(r"^\s*(?:\[ok\]|✓)\s+(.*\S)\s*$")
FAIL_LINE = re.compile(r"^\s*(?:\[FAIL\]|✗)\s+(.*\S)\s*$")

TAIL_LINES = 60  # of output attached to a suite-level failure


def clean(text: str) -> str:
    return ANSI.sub("", text).translate(XML_ILLEGAL)


def parse_cases(output: str) -> list[tuple[str, bool]]:
    """(name, passed) for every case line, in order."""
    cases = []
    for raw in output.splitlines():
        line = clean(raw)
        m = PASS_LINE.match(line)
        if m:
            cases.append((m.group(1), True))
            continue
        m = FAIL_LINE.match(line)
        if m:
            cases.append((m.group(1), False))
    return cases


def run(argv: list[str]) -> tuple[int, str, float]:
    start = time.monotonic()
    try:
        proc = subprocess.run(
            argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, encoding="utf-8", errors="replace",
            # A Python suite writing to a pipe uses the locale encoding, which
            # on some hosts cannot encode the evals' tick marks and crashes the
            # suite on its first case. Read as UTF-8 above, so write it too.
            env={**os.environ, "PYTHONIOENCODING": "utf-8"},
        )
        code, out = proc.returncode, proc.stdout or ""
    except OSError as exc:  # not found, not executable
        code, out = 127, f"could not start {argv[0]!r}: {exc}\n"
    return code, out, time.monotonic() - start


def build(name: str, argv: list[str], code: int, output: str, elapsed: float) -> ET.Element:
    suite = ET.Element("testsuite", name=name, time=f"{elapsed:.3f}")
    cases = parse_cases(output)
    tail = clean("\n".join(output.splitlines()[-TAIL_LINES:]))
    failures = errors = 0

    for case_name, passed in cases:
        tc = ET.SubElement(suite, "testcase", classname=name, name=case_name)
        if not passed:
            ET.SubElement(tc, "failure", message=case_name[:500])
            failures += 1

    command = " ".join(argv)
    if code != 0:
        # The suite's own verdict, as a case of its own. Without it a suite
        # that crashed after printing only [ok] lines would be all green.
        tc = ET.SubElement(suite, "testcase", classname=name, name=f"{name}: exit status")
        el = ET.SubElement(tc, "failure", message=f"`{command}` exited {code}")
        el.text = tail
        failures += 1
    elif not cases:
        tc = ET.SubElement(suite, "testcase", classname=name, name=f"{name}: reported no cases")
        el = ET.SubElement(
            tc, "error",
            message=f"`{command}` exited 0 but printed no [ok]/[FAIL] lines; nothing is known to have been tested",
        )
        el.text = tail
        errors += 1

    total = len(cases) + (1 if code != 0 or not cases else 0)
    suite.set("tests", str(total))
    suite.set("failures", str(failures))
    suite.set("errors", str(errors))
    suite.set("skipped", "0")
    ET.SubElement(suite, "system-out").text = clean(output)
    return suite


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--name", required=True, help="suite name; also the XML file name")
    ap.add_argument("--out", required=True, help="directory to write <name>.xml into")
    ap.add_argument("command", nargs=argparse.REMAINDER, help="-- then the suite command")
    args = ap.parse_args()

    argv = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not argv:
        ap.error("no suite command given after --")
    if not re.fullmatch(r"[A-Za-z0-9._-]+", args.name):
        ap.error("--name must be a plain file-name token")

    code, output, elapsed = run(argv)

    # The report first: nothing after this point may stop it being written.
    suite = build(args.name, argv, code, output, elapsed)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(suite).write(out / f"{args.name}.xml", encoding="utf-8", xml_declaration=True)

    # Then the build log still shows the suite as it ran. `replace` because a
    # console that cannot print a tick mark is no reason to fail the step.
    sys.stdout.reconfigure(errors="replace")
    sys.stdout.write(output)

    bad = int(suite.get("failures")) + int(suite.get("errors"))
    print(f"junit-suite: {args.name}: {suite.get('tests')} case(s), {bad} failing, exit {code}")
    if code != 0:
        return code
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
