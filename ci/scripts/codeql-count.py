#!/usr/bin/env python3
"""Count CodeQL SECURITY findings at severity >= medium. Refs: #42

Separate from codeql.sh because a Python heredoc nested inside a shell heredoc
inside a generator is exactly how the quoting bugs in this repo get written.

`security-severity` is a CVSS-like number set only on security queries; >= 4.0 is
medium and above. A rule without it is a quality finding, and quality findings do
not gate — they would turn `security-and-quality` into a style gate and the lane
would be switched off within a week.
"""
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "mykronos-results/codeql.sarif")
if not path.exists():
    print(0)
    raise SystemExit(0)

doc = json.loads(path.read_text(encoding="utf-8"))
count = 0
for run in doc.get("runs", []):
    rules = {r.get("id"): r for r in run.get("tool", {}).get("driver", {}).get("rules", [])}
    for result in run.get("results", []):
        sev = rules.get(result.get("ruleId"), {}).get("properties", {}).get("security-severity")
        try:
            if sev is not None and float(sev) >= 4.0:
                count += 1
        except (TypeError, ValueError):
            continue
print(count)
