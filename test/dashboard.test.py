#!/usr/bin/env python3
"""
Tests for the dashboard generator.

Covers the two things the feature's own self-review recorded as UNVERIFIED — layout under
volume, and behaviour when `gh` is unavailable — plus the truncation defect that review
found. Writing them after the fact is the honest close to that loop.

    python test/dashboard.test.py
"""
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("dash", ROOT / "scripts" / "dashboard.py")
dash = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dash)

failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def base_data(**over):
    d = {
        "generated": "2026-08-08 12:00 UTC",
        "repo": {"nameWithOwner": "t/keel"},
        "open_prs": [], "merged_prs": [], "issues": [], "runs": [],
        "protection": None,
        "poam": {"open": [], "closed": 3},
        "lessons": 12, "evals": 4, "skills": 17, "agents": 10,
    }
    d.update(over)
    return d


print("dashboard generator")

# ── the defect this file exists for: truncation must announce itself ─────────
many = [{"number": i, "title": f"PR {i}", "mergeStateStatus": "CLEAN",
         "isDraft": False, "author": {}, "createdAt": "2026-08-08T00:00:00Z"}
        for i in range(25)]
html = dash.render(base_data(open_prs=many))
check("volume: renders 25 open PRs without crashing", "PR 0" in html)
check("volume: truncation is DECLARED, not silent",
      "more not shown" in html and "25 items need a human" in html)
check("volume: hidden count is correct", "+15" in html)

# ── unauthenticated / gh unavailable: degrade, and say so ───────────────────
html = dash.render(base_data())
check("no protection data: says controls are unverified, does not claim green",
      "not readable" in html and "unconfigured until verified" in html)
check("no runs: says so rather than showing a fake rate",
      "No completed runs" in html)

# ── a failed control must be shown loudly, never omitted ────────────────────
prot = {"enforce_admins": {"enabled": False},
        "required_linear_history": {"enabled": True},
        "allow_force_pushes": {"enabled": True},
        "required_conversation_resolution": {"enabled": True},
        "required_signatures": {"enabled": False},
        "required_status_checks": {"contexts": ["a", "b"]}}
html = dash.render(base_data(protection=prot))
check("a disabled control renders OFF (not omitted)", html.count("OFF") >= 3)
check("required-check count is shown", ">2<" in html)

# ── escaping: PR titles and POA&M text are attacker-influenceable ───────────
evil = '<script>alert(1)</script>'
html = dash.render(base_data(
    open_prs=[{"number": 1, "title": evil, "mergeStateStatus": "CLEAN",
               "isDraft": False, "author": {}, "createdAt": "2026-08-08T00:00:00Z"}],
    poam={"open": [{"id": "POAM-X", "weakness": evil, "risk": "High", "owner": evil,
                    "status": "Open"}], "closed": 0}))
check("XSS: no raw <script> survives escaping", "<script>alert(1)</script>" not in html)
check("XSS: content is present but escaped", "&lt;script&gt;" in html)

# ── needs_human classification ──────────────────────────────────────────────
nh = dash.needs_human(base_data(
    open_prs=[{"number": 1, "title": "x", "mergeStateStatus": "CLEAN", "isDraft": False,
               "author": {}, "createdAt": "2026-08-08T00:00:00Z"},
              {"number": 2, "title": "y", "mergeStateStatus": "BLOCKED", "isDraft": False,
               "author": {}, "createdAt": "2026-08-08T00:00:00Z"},
              {"number": 3, "title": "d", "mergeStateStatus": "CLEAN", "isDraft": True,
               "author": {}, "createdAt": "2026-08-08T00:00:00Z"}],
    poam={"open": [{"id": "P1", "weakness": "w", "risk": "Low", "owner": "unassigned",
                    "status": "Open"}], "closed": 0}))
kinds = sorted(k for k, _ in nh)
check("classifies clean/blocked/unowned; ignores drafts",
      kinds == ["assign", "fix", "merge"], f"got {kinds}")

# ── POA&M markdown must not leak into the rendered page ─────────────────────
html = dash.render(base_data(
    poam={"open": [{"id": "POAM-8", "weakness": "w", "risk": "High",
                    "owner": "unassigned", "status": "Open"}], "closed": 0}))
check("risk renders without markdown asterisks", "**High**" not in html)
check("unowned still detected after stripping", "unowned findings" in html and ">1<" in html)

# ── theme correctness: no colour defined ONLY in a theme block ──────────────
import re
root = re.search(r":root\{(.*?)\}", html, re.S).group(1)
base_tokens = set(re.findall(r"(--[a-z0-9-]+)\s*:", root))
all_tokens = set(re.findall(r"(--[a-z0-9-]+)\s*:", html))
check("every colour token is defined on bare :root", not (all_tokens - base_tokens),
      f"theme-only: {sorted(all_tokens - base_tokens)}")

print()
if failures:
    print(f"  {len(failures)} FAILED")
    sys.exit(1)
print("  all passed")
