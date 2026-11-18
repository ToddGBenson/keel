#!/usr/bin/env python3
"""
The agent that builds a PR writes its self-review; the operator does not. Refs: TheHub #61360

Operator decision 2026-11-04: agents self-review keel and binnacle PRs. Two failure
shapes: the rule is missing from the docs that carry it, or a doc still tells the
operator to run /self-review. Both fail here.

Refs: TheHub #61968 (the leftovers #183's review found). Four more shapes fail here: a script or
doc that tells a human to run /self-review, a doc that calls the record CI-required (keel's
pr-governance.yml has run on workflow_dispatch only since 2026-10-20), self-review.md crediting
the wrong script with the `verdict:` line, and a PR template silent on the Ref/Refs/Fixed rules
and the record-path link.

    python test/self-review-docs.test.py
"""
import re
import subprocess
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

# ---- TheHub #61968: leftovers from the #183 review ------------------------------------------

def tracked(*suffixes):
    out = subprocess.run(["git", "ls-files"], cwd=str(ROOT), capture_output=True, text=True,
                         check=True).stdout.splitlines()
    return [f for f in out if f.endswith(suffixes)
            and not f.startswith(("evidence/", "test/"))]


# 1. A human is never told to run /self-review. An imperative "run `/self-review`" must sit in a
#    sentence that names the building agent (sprint.sh's PR body escapes its backticks).
IMPERATIVE = re.compile(r"(?<!\w)run\s+\\?`/self-review", re.I)
BUILDER = re.compile(r"building agent|agent that builds|builder", re.I)
scanned = 0
for f in tracked(".md", ".sh"):
    text = re.sub(r"\s+", " ", (ROOT / f).read_text(encoding="utf-8"))
    scanned += 1
    bad = [m.start() for m in IMPERATIVE.finditer(text)
           if not BUILDER.search(text[max(0, m.start() - 160):m.start() + 120])]
    check(f"{f} does not tell a human to run /self-review", not bad)
check("scanned the scripts and docs (not vacuous)", scanned > 40, f"scanned {scanned}")

# 2. No doc calls the self-review record CI-required: pr-governance.yml is workflow_dispatch-only.
CI_REQUIRED = [
    re.compile(r"CI-required self-review", re.I),
    re.compile(r"self-review[^.|]{0,60}\brequired by (CI|pr-governance)", re.I),
    re.compile(r"\brequired by pr-governance", re.I),
    re.compile(r"pr-governance\.yml`?\*{0,2} blocks the merge", re.I),
    re.compile(r"Governance skips drafts", re.I),
]
# TheHub #62001: compliance/protection text, fixed under its own approval
EXCLUDED_62001 = (
    "docs/compliance/poam.md",
    "docs/compliance/cis-supply-chain-map.md",
    "scripts/configure-github.sh",
)
for f in tracked(".md", ".sh"):
    if f in EXCLUDED_62001:
        continue
    text = re.sub(r"\s+", " ", (ROOT / f).read_text(encoding="utf-8"))
    check(f"{f} does not call the self-review record CI-required",
          not any(r.search(text) for r in CI_REQUIRED))

runbook = flat("docs/runbooks/self-hosted-runner.md")
check("runbook says the self-review is read by reviewers, not by a running PR Governance check",
      "workflow_dispatch" in runbook and "reviewer" in runbook)

# 3. self-review.md credits each script with its own check.
sr = flat(".claude/commands/self-review.md")
check("self-review.md: control-liveness.py reads the verdict: line",
      re.search(r"`scripts/control-liveness\.py` (counts|reads)[^.]{0,80}`verdict: pass\|fail`", sr)
      is not None)
check("self-review.md: selfreview-check.js reads the PR: #<n> line",
      re.search(r"`scripts/selfreview-check\.js`[^.]{0,120}`PR: #<n>`", sr) is not None)
check("self-review.md does not credit selfreview-check.js with the verdict: line",
      re.search(r"selfreview-check\.js[^.]{0,120}verdict", sr) is None)

# 4. The PR template states the issue-resolution rules exactly as selfreview-check.js reads them.
check("PR template: Ref or Refs, any case, colon optional",
      "`Ref` or `Refs` (any case, with or without a colon)" in template)
check("PR template: only Closes, Fixes and Resolves close; Fixed falls to the Refs rule",
      "`Fixed #<n>`" in template and "falls to the `Refs` rule" in template)
check("PR template: the body must link the record path",
      "link `evidence/<issue>/g3/self-review.md` in the PR body" in template)

if failures:
    print(f"\n{len(failures)} failed")
    sys.exit(1)
print("\nall passed")
