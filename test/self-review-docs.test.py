#!/usr/bin/env python3
"""
The agent that builds a PR writes its self-review; the operator does not. Refs: TheHub #61360

Operator decision 2026-11-04: agents self-review keel and binnacle PRs. Two failure
shapes: the rule is missing from the docs that carry it, or a doc still tells the
operator to run /self-review. Both fail here.

    python test/self-review-docs.test.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def flat(path):
    """File text with Markdown line wraps and indentation collapsed to single spaces."""
    return re.sub(r"\s+", " ", (ROOT / path).read_text(encoding="utf-8"))


RULE = (
    "The agent that builds the PR writes `evidence/<issue>/g3/self-review.md` and the "
    "template sections before asking for review."
)
NOT_OPERATOR = (
    "The operator does not run `/self-review`, and MyKronos `independent-review` does not "
    "replace it."
)

for doc in (".claude/commands/self-review.md", "OPERATING.md"):
    text = flat(doc)
    check(f"{doc} states the builder writes the record", RULE in text)
    check(f"{doc} states the operator does not run /self-review", NOT_OPERATOR in text)

template = flat(".github/PULL_REQUEST_TEMPLATE.md")
check("PR template says how the record's issue is resolved",
      "Closes" in template and "Refs" in template and "in the title" in template)

# No tracked doc may tell the operator to run it. A negation ("does not run") is the rule itself.
OPERATOR_RUNS = re.compile(
    r"(operator|you|human)\s+(must\s+|should\s+|then\s+)?(runs?|invokes?)\s+`?/self-review", re.I)
scanned = 0
for base in ("OPERATING.md", "CLAUDE.md", "README.md", "CONTRIBUTING.md", "docs", ".claude", ".github"):
    p = ROOT / base
    files = [p] if p.is_file() else sorted(p.rglob("*.md")) if p.is_dir() else []
    for f in files:
        scanned += 1
        text = re.sub(r"\s+", " ", f.read_text(encoding="utf-8"))
        check(f"{f.relative_to(ROOT).as_posix()} does not say the operator runs /self-review",
              not OPERATOR_RUNS.search(text))
check("scanned the docs (not vacuous)", scanned > 20, f"scanned {scanned}")

if failures:
    print(f"\n{len(failures)} failed")
    sys.exit(1)
print("\nall passed")
