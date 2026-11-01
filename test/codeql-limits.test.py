#!/usr/bin/env python3
"""
Every CodeQL invocation is held to a fixed --ram and --threads. Refs: TheHub #61062

keel's tasks carry no memory limit (on these cgroup v2 workers one stops the
container being created at all, mykronos D-174); the worker container carries
the cap, and every build on that worker shares it. CodeQL sizes its evaluator
from the memory and cores it can SEE, and inside a container /proc/meminfo and
nproc report the HOST's, so an unbounded `codeql database create|analyze`
plans for the whole VM that also runs production. The `sast` and
`mykronos-sast` jobs each run two of them at once (python and javascript, in
parallel), so an unbounded pair is the heaviest thing a keel commit starts.

binnacle's ci/scripts/codeql.sh (#61040, HubOps review of binnacle #52) has
held CodeQL to --ram=1024 --threads=2 since; keel's did not (keel #156's
follow-up). Graded against the REAL ci/scripts/codeql.sh and ci/pipeline.yml:

  * every `codeql database create` and `codeql database analyze` passes
    --ram and --threads, and the walk is not vacuous (it finds both);
  * the defaults those flags resolve to are at most 1024 MB and 2 threads;
  * no pipeline step overrides CODEQL_RAM or CODEQL_THREADS upward;
  * a synthetic script without the flags, or with a larger default, is
    reported, so the check can fail.

Standard library plus PyYAML (ci/requirements.txt).

    python test/codeql-limits.test.py
"""
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "ci" / "scripts" / "codeql.sh"
PIPELINE = ROOT / "ci" / "pipeline.yml"
MAX_RAM_MB = 1024
MAX_THREADS = 2

failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def commands(text):
    """Every `codeql database <verb>` command, continuation lines joined."""
    out = []
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r"\s*codeql\s+database\s+(create|analyze)\b", line)
        if m:
            cmd = line
            while cmd.rstrip().endswith("\\") and i + 1 < len(lines):
                i += 1
                cmd = cmd.rstrip()[:-1] + " " + lines[i]
            out.append((m.group(1), cmd))
        i += 1
    return out


def default_of(text, var):
    """The integer a `VAR="${VAR:-N}"` line defaults to, or None."""
    m = re.search(r'^\s*%s="\$\{%s:-(\d+)\}"' % (var, var), text, re.M)
    return int(m.group(1)) if m else None


def resolved(value, text, var):
    """A flag value: a literal, or ${VAR} resolved through its default."""
    if re.fullmatch(r"\d+", value):
        return int(value)
    if value in (f"${{{var}}}", f"${var}"):
        return default_of(text, var)
    return None


def problems(text):
    """What is wrong with a codeql.sh, as a list of strings (empty is good)."""
    found = commands(text)
    bad = []
    verbs = {v for v, _ in found}
    if verbs != {"create", "analyze"}:
        bad.append(f"expected database create and analyze, found {sorted(verbs)}")
    for verb, cmd in found:
        ram = re.search(r'--ram="?([^"\s]+)"?', cmd)
        threads = re.search(r'--threads="?([^"\s]+)"?', cmd)
        if not ram:
            bad.append(f"database {verb} has no --ram")
        else:
            v = resolved(ram.group(1), text, "CODEQL_RAM")
            if v is None or not 0 < v <= MAX_RAM_MB:
                bad.append(f"database {verb} --ram resolves to {v}")
        if not threads:
            bad.append(f"database {verb} has no --threads")
        else:
            v = resolved(threads.group(1), text, "CODEQL_THREADS")
            if v is None or not 0 < v <= MAX_THREADS:
                bad.append(f"database {verb} --threads resolves to {v}")
    return bad


def overrides(node, where="pipeline"):
    """Yield (where, key, value) for any CODEQL_RAM/CODEQL_THREADS param."""
    if isinstance(node, dict):
        for k, v in node.items():
            if k in ("CODEQL_RAM", "CODEQL_THREADS"):
                yield where, k, v
            yield from overrides(v, f"{where}.{k}")
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from overrides(v, f"{where}[{i}]")


print("── ci/scripts/codeql.sh: CodeQL is held to --ram and --threads (TheHub #61062) ──")
text = SCRIPT.read_text(encoding="utf-8")
found = problems(text)
check("every codeql database create/analyze passes --ram <= 1024 and --threads <= 2",
      not found, "; ".join(found))
check("the walk is not vacuous: it finds create and analyze",
      {v for v, _ in commands(text)} == {"create", "analyze"})

pipeline = yaml.safe_load(PIPELINE.read_text(encoding="utf-8"))
ups = []
for where, k, v in overrides(pipeline):
    limit = MAX_RAM_MB if k == "CODEQL_RAM" else MAX_THREADS
    try:
        ok = 0 < int(str(v)) <= limit
    except ValueError:
        ok = False
    if not ok:
        ups.append(f"{where}={v}")
check("no pipeline step raises CODEQL_RAM or CODEQL_THREADS", not ups, "; ".join(ups))

print("── the check can fail ──")
bare = "codeql database create db \\\n  --language=python\ncodeql database analyze db \\\n  -- x\n"
check("a script without the flags is reported", len(problems(bare)) == 4, problems(bare))
big = ('CODEQL_RAM="${CODEQL_RAM:-4096}"\nCODEQL_THREADS="${CODEQL_THREADS:-2}"\n'
       'codeql database create db \\\n  --ram="${CODEQL_RAM}" --threads="${CODEQL_THREADS}"\n'
       'codeql database analyze db \\\n  --ram="${CODEQL_RAM}" --threads="${CODEQL_THREADS}"\n')
check("a 4096 MB default is reported", len(problems(big)) == 2, problems(big))
good = big.replace("4096", "1024")
check("a 1024 MB / 2 thread script passes", problems(good) == [], problems(good))

if failures:
    print(f"\n{len(failures)} check(s) failed")
    sys.exit(1)
print("\nall checks passed")
