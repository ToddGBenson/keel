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
  * open: any status that does not begin with `Closed`.

    python scripts/poam.py [--file F] [--today YYYY-MM-DD]   count + OVERDUE lines
    python scripts/poam.py --overdue                        OVERDUE lines only
    python scripts/poam.py --check                          exit 1 if an open
                                                            High/Critical is overdue
    python scripts/poam.py --list                           every parsed row

Exit codes: 0 ok, 1 --check found an overdue open High/Critical, 2 the register
could not be read or parsed. A register with no POAM rows is exit 2: a parse
that found nothing must not read as nothing open.
"""
import argparse
import re
import sys
from dataclasses import dataclass
from datetime import date, datetime, timezone
from pathlib import Path
from typing import List, Optional

DEFAULT_FILE = Path(__file__).resolve().parent.parent / "docs" / "compliance" / "poam.md"
GATING = {"high", "critical"}
_ROW = re.compile(r"^\s*\|\s*(?:\*\*)?POAM-\d+")
_DATE = re.compile(r"\b(\d{4})-(\d{2})-(\d{2})\b")
_STRUCK = re.compile(r"~~.*?~~")


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


def parse(text: str) -> List[Item]:
    items: List[Item] = []
    cols = None
    for n, line in enumerate(text.splitlines(), 1):
        if not line.lstrip().startswith("|"):
            continue
        cells = _cells(line)
        if not _ROW.match(line):
            # A header row resets the column map; separator rows are skipped.
            maybe = _columns(cells)
            if maybe:
                cols = maybe
            continue
        c = cols or {"id": 0, "severity": 3, "due": 5, "status": 6}
        if len(cells) <= max(c.values()):
            raise PoamError(f"line {n}: POAM row has {len(cells)} cells, "
                            f"needs {max(c.values()) + 1}: {line.strip()[:80]}")
        state = parse_state(cells[c["status"]])
        items.append(Item(
            id=_plain(cells[c["id"]]),
            severity=_plain(cells[c["severity"]]),
            due=parse_due(cells[c["due"]]),
            state=state,
            open=not _plain(cells[c["status"]]).lower().startswith("closed"),
        ))
    if not items:
        raise PoamError("no `| POAM-` rows found")
    return items


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
    return ap.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        items = parse(args.file.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, PoamError) as exc:
        print(f"poam.py: cannot read the POA&M register {args.file}: {exc}", file=sys.stderr)
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
        gating = [i for i in late if i.severity.lower() in GATING]
        if gating:
            print(f"FAIL: {len(gating)} open High/Critical POA&M item(s) past due "
                  f"({args.file.name}, today {args.today.isoformat()})")
            return 1
        print(f"ok: no open High/Critical POA&M item is past due "
              f"(today {args.today.isoformat()})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
