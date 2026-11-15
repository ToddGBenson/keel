#!/usr/bin/env python3
"""
Every CodeQL invocation is held to a fixed --ram and --threads, and no job
runs two CodeQL evaluators at once. Refs: TheHub #61062, #169

keel's tasks carry no memory limit (on these cgroup v2 workers one stops the
container being created at all, mykronos D-174); the worker container carries
the cap, and every build on that worker shares it. CodeQL sizes its evaluator
from the memory and cores it can SEE, and inside a container /proc/meminfo and
nproc report the HOST's, so an unbounded `codeql database create|analyze`
plans for the whole VM that also runs production.

2048 MB is CodeQL's floor, not a choice (#169). v2.26.3 logs "rounding --ram up
to the minimum of 2048" for both create and analyze, so the 1024 this file once
held was never the value in force. Each evaluator budgets 2048 MB plus JVM
overhead, and two of them do not fit in one 3 GiB worker. `sast` ran python and
javascript under a bare `in_parallel`; in build 141 both were placed on one
worker and the javascript one was OOM-killed (exit 137). So every job that runs
more than one CodeQL step runs them one at a time.

binnacle's ci/scripts/codeql.sh (#61040, HubOps review of binnacle #52) has
held CodeQL to --ram=1024 --threads=2 since; keel's did not (keel #156's
follow-up). Graded against the REAL ci/scripts/codeql.sh, ci/pipeline.yml and
ci/tasks/codeql.yml:

  * every `codeql database create` and `codeql database analyze` passes
    --ram and --threads, and the walk is not vacuous (it finds both);
  * the defaults those flags resolve to are exactly 2048 MB (CodeQL's floor:
    a lower value is rounded up, so it would only misreport the budget) and at
    most 2 threads;
  * no pipeline step overrides CODEQL_RAM or CODEQL_THREADS upward, and
    neither does the task file's own `params:` (TheHub #61238: a task param
    reaches the script exactly as a pipeline param does);
  * no job runs two CodeQL steps concurrently: an `in_parallel` holding more
    than one codeql.yml task must set `limit: 1` (#169);
  * a synthetic script without the flags, or with a larger or smaller default,
    and a synthetic unlimited `in_parallel`, are reported, so the check can fail.

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
TASK = ROOT / "ci" / "tasks" / "codeql.yml"
# CodeQL v2.26.3 rounds --ram up to 2048 (keel #169, build 141). Below it the
# configured number is fiction; above it the evaluator crowds a 3 GiB worker.
MIN_RAM_MB = 2048
MAX_RAM_MB = 2048
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
            if v is None or not MIN_RAM_MB <= v <= MAX_RAM_MB:
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


print("-- ci/scripts/codeql.sh: CodeQL is held to --ram and --threads (TheHub #61062) --")
text = SCRIPT.read_text(encoding="utf-8")
found = problems(text)
check("every codeql database create/analyze passes --ram = 2048 and --threads <= 2",
      not found, "; ".join(found))
check("the walk is not vacuous: it finds create and analyze",
      {v for v, _ in commands(text)} == {"create", "analyze"})

def upward(node, where):
    """Every CODEQL_RAM/CODEQL_THREADS value under `node` above its limit."""
    ups = []
    for at, k, v in overrides(node, where):
        lo, hi = (MIN_RAM_MB, MAX_RAM_MB) if k == "CODEQL_RAM" else (1, MAX_THREADS)
        try:
            ok = lo <= int(str(v)) <= hi
        except ValueError:
            ok = False
        if not ok:
            ups.append(f"{at}={v}")
    return ups


pipeline = yaml.safe_load(PIPELINE.read_text(encoding="utf-8"))
ups = upward(pipeline, "pipeline")
check("no pipeline step raises CODEQL_RAM or CODEQL_THREADS", not ups, "; ".join(ups))
task = yaml.safe_load(TASK.read_text(encoding="utf-8"))
tups = upward(task, "ci/tasks/codeql.yml")
check("ci/tasks/codeql.yml does not raise CODEQL_RAM or CODEQL_THREADS", not tups,
      "; ".join(tups))
check("the task file is the one the CodeQL steps run",
      "codeql.sh" in str(task.get("run", {}).get("args")) and "params" in task)


def is_codeql(step):
    return isinstance(step, dict) and str(step.get("file", "")).endswith("/codeql.yml")


def codeql_steps(node):
    """Every codeql.yml task step anywhere under `node`."""
    if is_codeql(node):
        yield node
    if isinstance(node, dict):
        for v in node.values():
            yield from codeql_steps(v)
    elif isinstance(node, list):
        for v in node:
            yield from codeql_steps(v)


def concurrent_codeql(node, where):
    """Every in_parallel that can run two CodeQL steps at the same time."""
    bad = []
    if isinstance(node, dict):
        par = node.get("in_parallel")
        if par is not None:
            steps = par.get("steps", []) if isinstance(par, dict) else par
            limit = par.get("limit") if isinstance(par, dict) else None
            branches = sum(1 for s in steps if any(True for _ in codeql_steps(s)))
            if branches > 1 and limit != 1:
                bad.append(f"{where}.in_parallel ({branches} CodeQL branches, limit={limit})")
        for k, v in node.items():
            bad += concurrent_codeql(v, f"{where}.{k}")
    elif isinstance(node, list):
        for i, v in enumerate(node):
            bad += concurrent_codeql(v, f"{where}[{i}]")
    return bad


print("-- no job runs two CodeQL evaluators at once (#169) --")
jobs = {j["name"]: j for j in pipeline.get("jobs", [])}
multi = sorted(n for n, j in jobs.items() if len(list(codeql_steps(j.get("plan", [])))) > 1)
check(f"the walk is not vacuous: jobs with two CodeQL steps {multi}",
      {"sast", "mykronos-sast"} <= set(multi), f"{multi}")
for n in multi:
    conc = concurrent_codeql(jobs[n].get("plan", []), n)
    check(f"{n} runs its CodeQL steps one at a time", not conc, "; ".join(conc))

print("-- the check can fail --")
bare = "codeql database create db \\\n  --language=python\ncodeql database analyze db \\\n  -- x\n"
check("a script without the flags is reported", len(problems(bare)) == 4, problems(bare))
big = ('CODEQL_RAM="${CODEQL_RAM:-4096}"\nCODEQL_THREADS="${CODEQL_THREADS:-2}"\n'
       'codeql database create db \\\n  --ram="${CODEQL_RAM}" --threads="${CODEQL_THREADS}"\n'
       'codeql database analyze db \\\n  --ram="${CODEQL_RAM}" --threads="${CODEQL_THREADS}"\n')
check("a 4096 MB default is reported", len(problems(big)) == 2, problems(big))
good = big.replace("4096", "2048")
check("a 2048 MB / 2 thread script passes", problems(good) == [], problems(good))
small = big.replace("4096", "1024")
check("a 1024 MB default (silently rounded up to 2048) is reported",
      len(problems(small)) == 2, problems(small))
raised = {"params": {"CODEQL_LANGUAGE": "", "CODEQL_RAM": "4096", "CODEQL_THREADS": 2}}
check("a task file that raises CODEQL_RAM is reported, and 2 threads is not",
      upward(raised, "t") == ["t.params=4096"], upward(raised, "t"))

cq = {"task": "x", "file": "repo/ci/tasks/codeql.yml"}
bare_par = [{"in_parallel": [dict(cq), dict(cq)]}]
check("a bare in_parallel of two CodeQL steps is reported",
      len(concurrent_codeql(bare_par, "j")) == 1, concurrent_codeql(bare_par, "j"))
wide = [{"in_parallel": {"limit": 2, "steps": [dict(cq), dict(cq)]}}]
check("an in_parallel with limit: 2 is reported", len(concurrent_codeql(wide, "j")) == 1)
nested = [{"in_parallel": {"steps": [{"do": [dict(cq)]}, {"do": [dict(cq)]}]}}]
check("CodeQL steps nested in do: branches are seen", len(concurrent_codeql(nested, "j")) == 1)
one = [{"in_parallel": {"limit": 1, "steps": [dict(cq), dict(cq)]}}]
check("limit: 1 passes", concurrent_codeql(one, "j") == [])

if failures:
    print(f"\n{len(failures)} check(s) failed")
    sys.exit(1)
print("\nall checks passed")
