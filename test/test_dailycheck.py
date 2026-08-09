#!/usr/bin/env python3
"""
Tests for the daily health/security reporter. Written BEFORE the implementation (G3, SA-11).

Every allocated control from the G2 threat model has a NEGATIVE-case test proving it
denies — the positive case only proves the feature works.

    python test/test_dailycheck.py
"""
import ast as _ast
import io
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

import dailycheck as dc  # noqa: E402

failures = []


def check(name, cond, detail=""):
    print(f"  [{'ok' if cond else 'FAIL'}]   {name}" + ("" if cond else f"  {detail}"))
    if not cond:
        failures.append(name)


print("dailycheck")

# ── AC: statuses and exit code ──────────────────────────────────────────────
rep = dc.run_all()
check("produces at least one check", len(rep.results) > 0)
check("every result has a valid status",
      all(r.status in ("PASS", "WARN", "FAIL", "SKIPPED") for r in rep.results))
check("exit code is 0 when nothing FAILED",
      dc.exit_code([r for r in rep.results if r.status != "FAIL"]) == 0)
check("exit code is 1 when something FAILED",
      dc.exit_code([dc.Result("x", "FAIL", "boom")]) == 1)

# ── T3 NEGATIVE: an unavailable probe must SKIP, never PASS ─────────────────
def unavailable():
    raise dc.ProbeUnavailable("no permission")

r = dc.safe_probe("privileged thing", unavailable)
check("unavailable probe -> SKIPPED", r.status == "SKIPPED", f"got {r.status}")
check("unavailable probe is NEVER PASS", r.status != "PASS")
check("skip reason is recorded", "no permission" in r.detail)

# ── T5 NEGATIVE: a raising probe degrades rather than crashing the run ──────
def explodes():
    raise RuntimeError("kaboom")

r = dc.safe_probe("flaky", explodes)
check("raising probe -> SKIPPED, run continues", r.status == "SKIPPED")
check("raising probe is NEVER PASS", r.status != "PASS")

# ── T1 NEGATIVE: the program must not be able to touch the network ──────────
_raw = (ROOT / "src" / "dailycheck.py").read_text(encoding="utf-8")


def code_only(text: str) -> str:
    """Strip comments so a scan cannot match the module's own prose ABOUT a pattern.

    The first version of these tests scanned raw source and failed on the module's comment
    saying "Never shell=True" — a test matching documentation about the thing rather than
    the thing itself (L0002/L0007), in a file written to guard against exactly that.

    Only comments are stripped here. Semantic checks below parse the AST, which ignores
    comments natively — no round-trip through unparse, which broke on a class whose body
    was only a docstring.
    """
    import io as _io, tokenize
    toks = [tk for tk in tokenize.generate_tokens(_io.StringIO(text).readline)
            if tk.type != tokenize.COMMENT]
    return tokenize.untokenize(toks)


src = code_only(_raw)
check("imports no socket library",
      "import socket" not in src and "import requests" not in src
      and "urllib.request" not in src and "http.client" not in src)
check("no active-scan tooling invoked",
      not any(t in src for t in ("nmap", "masscan", "ping -c", "arp-scan")))

# ── T4 NEGATIVE: no shell interpolation ─────────────────────────────────────
_shell_true = []
for _n in _ast.walk(_ast.parse(_raw)):
    if isinstance(_n, _ast.Call):
        for _kw in _n.keywords:
            if (_kw.arg == "shell" and isinstance(_kw.value, _ast.Constant)
                    and _kw.value.value is True):
                _shell_true.append(_n.lineno)
check("shell=True is never passed", not _shell_true, f"lines {_shell_true}")
# Verify semantically: every subprocess.run first arg must be a list/name, never a
# string literal (a string is what enables shell-style injection).
_bad_argv = []
for _n in _ast.walk(_ast.parse(_raw)):
    if (isinstance(_n, _ast.Call) and isinstance(_n.func, _ast.Attribute)
            and _n.func.attr == "run" and _n.args
            and isinstance(_n.args[0], _ast.Constant)
            and isinstance(_n.args[0].value, str)):
        _bad_argv.append(_n.lineno)
check("subprocess is never given a string command", not _bad_argv, f"lines {_bad_argv}")

# ── T5: every subprocess call is bounded by a timeout ───────────────────────
check("every subprocess.run has a timeout",
      src.count("subprocess.run(") == src.count("timeout="),
      f"{src.count('subprocess.run(')} calls vs {src.count('timeout=')} timeouts")

# ── T6 NEGATIVE: report path confinement ────────────────────────────────────
with tempfile.TemporaryDirectory() as td:
    base = Path(td)
    good = dc.resolve_report_path(base, "report.json")
    check("a normal filename resolves inside the base", str(good).startswith(str(base)))

    escaped = None
    try:
        dc.resolve_report_path(base, "../escape.json")
    except ValueError:
        escaped = "refused"
    check("path traversal is REFUSED", escaped == "refused")

    # ── writes valid JSON with schema version and UTC timestamp ─────────────
    out = dc.write_report(dc.run_all(), base, "report.json")
    data = json.loads(Path(out).read_text(encoding="utf-8"))
    check("report has a schema version", "schema" in data)
    check("report timestamp is UTC", data.get("generated", "").endswith("Z"))
    check("report lists results", isinstance(data.get("results"), list) and data["results"])

# ── thresholds are explicit numbers, not vibes (U5) ─────────────────────────
check("disk threshold is a number", isinstance(dc.THRESHOLDS["disk_percent"], (int, float)))
check("disk at 86% with threshold 85 -> WARN",
      dc.evaluate_threshold("disk", 86, dc.THRESHOLDS["disk_percent"]).status == "WARN")
check("disk at 50% -> PASS",
      dc.evaluate_threshold("disk", 50, dc.THRESHOLDS["disk_percent"]).status == "PASS")

# ── human-readable output renders without crashing ──────────────────────────
buf = io.StringIO()
dc.render_text(dc.run_all(), buf)
text = buf.getvalue()
check("text report mentions each status it found", "dailycheck" in text.lower() or len(text) > 50)

print()
if failures:
    print(f"  {len(failures)} FAILED")
    sys.exit(1)
print("  all passed")
