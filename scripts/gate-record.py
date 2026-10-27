#!/usr/bin/env python3
"""Write the evidence record for a G0 (/idea) or G1 (/ready) gate run.
Refs: TheHub #60981, POAM-018

G0 and G1 used to leave no record anywhere scripts/control-liveness.py could
count, so those gates read as "never fired" however often they ran. This script
is the one way /idea and /ready write their record:

    evidence/<key>/g0/intake.md     (/idea)
    evidence/<key>/g1/ready.md      (/ready)

    python scripts/gate-record.py --gate g1 --key hub-60944 --verdict fail \\
        --role product-owner+ux \\
        --item ac-binary=no:"AC-2 is not binary" --item sized=yes \\
        --item flags=yes --item no-open-question=yes

Every checklist item id that .sdlc/process.yaml declares for the gate must be
marked exactly once: `<id>=yes` or `<id>=no:<the gap>`. A FAILED gate writes its
record too: a rejection is the gate firing, and the rejection rate is the health
signal g1-ready.md asks for. A re-run appends, so an earlier rejection is never
overwritten by a later pass.

INPUT VALIDATION (the key becomes a path component under evidence/)
  * <key> is a GitHub issue number (^[0-9]+$) or a tracker id (^[a-z]+-[0-9]+$,
    e.g. hub-60944). ASCII only. Anything else, including '/', '\\' or '..', is
    refused before any directory is created.
  * The resolved path must still sit under evidence/ (defence in depth).
  * Role and gap text are single-line printable text, because control-liveness
    counts records by their `verdict:` line and a newline would let an argument
    forge one.
  * `verdict: pass` with any item unsatisfied is refused: that record would be
    false (CLAUDE.md PD-7).

Exit: 0 record written · 2 refused (nothing written)
"""

from __future__ import annotations

import argparse
import datetime as dt
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROCESS = ROOT / ".sdlc" / "process.yaml"
EVIDENCE = ROOT / "evidence"

# \A and \Z, not ^ and $: `$` also matches before a trailing newline. re.ASCII so
# no other script's digits pass as [0-9].
KEY_RE = re.compile(r"\A(?:[0-9]+|[a-z]+-[0-9]+)\Z", re.ASCII)
ROLE_RE = re.compile(r"\A[a-z][a-z-]*(?:\+[a-z][a-z-]*)*\Z", re.ASCII)
GATES = {"g0": ("G0", "intake.md", "Intake"), "g1": ("G1", "ready.md", "Ready (Definition of Ready)")}


class Refused(Exception):
    pass


def valid_key(key: str) -> str:
    if not KEY_RE.match(key):
        raise Refused(
            f"key {key!a} refused: it must be a GitHub issue number (^[0-9]+$) or a "
            f"tracker id (^[a-z]+-[0-9]+$, e.g. hub-60944). Nothing was written.")
    return key


def single_line(label: str, text: str) -> str:
    if not text or any(ord(c) < 0x20 or ord(c) == 0x7F for c in text):
        raise Refused(f"{label} must be non-empty, single-line text with no control characters")
    if len(text) > 500:
        raise Refused(f"{label} is longer than 500 characters")
    return text


def checklist_ids(gate_id: str) -> list[str]:
    import yaml  # ci/requirements.txt

    doc = yaml.safe_load(PROCESS.read_text(encoding="utf-8"))
    for gate in doc.get("gates", []):
        if gate.get("id") == gate_id:
            ids = [str(item["id"]) for item in gate.get("checklist", [])]
            if not ids:
                raise Refused(f"{PROCESS.name} declares no checklist items for {gate_id}")
            return ids
    raise Refused(f"{PROCESS.name} declares no gate {gate_id}")


def parse_items(raw: list[str], expected: list[str]) -> list[tuple[str, bool, str]]:
    marked: dict[str, tuple[bool, str]] = {}
    for entry in raw:
        item, sep, rest = entry.partition("=")
        if not sep:
            raise Refused(f"--item {entry!r}: expected <id>=yes or <id>=no:<gap>")
        if item not in expected:
            raise Refused(f"--item {item!r} is not a checklist item for this gate; "
                          f"{PROCESS.name} declares {expected}")
        if item in marked:
            raise Refused(f"--item {item!r} given twice")
        if rest == "yes":
            marked[item] = (True, "")
        elif rest.startswith("no:"):
            marked[item] = (False, single_line(f"gap for {item}", rest[3:].strip()))
        else:
            raise Refused(f"--item {entry!r}: an unsatisfied item must name its gap (<id>=no:<gap>)")
    missing = [i for i in expected if i not in marked]
    if missing:
        raise Refused(f"checklist item(s) not assessed: {missing}. Every item is marked, "
                      f"satisfied or not.")
    return [(i, *marked[i]) for i in expected]


def render(gate: str, key: str, verdict: str, role: str, items, today: str,
           recorded_by: str = "") -> str:
    label, _, name = GATES[gate]
    lines = [
        f"# {label} {name} - {key}",
        "",
        f"key: {key}",
        f"date: {today}",
        f"verdict: {verdict}",
        f"recommending role: {role}",
        f"recorded by: {recorded_by or 'not stated'}",
        "",
        "## Checklist (.sdlc/process.yaml)",
        "",
    ]
    for item, ok, gap in items:
        lines.append(f"- {item}: satisfied" if ok else f"- {item}: NOT satisfied - gap: {gap}")
    lines += ["", f"Written by scripts/gate-record.py. Approval of {label} belongs to the "
                  f"Delivery Lead (ADR-0005); this record is the recommendation, not the approval.", ""]
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--gate", required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--verdict", required=True)
    ap.add_argument("--role", required=True, help="recommending role, e.g. product-owner+ux")
    ap.add_argument("--item", action="append", default=[], help="<id>=yes | <id>=no:<gap>")
    ap.add_argument("--recorded-by", default="",
                    help="who produced the assessment: agent and model, or person "
                         "(evidence/README.md: every record names its producer)")
    args = ap.parse_args(argv)

    try:
        if args.gate not in GATES:
            raise Refused(f"gate {args.gate!r} refused: this writer covers {sorted(GATES)}")
        key = valid_key(args.key)
        if args.verdict not in ("pass", "fail"):
            raise Refused(f"verdict {args.verdict!r} refused: pass or fail")
        if not ROLE_RE.match(args.role):
            raise Refused(f"role {args.role!a} refused: an agent role name such as "
                          f"product-owner or product-owner+ux")
        recorded_by = single_line("--recorded-by", args.recorded_by) if args.recorded_by else ""
        label, filename, _ = GATES[args.gate]
        items = parse_items(args.item, checklist_ids(label))
        if args.verdict == "pass" and not all(ok for _, ok, _ in items):
            raise Refused("verdict pass refused: an item is not satisfied. Record verdict fail "
                          "with the gap (PD-7).")

        target = EVIDENCE / key / args.gate / filename
        base = EVIDENCE.resolve()
        if base not in target.resolve().parents:
            raise Refused(f"key {key!a} refused: {target} resolves outside evidence/")
    except Refused as e:
        print(f"gate-record: {e}", file=sys.stderr)
        return 2

    record = render(args.gate, key, args.verdict, args.role, items,
                    dt.datetime.now(dt.timezone.utc).date().isoformat(), recorded_by)
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and target.read_text(encoding="utf-8").strip():
        # Append: the earlier attempt, and any rejection in it, stays on record.
        record = target.read_text(encoding="utf-8").rstrip("\n") + "\n\n---\n\n" + record
    target.write_text(record, encoding="utf-8", newline="\n")
    print(f"gate-record: wrote {target.relative_to(ROOT).as_posix()} (verdict: {args.verdict})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
