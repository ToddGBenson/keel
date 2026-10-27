#!/usr/bin/env python3
"""
POA&M due dates, enforced. Refs: TheHub #60977

POAM-010, POAM-014 and POAM-016 went 38-40 days past due and nothing reported
it. `./keel status` counted `grep -c '| POAM-[0-9]* .* Open'`, which missed
POAM-010 ('In progress') and never looked at a date. This reads the register
instead:

  * every `| POAM-<n> |` row of docs/compliance/poam.md, in whatever order;
  * columns found by header name (ID, Risk or Severity, Due, Status);
  * due date: struck-through text (`~~2026-09-12~~`) is ignored, then the first
    YYYY-MM-DD left is the date. `review quarterly` or `on 2nd team member` is
    `no date`, kept, and never overdue;
  * status: the vocabulary poam.md itself defines (Entry format, `Status`):
    Open, In progress, Risk accepted -> open; Completed (and the `Closed` this
    register uses in practice) -> closed. Any other status is an error, not a
    guess (keel #146 review);
  * an empty register -- the header and the template's placeholder row, as
    binnacle and every fresh fork ship it -- is 0 open, not an error;
  * --history (with --check): an open item is gated at the HIGHEST Risk any
    committed version of the register gave it, so downgrading High to Medium
    does not get an overdue item past the gate. Closing it or re-dating it
    (both reviewed edits) does. Old versions are read for ID and Risk only, so
    a status the vocabulary does not know (keel's own register once said
    `REOPENED`) cannot hide a version's Risk; a version whose ID and Risk
    cannot be read is named and the check exits 2 (keel #153 review).

    python scripts/poam.py [--file F] [--today YYYY-MM-DD]   count + OVERDUE lines
    python scripts/poam.py --overdue                        OVERDUE lines only
    python scripts/poam.py --check                          exit 1 if an open
                                                            High/Critical is overdue
    python scripts/poam.py --check --history                ... at its highest
                                                            committed Risk
    python scripts/poam.py --list                           every parsed row

Exit codes: 0 ok, 1 --check found an overdue open High/Critical, 2 the register
could not be read or parsed. A file with no register table (no header row
naming ID, Risk, Due and Status) is exit 2: a parse that found nothing must not
read as nothing open. A register table with no POAM rows is 0 open.
"""
import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple

DEFAULT_FILE = Path(__file__).resolve().parent.parent / "docs" / "compliance" / "poam.md"
_ROW = re.compile(r"^\s*\|\s*(?:\*\*)?POAM-\d+")
_DATE = re.compile(r"\b(\d{4})-(\d{2})-(\d{2})\b")
_STRUCK = re.compile(r"~~.*?~~")
# poam.md, Entry format: `Status | Open / In progress / Risk accepted / Completed`.
# `Closed` is what the register's rows actually say, so it is closed too.
OPEN_STATES = ("open", "in progress", "risk accepted")
CLOSED_STATES = ("completed", "closed")
VOCABULARY = "Open, In progress, Risk accepted, Completed (or Closed)"
RANK = {"low": 1, "medium": 2, "high": 3, "critical": 4}


class PoamError(Exception):
    pass


@dataclass
class Item:
    id: str
    severity: str
    due: Optional[date]
    state: str
    open: bool

    def days_overdue(self, today: date) -> int:
        return (today - self.due).days if self.due else 0

    def is_overdue(self, today: date) -> bool:
        return self.open and self.due is not None and self.due < today


def _cells(line: str) -> List[str]:
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|"):
        s = s[:-1]
    return [c.strip() for c in s.split("|")]


def _plain(cell: str) -> str:
    return re.sub(r"[*_`]", "", cell).strip()


def parse_due(cell: str) -> Optional[date]:
    for m in _DATE.finditer(_STRUCK.sub("", cell)):
        try:
            return date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        except ValueError:
            continue
    return None


def parse_state(cell: str) -> str:
    """The leading status phrase: 'Open', 'In progress', 'Closed', ..."""
    text = _plain(cell)
    head = re.split(r"\s+[—–-]\s+|\(|;", text, maxsplit=1)[0]
    head = _DATE.sub("", head).strip(" .,:")
    return head or text


def classify(cell: str) -> Optional[bool]:
    """True open, False closed, None outside the vocabulary."""
    text = _plain(cell).lower()
    for word in CLOSED_STATES:
        if re.match(re.escape(word) + r"\b", text):
            return False
    for word in OPEN_STATES:
        if re.match(re.escape(word) + r"\b", text):
            return True
    return None


def rank(severity: str) -> int:
    m = re.match(r"[a-z]+", _plain(severity).lower())
    return RANK.get(m.group(0), 0) if m else 0


def level(cell: str) -> str:
    """`**High** — reachable from a fork` -> `High`. poam.md asks for the Risk
    "with reasoning", so the level is the leading word; any other text is kept."""
    text = _plain(cell)
    m = re.match(r"[A-Za-z]+", text)
    return m.group(0).capitalize() if m and m.group(0).lower() in RANK else text


def _columns(header: List[str]):
    names = [_plain(h).lower() for h in header]

    def find(*wanted):
        for w in wanted:
            if w in names:
                return names.index(w)
        return None

    cols = {"id": find("id"), "severity": find("risk", "severity"),
            "due": find("due", "due date"), "status": find("status", "state")}
    if None in cols.values():
        return None
    return cols


def parse_risks(text: str) -> Dict[str, str]:
    """{id: Risk} from a register, reading only the ID and Risk columns.

    For --history: an old version is evidence of what Risk an item had, whatever
    its Status or Due said, so neither is read. Raises PoamError when a POAM row
    has no readable ID or Risk -- that version would otherwise count for less.
    """
    risks: Dict[str, str] = {}
    cols = None
    for n, line in enumerate(text.splitlines(), 1):
        if not line.lstrip().startswith("|"):
            continue
        cells = _cells(line)
        if not _ROW.match(line):
            names = [_plain(h).lower() for h in cells]
            if "id" in names and ("risk" in names or "severity" in names):
                cols = {"id": names.index("id"),
                        "severity": names.index("risk" if "risk" in names else "severity")}
            continue
        c = cols or {"id": 0, "severity": 3}
        ident = _plain(cells[c["id"]]) if len(cells) > c["id"] else ""
        if len(cells) <= c["severity"] or rank(cells[c["severity"]]) == 0:
            raise PoamError(f"line {n}: {ident or 'a POAM row'} has no readable Risk: "
                            f"{line.strip()[:80]}")
        sev = level(cells[c["severity"]])
        if ident not in risks or rank(sev) > rank(risks[ident]):
            risks[ident] = sev
    return risks


def parse(text: str) -> List[Item]:
    items: List[Item] = []
    cols = None
    saw_header = False
    for n, line in enumerate(text.splitlines(), 1):
        if not line.lstrip().startswith("|"):
            continue
        cells = _cells(line)
        if not _ROW.match(line):
            # A header row resets the column map; separator rows are skipped.
            maybe = _columns(cells)
            if maybe:
                cols = maybe
                saw_header = True
            continue
        c = cols or {"id": 0, "severity": 3, "due": 5, "status": 6}
        if len(cells) <= max(c.values()):
            raise PoamError(f"line {n}: POAM row has {len(cells)} cells, "
                            f"needs {max(c.values()) + 1}: {line.strip()[:80]}")
        state = parse_state(cells[c["status"]])
        is_open = classify(cells[c["status"]])
        if is_open is None:
            raise PoamError(f"line {n}: {_plain(cells[c['id']])} has status {state!r}; "
                            f"poam.md's statuses are {VOCABULARY}")
        items.append(Item(
            id=_plain(cells[c["id"]]),
            severity=level(cells[c["severity"]]),
            due=parse_due(cells[c["due"]]),
            state=state,
            open=is_open,
        ))
    if not items and not saw_header:
        raise PoamError("no register table (a header naming ID, Risk, Due and Status) "
                        "and no `| POAM-` rows found")
    return items


def history_ranks(path: Path) -> Tuple[Dict[str, Tuple[str, str]], int, List[str]]:
    """The highest Risk each ID had in any committed version of `path`.

    Returns ({id: (severity, short sha)}, versions found, ["<sha>: <why>" for
    each version whose ID/Risk could not be read]). Raises PoamError when git
    cannot answer. The caller fails on any skipped version: --history must
    never quietly gate on less.
    """
    path = path.resolve()

    where = [path.parent]  # rev-parse runs beside the file; the rest from the top

    def git(*args):
        p = subprocess.run(["git", "-C", str(where[0]), *args],
                           capture_output=True, text=True, encoding="utf-8")
        if p.returncode != 0:
            raise PoamError(f"--history: git {args[0]} failed: {p.stderr.strip()[:200]}")
        return p.stdout

    try:
        top = Path(git("rev-parse", "--show-toplevel").strip()).resolve()
    except OSError as exc:
        raise PoamError(f"--history: git is not available: {exc}")
    rel = path.relative_to(top).as_posix()
    where[0] = top  # pathspecs are relative to -C, and `rel` is relative to the top
    shas = git("log", "--format=%H", "--", rel).split()
    if not shas:
        raise PoamError(f"--history: {rel} has no committed versions")
    best: Dict[str, Tuple[str, str]] = {}
    skipped: List[str] = []
    for sha in shas:
        try:
            old = parse_risks(git("show", f"{sha}:{rel}"))
        except PoamError as exc:
            skipped.append(f"{sha[:12]}: {exc}")
            continue
        for ident, sev in old.items():
            if ident not in best or rank(sev) > rank(best[ident][0]):
                best[ident] = (sev, sha[:12])
    return best, len(shas), skipped


def overdue(items: List[Item], today: date) -> List[Item]:
    return sorted((i for i in items if i.is_overdue(today)),
                  key=lambda i: (i.due, i.id))


def overdue_line(i: Item, today: date) -> str:
    return f"OVERDUE {i.id} {i.severity} due {i.due.isoformat()} ({i.days_overdue(today)} days)"


def _iso(s: str) -> date:
    try:
        return datetime.strptime(s, "%Y-%m-%d").date()
    except ValueError:
        raise argparse.ArgumentTypeError(f"not YYYY-MM-DD: {s!r}")


def parse_args(argv):
    ap = argparse.ArgumentParser(description="POA&M due dates (TheHub #60977)")
    ap.add_argument("--file", type=Path, default=DEFAULT_FILE)
    ap.add_argument("--today", type=_iso, default=datetime.now(timezone.utc).date(),
                    help="YYYY-MM-DD; default: the current UTC date")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true",
                      help="exit 1 when an open High or Critical item is overdue")
    mode.add_argument("--overdue", action="store_true",
                      help="print only OVERDUE lines (nothing when none)")
    mode.add_argument("--list", action="store_true", help="print every parsed row")
    ap.add_argument("--history", action="store_true",
                    help="with --check: gate each open item at the highest Risk any "
                         "committed version of the register gave it (git required)")
    return ap.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        items = parse(args.file.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, PoamError) as exc:
        print(f"poam.py: cannot read the POA&M register {args.file}: {exc}", file=sys.stderr)
        return 2
    gate_as = {i.id: i.severity for i in items}
    if args.history and args.check:
        try:
            best, versions, skipped = history_ranks(args.file)
        except (OSError, ValueError, PoamError) as exc:
            print(f"poam.py: {exc}", file=sys.stderr)
            return 2
        for i in items:
            was = best.get(i.id)
            if i.open and was and rank(was[0]) > rank(i.severity):
                gate_as[i.id] = was[0]
                print(f"note: {i.id} Risk is {i.severity} now but was {was[0]} at {was[1]}; "
                      f"gated as {was[0]} until it is closed or re-dated")
        print(f"history: {versions - len(skipped)} of {versions} committed version(s) of "
              f"{args.file.name} read, {len(skipped)} skipped")
        if skipped:
            for why in skipped:
                print(f"poam.py: --history: cannot read ID/Risk in {why}", file=sys.stderr)
            print("poam.py: --history would gate on less than the full history; "
                  "fix or explain the skipped version(s)", file=sys.stderr)
            return 2
    late = overdue(items, args.today)

    if args.list:
        for i in items:
            due = i.due.isoformat() if i.due else "no date"
            print(f"{i.id}  {i.severity}  {due}  {i.state}  {'open' if i.open else 'closed'}")
        return 0
    if args.overdue:
        for i in late:
            print(overdue_line(i, args.today))
        return 0

    if not args.check:
        print(f"open POA&M findings: {sum(i.open for i in items)}")
    for i in late:
        print(overdue_line(i, args.today))
    if not late:
        print("no overdue POA&M items")
    if args.check:
        gating = [i for i in late if rank(gate_as[i.id]) >= RANK["high"]]
        if gating:
            print(f"FAIL: {len(gating)} open High/Critical POA&M item(s) past due "
                  f"({args.file.name}, today {args.today.isoformat()})")
            return 1
        print(f"ok: no open High/Critical POA&M item is past due "
              f"(today {args.today.isoformat()})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
