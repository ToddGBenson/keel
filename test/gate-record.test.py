#!/usr/bin/env python3
"""
Tests for scripts/gate-record.py, the writer behind /idea (G0) and /ready (G1).
Refs: TheHub #60981, POAM-018

The key becomes a path component under evidence/, so it is the input that
matters: anything that is not a GitHub issue number (^[0-9]+$) or a tracker id
(^[a-z]+-[0-9]+$, e.g. hub-60944) is refused and NOTHING is written. Free-text
fields are refused if they could forge a second `verdict:` line, because
scripts/control-liveness.py counts records by that line.

Each case copies the REAL script and .sdlc/process.yaml into a throwaway tree
(the script finds its root from its own location) and runs it there.

Needs PyYAML (ci/requirements.txt).

    python test/gate-record.test.py
"""
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "gate-record.py"
failures = []

G1_ALL_YES = ["ac-binary=yes", "sized=yes", "flags=yes", "no-open-question=yes"]


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


class Tree:
    def __enter__(self):
        self._tmp = tempfile.TemporaryDirectory()
        # Nested three deep, so a key that climbs out of evidence/ (../../x)
        # still lands inside the throwaway directory, where escaped() sees it.
        self.base = Path(self._tmp.name)
        self.root = self.base / "l1" / "l2" / "tree"
        (self.root / "scripts").mkdir(parents=True)
        (self.root / ".sdlc").mkdir()
        if SCRIPT.exists():
            shutil.copy(SCRIPT, self.root / "scripts" / SCRIPT.name)
        shutil.copy(ROOT / ".sdlc" / "process.yaml", self.root / ".sdlc" / "process.yaml")
        return self

    def __exit__(self, *exc):
        self._tmp.cleanup()

    def run(self, *args):
        p = subprocess.run([sys.executable, str(self.root / "scripts" / SCRIPT.name), *args],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        return p.returncode, p.stdout + p.stderr

    def written(self):
        ev = self.root / "evidence"
        return sorted(str(p.relative_to(self.root)).replace("\\", "/")
                      for p in ev.rglob("*") if p.is_file()) if ev.exists() else []

    def escaped(self):
        """Files created anywhere in the throwaway directory outside evidence/."""
        fixtures = {self.root / "scripts" / SCRIPT.name, self.root / ".sdlc" / "process.yaml"}
        ev = self.root / "evidence"
        return [str(p) for p in self.base.rglob("*")
                if p.is_file() and p not in fixtures and ev not in p.parents]


def g1(t, key, verdict="pass", items=None, role="product-owner"):
    args = ["--gate", "g1", "--key", key, "--verdict", verdict, "--role", role]
    for i in (G1_ALL_YES if items is None else items):
        args += ["--item", i]
    return t.run(*args)


print("happy path")
with Tree() as t:
    rc, out = g1(t, "42")
    check("a numeric key writes evidence/42/g1/ready.md", rc == 0 and t.written() == ["evidence/42/g1/ready.md"],
          f"rc={rc} written={t.written()}\n{out[-400:]}")
    if t.written():
        rec = (t.root / "evidence/42/g1/ready.md").read_text(encoding="utf-8")
        check("record holds the key", re.search(r"^key: 42$", rec, re.M) is not None, rec)
        check("record holds the date", re.search(r"^date: \d{4}-\d{2}-\d{2}$", rec, re.M) is not None, rec)
        check("record holds a `verdict: pass` line", re.search(r"^verdict: pass$", rec, re.M) is not None, rec)
        check("record holds the recommending role",
              re.search(r"^recommending role: product-owner$", rec, re.M) is not None, rec)
        for item in ("ac-binary", "sized", "flags", "no-open-question"):
            check(f"record marks checklist item {item}",
                  re.search(rf"^- {re.escape(item)}: satisfied$", rec, re.M) is not None, rec)

with Tree() as t:
    items = [a for i in G1_ALL_YES for a in ("--item", i)]
    rc, out = t.run("--gate", "g1", "--key", "3", "--verdict", "pass", "--role", "product-owner",
                    "--recorded-by", "developer agent (Claude Opus 5.5)", *items)
    rec = (t.root / "evidence/3/g1/ready.md").read_text(encoding="utf-8") if rc == 0 else out
    check("record names its producer", "recorded by: developer agent (Claude Opus 5.5)" in rec, rec[-300:])
    rc, out = t.run("--gate", "g1", "--key", "4", "--verdict", "pass", "--role", "product-owner",
                    "--recorded-by", "x\nverdict: fail", *items)
    check("a producer that would forge a verdict line is refused",
          rc == 2 and not (t.root / "evidence/4").exists(), f"rc={rc}\n{out[-200:]}")

with Tree() as t:
    rc, out = g1(t, "hub-60944")
    check("a tracker id (hub-60944) is accepted",
          rc == 0 and t.written() == ["evidence/hub-60944/g1/ready.md"], f"rc={rc} {t.written()}\n{out[-300:]}")

with Tree() as t:
    rc, out = t.run("--gate", "g0", "--key", "hub-5", "--verdict", "pass", "--role", "product-owner",
                    "--item", "problem=yes")
    check("g0 writes evidence/<key>/g0/intake.md",
          rc == 0 and t.written() == ["evidence/hub-5/g0/intake.md"], f"rc={rc} {t.written()}\n{out[-300:]}")

print("\na failed gate still writes its record")
with Tree() as t:
    rc, out = g1(t, "7", verdict="fail",
                 items=["ac-binary=no:AC are not in Given/When/Then", "sized=yes", "flags=yes",
                        "no-open-question=yes"])
    check("a failed /ready exits 0 and writes", rc == 0 and t.written() == ["evidence/7/g1/ready.md"],
          f"rc={rc} {t.written()}\n{out[-300:]}")
    if t.written():
        rec = (t.root / "evidence/7/g1/ready.md").read_text(encoding="utf-8")
        check("with `verdict: fail`", re.search(r"^verdict: fail$", rec, re.M) is not None, rec)
        check("and the unsatisfied item with its gap",
              "- ac-binary: NOT satisfied - gap: AC are not in Given/When/Then" in rec, rec)
    rc, out = g1(t, "7")
    f = t.root / "evidence/7/g1/ready.md"
    rec = f.read_text(encoding="utf-8") if f.exists() else ""
    check("a re-run appends; the earlier rejection is kept",
          rc == 0 and re.search(r"^verdict: fail$", rec, re.M) and re.search(r"^verdict: pass$", rec, re.M),
          rec)

print("\nkeys that are refused, with nothing written")
BAD_KEYS = ["", "..", "../x", "../../etc", "42/..", "a/b", "hub-1/../../x", "42\\..\\x",
            "/abs", "C:\\x", "HUB-1", "hub-", "-1", "hub_1", "hub-1a", "42 ", " 42", "42\n",
            "4\u00b2", "\uff14\uff12", "hub-\u0661", "evidence", "hub--1"]
for key in BAD_KEYS:
    with Tree() as t:
        rc, out = g1(t, key)
        check(f"key {key!a} is refused with an error and nothing is written",
              rc == 2 and t.written() == [] and not t.escaped() and "key" in out.lower(),
              f"rc={rc} written={t.written()} escaped={t.escaped()}\n{out[-200:]}")

print("\nrecords that would be false are refused")
with Tree() as t:
    rc, out = g1(t, "8", verdict="pass",
                 items=["ac-binary=no:not G/W/T", "sized=yes", "flags=yes", "no-open-question=yes"])
    check("pass with an unsatisfied item is refused", rc == 2 and t.written() == [], f"rc={rc}\n{out[-200:]}")
with Tree() as t:
    rc, out = g1(t, "8", items=["ac-binary=yes", "sized=yes", "flags=yes"])
    check("a checklist item left unassessed is refused", rc == 2 and t.written() == [], f"rc={rc}\n{out[-200:]}")
with Tree() as t:
    rc, out = g1(t, "8", items=G1_ALL_YES + ["made-up=yes"])
    check("an item not in .sdlc/process.yaml is refused", rc == 2 and t.written() == [], f"rc={rc}\n{out[-200:]}")
with Tree() as t:
    rc, out = g1(t, "8", verdict="fail", items=["ac-binary=no", "sized=yes", "flags=yes", "no-open-question=yes"])
    check("an unsatisfied item with no gap is refused", rc == 2 and t.written() == [], f"rc={rc}\n{out[-200:]}")
with Tree() as t:
    rc, out = g1(t, "8", verdict="fail",
                 items=["ac-binary=no:x\nverdict: pass", "sized=yes", "flags=yes", "no-open-question=yes"])
    check("a gap that would forge a second verdict line is refused", rc == 2 and t.written() == [],
          f"rc={rc}\n{out[-200:]}")
with Tree() as t:
    rc, out = g1(t, "8", role="product-owner\nverdict: pass")
    check("a role that would forge a verdict line is refused", rc == 2 and t.written() == [],
          f"rc={rc}\n{out[-200:]}")
with Tree() as t:
    rc, out = t.run("--gate", "g2", "--key", "8", "--verdict", "pass", "--role", "architect")
    check("a gate other than g0/g1 is refused", rc == 2 and t.written() == [], f"rc={rc}\n{out[-200:]}")

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)
print("\nall passed")
