#!/usr/bin/env python3
"""
Tests for POA&M due-date enforcement. Refs: TheHub #60977

POAM-010, POAM-014 and POAM-016 went 38-40 days past due and nothing said so.
`./keel status` counted open items with `grep -c '| POAM-[0-9]* .* Open'`, which
reported 7 of 8 (it missed POAM-010, 'In progress') and never compared a date.

Runs the REAL scripts/poam.py, the REAL `./keel status` and the REAL
.claude/hooks/session-brief.sh, each against fixture registers in a throwaway
copy of the repository layout (keel reads the poam.md next to itself), with `gh`
stubbed on PATH so no network or auth is involved:

  * a struck-through date followed by a new one yields the new one;
  * 'In progress' counts as open; 'Closed ...' does not;
  * a non-date due cell yields `no date` and the row is not skipped;
  * an overdue open High makes `--check` exit 1; an overdue Medium is reported
    but does not; nothing overdue exits 0;
  * against the register at af878f1, `./keel status` prints 8 open, POAM-010
    among them (the old grep printed 7);
  * the session brief prints OVERDUE lines when there are any and adds nothing
    when there are none;
  * the platform-integrity job (daily-0600) runs `scripts/poam.py --check`.

    python test/poam.test.py
"""
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
POAM_PY = ROOT / "scripts" / "poam.py"
KEEL = ROOT / "keel"
BRIEF = ROOT / ".claude" / "hooks" / "session-brief.sh"
AF878F1 = ROOT / "test" / "fixtures" / "poam-af878f1.md"
BASH = shutil.which("bash") or "bash"
failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


HEADER = ("| ID | Weakness | Control | Risk | Owner | Due | Status |\n"
          "|---|---|---|---|---|---|---|\n")


def register(*rows):
    return "# POA&M\n\n## Register\n\n" + HEADER + "".join(r + "\n" for r in rows)


# Each row is a real shape from docs/compliance/poam.md.
ROW_REDATED_HIGH = ("| POAM-010 | Release authorization weakened | CM-3, AC-5 | **High** | "
                    "Todd Benson | ~~2026-09-12~~ **2026-11-21** (extended once, 2026-10-22) | "
                    "In progress — the Concourse job is **deleted** |")
ROW_NODATE_LOW = ("| POAM-001 | Agent write-scope is prompt-enforced | AIC-3 | Low | "
                  "*unassigned* | review quarterly | Open — compensating controls in place |")
ROW_NODATE_HIGH = ("| POAM-008 | **Solo operation** | AC-5 | **High** | Todd Benson | "
                   "on 2nd team member | Open — accepted with compensating controls |")
ROW_OVERDUE_HIGH = ("| POAM-014 | **The merge gate verifies process** | CM-3 | **High** | "
                    "Todd Benson | 2026-09-14 | Open — measured 2026-10-22 |")
ROW_OVERDUE_MEDIUM = ("| POAM-011 | No provenance for forks | SR-4(3) | Medium | Todd Benson | "
                      "2026-09-01 | Open |")
ROW_CLOSED_LATE = ("| POAM-016 | **Two release paths** | CM-3 | Medium | Todd Benson | 2026-09-14 | "
                   "**Closed 2026-10-22** (TheHub #60935, 38 days late) — one path |")
ROW_FUTURE_CRITICAL = ("| POAM-019 | Something critical | SI-7 | **Critical** | Todd Benson | "
                       "2026-12-01 | Open |")


def load_poam():
    spec = importlib.util.spec_from_file_location("poam", POAM_PY)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def run_poam(text, *args):
    tmp = Path(tempfile.mkdtemp(prefix="poam-"))
    try:
        f = tmp / "poam.md"
        f.write_text(text, encoding="utf-8")
        p = subprocess.run([sys.executable, str(POAM_PY), "--file", str(f), *args],
                           capture_output=True, text=True, encoding="utf-8")
        return p.returncode, p.stdout + p.stderr
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def fake_repo(poam_text, with_poam_py=True):
    """A throwaway copy of the layout keel and the session brief read."""
    tmp = Path(tempfile.mkdtemp(prefix="poam-repo-"))
    (tmp / "docs" / "compliance").mkdir(parents=True)
    (tmp / "scripts").mkdir()
    (tmp / ".claude" / "hooks").mkdir(parents=True)
    (tmp / "docs" / "compliance" / "poam.md").write_text(poam_text, encoding="utf-8")
    shutil.copy2(KEEL, tmp / "keel")
    shutil.copy2(BRIEF, tmp / ".claude" / "hooks" / "session-brief.sh")
    if with_poam_py and POAM_PY.exists():
        shutil.copy2(POAM_PY, tmp / "scripts" / "poam.py")
    stubs = tmp / "stubs"
    stubs.mkdir()
    # gh: `pr list` prints nothing, `auth status` fails, so the hook's
    # PR-awaiting-approval block stays out of the comparison.
    (stubs / "gh").write_text(
        '#!/usr/bin/env bash\n[ "${1:-}" = "auth" ] && exit 1\nexit 0\n', newline="\n")
    os.chmod(stubs / "gh", 0o755)
    return tmp, stubs


def run_in(tmp, stubs, argv):
    env = dict(os.environ)
    env["PATH"] = str(stubs) + os.pathsep + env.get("PATH", "")
    env["CLAUDE_PROJECT_DIR"] = str(tmp)
    p = subprocess.run([BASH, *argv], cwd=str(tmp), capture_output=True, text=True,
                       encoding="utf-8", env=env)
    return p.returncode, p.stdout + p.stderr


def keel_status(poam_text, today):
    tmp, stubs = fake_repo(poam_text)
    try:
        return run_in(tmp, stubs, ["keel", "status", "--today", today])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def brief(poam_text, today, with_poam_py=True):
    tmp, stubs = fake_repo(poam_text, with_poam_py)
    try:
        env_today = {"POAM_TODAY": today}
        os.environ.update(env_today)
        try:
            return run_in(tmp, stubs, [".claude/hooks/session-brief.sh"])
        finally:
            os.environ.pop("POAM_TODAY", None)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


print("POA&M due-date enforcement (TheHub #60977)")

if not POAM_PY.exists():
    check("scripts/poam.py exists", False, "(not present)")

# ── 1. a struck-through date followed by a new date yields the new date ───────
if POAM_PY.exists():
    poam = load_poam()
    items = {i.id: i for i in poam.parse(register(
        ROW_REDATED_HIGH, ROW_NODATE_LOW, ROW_CLOSED_LATE))}
    check("re-dated cell yields the new date, not the struck one or the note's",
          items.get("POAM-010") and items["POAM-010"].due == date(2026, 11, 21),
          f"got {items.get('POAM-010')}")
    check("severity is read without markdown emphasis",
          items.get("POAM-010") and items["POAM-010"].severity == "High")
    # ── 2. 'In progress' is open; 'Closed ...' is not ───────────────────────
    check("'In progress' counts as open",
          items.get("POAM-010") and items["POAM-010"].open)
    check("'**Closed 2026-10-22** ...' counts as closed",
          items.get("POAM-016") and not items["POAM-016"].open)
    # ── 3. a non-date due cell is `no date`, and the row is kept ───────────
    check("non-date cell row is not skipped", "POAM-001" in items, f"ids {sorted(items)}")
    check("non-date cell yields no date",
          items.get("POAM-001") is not None and items["POAM-001"].due is None)

rc, out = run_poam(register(ROW_NODATE_LOW, ROW_NODATE_HIGH), "--today", "2026-10-23")
check("non-date cells are reported as `no date`, never as overdue",
      rc == 0 and "no overdue POA&M items" in out and "OVERDUE" not in out, out)
rc, out = run_poam(register(ROW_NODATE_LOW), "--list", "--today", "2026-10-23")
check("--list shows the non-date row as `no date`",
      re.search(r"POAM-001\s+Low\s+no date\s+Open", out) is not None, out)

# ── 4. an overdue open High makes --check exit 1 ─────────────────────────────
rc, out = run_poam(register(ROW_OVERDUE_HIGH, ROW_NODATE_LOW), "--check", "--today", "2026-10-23")
check("overdue open High: --check exits 1", rc == 1, f"rc={rc} {out}")
check("overdue open High: OVERDUE line names id, severity, date and days",
      "OVERDUE POAM-014 High due 2026-09-14 (39 days)" in out, out)
rc, out = run_poam(register(ROW_OVERDUE_MEDIUM), "--check", "--today", "2026-10-23")
check("overdue Medium only: --check exits 0 but still reports it",
      rc == 0 and "OVERDUE POAM-011 Medium due 2026-09-01 (52 days)" in out, f"rc={rc} {out}")
rc, out = run_poam(register(ROW_CLOSED_LATE, ROW_REDATED_HIGH), "--check", "--today", "2026-10-23")
check("closed-late and re-dated items: --check exits 0", rc == 0, f"rc={rc} {out}")
rc, out = run_poam(register(ROW_FUTURE_CRITICAL), "--check", "--today", "2026-12-02")
check("overdue Critical: --check exits 1", rc == 1, f"rc={rc} {out}")
rc, out = run_poam(register(ROW_OVERDUE_HIGH), "--check", "--today", "2026-09-14")
check("due today is not overdue", rc == 0 and "no overdue POA&M items" in out, out)
rc, out = run_poam(register(ROW_OVERDUE_HIGH,
                            "| POAM-099 | half a row | AC-1 | High |"), "--check")
check("a malformed POAM row fails loudly (exit 2), never reads as nothing open",
      rc == 2, f"rc={rc} {out}")
rc, out = run_poam("# empty\n", "--check")
check("a register with no POAM rows fails (exit 2): a parse that found nothing is not a pass",
      rc == 2, f"rc={rc} {out}")
rc, out = run_poam(register(ROW_NODATE_LOW), "--today", "23/10/2026")
check("--today must be YYYY-MM-DD", rc != 0 and rc != 1, f"rc={rc} {out}")

# --today defaults to the current UTC date.
if POAM_PY.exists():
    check("--today defaults to the UTC date",
          load_poam().parse_args([]).today == __import__("datetime").datetime.now(
              __import__("datetime").timezone.utc).date())

# ── 5. ./keel status against the register at af878f1 ────────────────────────
af = AF878F1.read_text(encoding="utf-8")
rc, out = keel_status(af, "2026-10-23")
check("keel status at af878f1: `open POA&M findings: 8`",
      re.search(r"open POA&M findings: 8\b", out) is not None, out)
rc2, lst = run_poam(af, "--list", "--today", "2026-10-23")
open_ids = sorted(set(re.findall(r"^\s*(POAM-\d+)\s.*\bopen\s*$", lst, re.M)))
check("the 8 open at af878f1 are 001 008 010 011 013 014 017 018",
      open_ids == ["POAM-001", "POAM-008", "POAM-010", "POAM-011", "POAM-013",
                   "POAM-014", "POAM-017", "POAM-018"], f"{open_ids}\n{lst}")
check("keel status at af878f1, 2026-10-23: `no overdue POA&M items`",
      "no overdue POA&M items" in out, out)
rc, out = keel_status(af, "2026-11-16")
check("keel status at af878f1, 2026-11-16: POAM-017 and POAM-018 OVERDUE (1 day)",
      "OVERDUE POAM-017 High due 2026-11-15 (1 days)" in out
      and "OVERDUE POAM-018 High due 2026-11-15 (1 days)" in out
      and "POAM-010" not in out, out)

# ── 6. the session brief ─────────────────────────────────────────────────────
baseline_rc, baseline = brief(register(ROW_NODATE_LOW), "2026-10-23", with_poam_py=False)
rc, out = brief(register(ROW_OVERDUE_HIGH, ROW_NODATE_LOW), "2026-10-23")
check("session brief prints the OVERDUE line when one exists",
      "OVERDUE POAM-014 High due 2026-09-14 (39 days)" in out and rc == 0, out)
rc, out = brief(register(ROW_REDATED_HIGH, ROW_NODATE_LOW, ROW_CLOSED_LATE), "2026-10-23")
check("session brief adds no output when nothing is overdue",
      rc == 0 and out == baseline, f"\n--- got ---\n{out}\n--- baseline ---\n{baseline}")

# ── 7. the daily platform-integrity lane runs --check ────────────────────────
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
check("platform-integrity.sh runs `scripts/poam.py --check`",
      any(re.search(r"\bscripts/poam\.py --check\b", ln) for ln in live))

print()
if failures:
    print(f"{len(failures)} FAILED")
    sys.exit(1)
print("all passed")
