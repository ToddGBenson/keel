#!/usr/bin/env python3
"""Verify platform/MANIFEST.yml actually governs this repository. Refs: #56

keel is a TEMPLATE. It ships no artifact, so it has no build to break and no
deploy to fail. Its delivery mechanism is `scripts/sync-platform.sh`, and the
contract that mechanism obeys is `platform/MANIFEST.yml`.

That makes the manifest the closest thing this repository has to a build output,
and until now nothing checked it. The failure mode is silent in the worst way: a
path nobody classified is simply never delivered to a fork, and no fork can
notice something it was never sent.

This is not hypothetical. `ci/` — the entire Concourse pipeline — sat
unclassified after being added, and was only caught by hand. At the time of
writing this check first ran, nine tracked paths were unclassified, including
`keel` (the CLI the operator actually types) and `evals/`.

What it checks
--------------
1. Every tracked top-level path is classified. Unclassified means ungoverned.
2. Every platform_owned and merge_required entry exists. Those are what upstream
   ships; an entry pointing at nothing is a promise it cannot keep.
3. No path is claimed by two buckets — the three-way split is only meaningful if
   each path has exactly one answer.

What it deliberately does NOT check
-----------------------------------
project_owned and bootstrap_only entries are allowed to point at nothing. They
describe what a FORK will have (`src/`, `app/`, `package.json`), not what this
repository contains. Requiring them to exist would be requiring the template to
be an application, which is the confusion this whole change exists to remove.

    python scripts/validate-manifest.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    print("PyYAML is required: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "platform" / "MANIFEST.yml"

# Buckets whose entries must exist here, because upstream ships them.
MUST_EXIST = ("platform_owned", "merge_required")
# Buckets that legitimately describe a fork's future content.
MAY_BE_ABSENT = ("project_owned", "bootstrap_only")

errors: list[str] = []
warnings: list[str] = []


def tracked_files() -> list[str]:
    out = subprocess.run(["git", "ls-files"], cwd=ROOT,
                         capture_output=True, text=True, encoding="utf-8")
    return out.stdout.split()


def main() -> int:
    if not MANIFEST.exists():
        print(f"[ERROR] {MANIFEST.relative_to(ROOT)} does not exist")
        return 1

    manifest = yaml.safe_load(MANIFEST.read_text(encoding="utf-8")) or {}
    buckets = {k: [e for e in v if isinstance(e, str)]
               for k, v in manifest.items() if isinstance(v, list)}

    files = tracked_files()
    top_level = sorted({p.split("/")[0] + ("/" if "/" in p else "") for p in files})

    claimed: dict[str, list[str]] = {}
    for bucket, entries in buckets.items():
        for entry in entries:
            claimed.setdefault(entry, []).append(bucket)

    # 1 — every tracked top-level path is governed by some bucket.
    for path in top_level:
        if not any(path == c or path.startswith(c) or c.startswith(path) for c in claimed):
            errors.append(
                f"'{path}' is tracked but classified by no bucket. sync-platform.sh "
                f"will never deliver it to a fork, and no fork can notice a file it "
                f"was never sent.")

    # 2 — what upstream ships must be here.
    for bucket in MUST_EXIST:
        for entry in buckets.get(bucket, []):
            target = entry.rstrip("/")
            if not (ROOT / target).exists():
                errors.append(
                    f"{bucket} lists '{entry}' which does not exist. Upstream cannot "
                    f"ship what it does not have.")

    # 3 — exactly one answer per path.
    for entry, owners in sorted(claimed.items()):
        if len(owners) > 1:
            errors.append(
                f"'{entry}' is claimed by {owners}. The three-way split only means "
                f"something if each path has exactly one answer.")

    # Informational: forward-looking placeholders, which are correct and worth
    # showing so nobody 'tidies' them away.
    absent = [e for b in MAY_BE_ABSENT for e in buckets.get(b, [])
              if not (ROOT / e.rstrip("/")).exists()]
    if absent:
        warnings.append(
            f"{len(absent)} project_owned/bootstrap_only entries point at paths this "
            f"repository does not have — correct, they describe a fork's content "
            f"({', '.join(sorted(absent)[:4])}…)")

    print("Platform manifest validation")
    print(f"  {len(files)} tracked files, {len(top_level)} top-level paths, "
          f"{len(claimed)} manifest entries")
    for w in warnings:
        print(f"  [warn]  {w}")
    for e in errors:
        print(f"  [ERROR] {e}")
    if errors:
        print(f"\n  {len(errors)} error(s). The manifest is this template's delivery "
              f"contract; an unclassified path is one no fork will ever receive.")
        return 1
    print("  [ok]    every tracked path is governed, and every shipped entry exists")
    return 0


if __name__ == "__main__":
    sys.exit(main())
