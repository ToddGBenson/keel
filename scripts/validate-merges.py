#!/usr/bin/env python3
"""Did a merged pull request's content actually reach the default branch? Refs: #69

**A pull request can report "merged" while changing nothing.**

That is not hypothetical here. #68 was based on #66's branch and merged 39
seconds after it. #66 was **squash**-merged, which put a new commit on `main` and
left its branch obsolete — so #68 merged into a branch that no longer led
anywhere. 490 lines across 8 files never arrived. Both PRs showed green, both
showed merged, and nothing noticed until someone asked an unrelated question
about the pipeline.

Every check in this repository measured whether things were *correct*. None
measured whether they were *there*.

WHAT IT CHECKS
--------------
1. **A merged PR whose base is not the default branch.** That is the stacked-PR
   shape, and with squash merges it is the one that silently lands nowhere.
2. **A merged PR whose merge commit is not reachable from the default branch.**
   Authoritative, unlike matching `(#N)` in commit subjects — the first version of
   this check did that and flagged five PRs whose content was present but whose
   merge method had not written the number. A checker that cries wolf gets muted
   (L0007), so it asks GitHub which commit the merge produced and whether that
   commit is on the branch.

Either finding is reconciled — not suppressed — in `.merge-reconciled.json`, with
a reason, because a stranded PR is often legitimately re-landed by a later one
and should stop being reported once it has been.

    python scripts/validate-merges.py            # report
    python scripts/validate-merges.py --check    # non-zero on an unreconciled strand

Needs `gh` authenticated. Without it the check **skips loudly and fails open**
(GP-4): a merge check that quietly passes because it could not look is the exact
failure it exists to catch.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RECONCILED = ROOT / ".merge-reconciled.json"
LOOKBACK = 40  # merged PRs to examine


def gh(*args: str) -> str | None:
    try:
        out = subprocess.run(["gh", *args], cwd=ROOT, capture_output=True,
                             text=True, encoding="utf-8", timeout=120)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    return out.stdout if out.returncode == 0 else None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    print("Merged-PR landing check")

    repo_json = gh("repo", "view", "--json", "defaultBranchRef,nameWithOwner")
    if repo_json is None:
        print("  [SKIP]  gh is unavailable or not authenticated.")
        print("          This check CANNOT run, which is not the same as passing.")
        print("          A merge check that quietly succeeds because it could not")
        print("          look is the failure it exists to catch (GP-4).")
        return 1 if args.check else 0

    repo = json.loads(repo_json)
    default = repo["defaultBranchRef"]["name"]
    slug = repo["nameWithOwner"]

    prs_json = gh("pr", "list", "--state", "merged", "--limit", str(LOOKBACK),
                  "--json", "number,baseRefName,title,mergedAt,mergeCommit")
    shas_json = gh("api", f"repos/{slug}/commits?sha={default}&per_page=100",
                   "--paginate", "--jq", ".[].sha")
    if prs_json is None or shas_json is None:
        print("  [SKIP]  could not read PRs or commits from GitHub. Not a pass.")
        return 1 if args.check else 0

    prs = json.loads(prs_json)
    landed = {s.strip() for s in shas_json.split() if s.strip()}
    reconciled = json.loads(RECONCILED.read_text(encoding="utf-8")) if RECONCILED.exists() else {}

    findings: list[str] = []
    for pr in prs:
        n = pr["number"]
        if str(n) in reconciled:
            continue
        if pr["baseRefName"] != default:
            findings.append(
                f"#{n} was merged into '{pr['baseRefName']}', not '{default}'. With squash "
                f"merges a stacked PR must be RE-TARGETED before its parent merges, or it "
                f"lands nowhere: \"{pr['title'][:60]}\"")
        else:
            sha = (pr.get("mergeCommit") or {}).get("oid")
            if sha and sha not in landed:
                findings.append(
                    f"#{n} is merged into '{default}' but its merge commit {sha[:8]} is not "
                    f"reachable from it. The content is not there: \"{pr['title'][:60]}\"")

    print(f"  examined {len(prs)} merged PR(s) against {len(landed)} commit(s) "
          f"on '{default}'")
    if reconciled:
        print(f"  {len(reconciled)} reconciled and not reported "
              f"(see {RECONCILED.name})")

    for f in findings:
        print(f"\n  [ERROR] {f}")

    if findings:
        print(f"\n  {len(findings)} PR(s) may have landed nowhere. Confirm the content is on "
              f"'{default}', then record it in {RECONCILED.name} with the PR that carried it.")
        return 1 if args.check else 0

    print("  [ok]    every merged PR reached the default branch")
    return 0


if __name__ == "__main__":
    sys.exit(main())
