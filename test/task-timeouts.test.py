#!/usr/bin/env python3
"""
Every task, get and set_pipeline step has a timeout, so a hung job cannot hold
its lane. Refs: TheHub #61062, TheHub #61238

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

MAX_GET_TIMEOUT is 15m (TheHub #61238, the follow-up from keel #159's review).
A `get` of the git repo can stall on the network, and any get can stall on a
sealed Vault credential; that would hold a lane exactly as a hung task does.
The longest get step (resource or task image) in the last 4 builds of 12 keel
jobs, read from Concourse on 2026-11-03, took 55 s (set-pipeline's repo get;
every other job's longest was 47 s or less). 15m is 16 times that.
`set_pipeline: self` is bounded the same way: it reads a file already fetched.

Graded against the REAL ci/pipeline.yml, anchors expanded:

  * every task step in every job (plan, do, in_parallel, try and every
    ensure/on_* hook) declares `timeout:`, at most MAX_TIMEOUT;
  * every get and set_pipeline step, in the same places, declares `timeout:`,
    at most MAX_GET_TIMEOUT;
  * the walk is not vacuous: it finds the task steps it should;
  * a synthetic job with no timeout, or with one above the ceiling, is
    reported, for tasks and for gets.

Needs PyYAML (ci/requirements.txt).

    python test/task-timeouts.test.py
"""
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
MAX_TIMEOUT_S = 3 * 3600
MAX_GET_TIMEOUT_S = 15 * 60
# Step kind -> its ceiling. A step is classified by the first of these keys.
CEILINGS = {"task": MAX_TIMEOUT_S, "get": MAX_GET_TIMEOUT_S,
            "set_pipeline": MAX_GET_TIMEOUT_S}

failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


HOOKS = ("ensure", "on_success", "on_failure", "on_error", "on_abort")


def kind_of(step):
    """The bounded step kind ("task", "get", "set_pipeline") of `step`, or None."""
    return next((k for k in CEILINGS if k in step), None)


def bounded_steps(step, where):
    """Yield (where, kind, step) for every task, get or set_pipeline step
    reachable from `step`."""
    if isinstance(step, list):
        for i, s in enumerate(step):
            yield from bounded_steps(s, f"{where}[{i}]")
        return
    if not isinstance(step, dict):
        return
    kind = kind_of(step)
    if kind:
        yield where, kind, step
    for key in ("do", "try"):
        if key in step:
            yield from bounded_steps(step[key], f"{where}.{key}")
    if "in_parallel" in step:
        par = step["in_parallel"]
        yield from bounded_steps(par.get("steps", []) if isinstance(par, dict) else par,
                                 f"{where}.in_parallel")
    for hook in HOOKS:
        if hook in step:
            yield from bounded_steps(step[hook], f"{where}.{hook}")


def seconds(duration):
    """A Concourse duration ("90m", "1h30m", "45s") in seconds, or None."""
    if not isinstance(duration, str):
        return None
    parts = re.findall(r"(\d+(?:\.\d+)?)(h|m|s)", duration)
    if not parts or "".join(n + u for n, u in parts) != duration:
        return None
    unit = {"h": 3600, "m": 60, "s": 1}
    return sum(float(n) * unit[u] for n, u in parts)


def ceiling_label(limit):
    return f"{limit // 3600}h" if limit % 3600 == 0 else f"{limit // 60}m"


def problems(pipeline):
    """({kind: steps found}, list of problems)."""
    n, bad = {k: 0 for k in CEILINGS}, []
    for job in pipeline.get("jobs", []):
        roots = [("plan", job.get("plan", []))]
        roots += [(h, job[h]) for h in HOOKS if h in job]
        for key, root in roots:
            for where, kind, step in bounded_steps(root, f"{job['name']}.{key}"):
                n[kind] += 1
                limit = CEILINGS[kind]
                label = f"{where} {kind} {step[kind]}"
                if "timeout" not in step:
                    bad.append(f"{label}: no timeout")
                    continue
                s = seconds(step["timeout"])
                if s is None or not 0 < s <= limit:
                    bad.append(f"{label}: timeout {step['timeout']!r} "
                               f"is not 1s..{ceiling_label(limit)}")
    return n, bad


print("-- ci/pipeline.yml: every task step times out within 3h, every get and "
      "set_pipeline step within 15m (TheHub #61062, #61238) --")
pipeline = yaml.safe_load((ROOT / "ci" / "pipeline.yml").read_text(encoding="utf-8"))
n, bad = problems(pipeline)
task_bad = [p for p in bad if " task " in p]
get_bad = [p for p in bad if " task " not in p]
check(f"every task step declares a timeout <= 3h ({n['task']} task steps)", not task_bad,
      "\n         " + "\n         ".join(task_bad))
check(f"every get and set_pipeline step declares a timeout <= 15m "
      f"({n['get']} get steps, {n['set_pipeline']} set_pipeline)", not get_bad,
      "\n         " + "\n         ".join(get_bad))
heavy = {"sast", "mykronos-sast", "iac", "mykronos-secrets", "sca", "mykronos-sca", "lint"}
jobs = {j["name"] for j in pipeline.get("jobs", [])}
check("the walk is not vacuous: it reaches the heavy jobs, their hooks and their gets",
      heavy <= jobs and n["task"] >= 2 * len(heavy) and n["get"] >= len(jobs)
      and n["set_pipeline"] >= 1, n)

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
gets = {"jobs": [{
    "name": "y",
    "plan": [{"get": "repo", "trigger": True},
             {"in_parallel": [{"get": "a", "timeout": "15m"},
                              {"get": "b", "timeout": "1h"}]},
             {"set_pipeline": "self", "file": "repo/ci/pipeline.yml"},
             {"task": "t", "timeout": "1h"}],
}]}
gn, gbad = problems(gets)
check("a get without a timeout, a 1h get and an unbounded set_pipeline are reported; "
      "a 1h task is not",
      len(gbad) == 3 and gn == {"task": 1, "get": 3, "set_pipeline": 1}
      and any("get repo: no timeout" in p for p in gbad)
      and any("get b: timeout '1h'" in p for p in gbad)
      and any("set_pipeline self: no timeout" in p for p in gbad), gbad)
check("durations parse", seconds("3h") == 10800 and seconds("1h30m") == 5400
      and seconds("5m") == 300 and seconds("3 h") is None and seconds(5) is None)

if failures:
    print(f"\n{len(failures)} check(s) failed")
    sys.exit(1)
print("\nall checks passed")
