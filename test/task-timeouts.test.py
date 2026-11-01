#!/usr/bin/env python3
"""
Every task step has a timeout, so a hung job cannot hold its lane. Refs: TheHub #61062

The three `serial_groups` lanes (keel #156, D-172) mean a job that hangs
blocks every later job in its lane, for every later commit, until it ends.
Before this, keel's only step timeouts were on its check-run hooks. On
2026-10-31 the commit-triggered run of 9699ecb started one job per lane at
03:47:44Z (iac, mykronos-secrets, sast), all three hung, and all three
errored at 13:30:03Z: 9.7 hours with every keel lane shut.

MAX_TIMEOUT is 3h. The longest SUCCESSFUL keel job in the last 100 builds of
each, measured from Concourse on 2026-11-01, was mykronos-sast at 138.7
minutes, during the unbounded fan-out storms, before the lanes. Its median is
16.8. So 3h kills no run that has ever passed, and it bounds a hang to a third
of the 9.7 hours above.

Graded against the REAL ci/pipeline.yml, anchors expanded:

  * every task step in every job (plan, do, in_parallel, try and every
    ensure/on_* hook) declares `timeout:`, at most MAX_TIMEOUT;
  * the walk is not vacuous: it finds the task steps it should;
  * a synthetic job with no timeout, or with one above the ceiling, is
    reported.

Needs PyYAML (ci/requirements.txt).

    python test/task-timeouts.test.py
"""
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
MAX_TIMEOUT_S = 3 * 3600

failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


HOOKS = ("ensure", "on_success", "on_failure", "on_error", "on_abort")


def task_steps(step, where):
    """Yield (where, step) for every task step reachable from `step`."""
    if isinstance(step, list):
        for i, s in enumerate(step):
            yield from task_steps(s, f"{where}[{i}]")
        return
    if not isinstance(step, dict):
        return
    if "task" in step:
        yield where, step
    for key in ("do", "try"):
        if key in step:
            yield from task_steps(step[key], f"{where}.{key}")
    if "in_parallel" in step:
        par = step["in_parallel"]
        yield from task_steps(par.get("steps", []) if isinstance(par, dict) else par,
                              f"{where}.in_parallel")
    for hook in HOOKS:
        if hook in step:
            yield from task_steps(step[hook], f"{where}.{hook}")


def seconds(duration):
    """A Concourse duration ("90m", "1h30m", "45s") in seconds, or None."""
    if not isinstance(duration, str):
        return None
    parts = re.findall(r"(\d+(?:\.\d+)?)(h|m|s)", duration)
    if not parts or "".join(n + u for n, u in parts) != duration:
        return None
    unit = {"h": 3600, "m": 60, "s": 1}
    return sum(float(n) * unit[u] for n, u in parts)


def problems(pipeline):
    """(task steps found, list of problems)."""
    n, bad = 0, []
    for job in pipeline.get("jobs", []):
        roots = [("plan", job.get("plan", []))]
        roots += [(h, job[h]) for h in HOOKS if h in job]
        for key, root in roots:
            for where, step in task_steps(root, f"{job['name']}.{key}"):
                n += 1
                label = f"{where} task {step['task']}"
                if "timeout" not in step:
                    bad.append(f"{label}: no timeout")
                    continue
                s = seconds(step["timeout"])
                if s is None or not 0 < s <= MAX_TIMEOUT_S:
                    bad.append(f"{label}: timeout {step['timeout']!r} is not 1s..3h")
    return n, bad


print("-- ci/pipeline.yml: every task step has a timeout of at most 3h (TheHub #61062) --")
pipeline = yaml.safe_load((ROOT / "ci" / "pipeline.yml").read_text(encoding="utf-8"))
n, bad = problems(pipeline)
check(f"every task step declares a timeout <= 3h ({n} task steps)", not bad,
      "\n         " + "\n         ".join(bad))
heavy = {"sast", "mykronos-sast", "iac", "mykronos-secrets", "sca", "mykronos-sca", "lint"}
jobs = {j["name"] for j in pipeline.get("jobs", [])}
check("the walk is not vacuous: it reaches the heavy jobs and their hooks",
      heavy <= jobs and n >= 2 * len(heavy), f"{n} task steps")

print("-- the check can fail --")
synthetic = {"jobs": [{
    "name": "x",
    "plan": [{"in_parallel": [{"task": "a", "timeout": "30m"},
                              {"task": "b"}]},
             {"do": [{"task": "c", "timeout": "4h"}]}],
    "on_failure": {"task": "d"},
}]}
_, sbad = problems(synthetic)
check("a missing timeout, a 4h timeout and a hook without one are reported",
      len(sbad) == 3 and all(("x.plan" in p) or ("on_failure" in p) for p in sbad), sbad)
check("durations parse", seconds("3h") == 10800 and seconds("1h30m") == 5400
      and seconds("5m") == 300 and seconds("3 h") is None and seconds(5) is None)

if failures:
    print(f"\n{len(failures)} check(s) failed")
    sys.exit(1)
print("\nall checks passed")
