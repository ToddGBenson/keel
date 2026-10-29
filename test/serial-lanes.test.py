#!/usr/bin/env python3
"""
keel runs at most three heavy jobs at once. Refs: TheHub #61062, mykronos D-172

Every job that `get`s `repo` with `trigger: true` used to start on the same
version in the same minute: on 2026-10-27 one keel commit started 15 builds
within a minute on the two workers that share a host with production, and
TheHub production lost backend workers 11 times. thehub's pipeline solved the
same thing with three serial lanes (mykronos D-172, its
test_thehub_serial_lanes.py); this is that pattern, for keel.

These checks do not grep for group names. They read ci/pipeline.yml as
Concourse would - task steps, triggers, `passed:` constraints and serial
groups - and:

  * every job that runs a task container is in exactly one lane, and there are
    at most three lanes, so no trigger can put more than three keel task
    containers on the workers at once;
  * both CodeQL jobs share one lane, so two CodeQL evaluators never run at once;
  * no job in the commit verdict queues behind an ingestion (mykronos-*) job,
    except `sast`, which shares the CodeQL lane;
  * one main commit is replayed through the lanes with the durations Concourse
    measured, and the verdict (`verify-artifact`) and the last job must land
    inside a budget. A future edit that puts the verdict behind an ingestion
    upload fails here with the projected minutes and the timeline.

Needs PyYAML (ci/requirements.txt).

    python test/serial-lanes.test.py
"""
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
PIPELINE = ROOT / "ci" / "pipeline.yml"

# The ceiling on concurrent heavy jobs, as thehub's D-172 lanes.
MAX_LANES = 3

# Median run time, in minutes, of the last 60 builds of each job that
# SUCCEEDED, read anonymously from Concourse
# (/api/v1/teams/main/pipelines/keel/jobs/<job>/builds?limit=60) on
# 2026-10-29. Run time only: a build's start_time is set when it leaves the
# serial queue. Taken while 13-14 keel jobs ran at once, so they overstate a
# job that runs beside two others. mykronos-sca had only 6 successes.
P50 = {
    "set-pipeline": 0.18,
    "build": 0.35,
    "lint": 1.60,
    "test": 0.53,
    "sast": 8.88,
    "secrets": 0.25,
    "sca": 3.65,
    "iac": 4.93,
    "suppression-audit": 0.16,
    "platform-integrity": 0.28,
    "mykronos-sast": 15.81,
    "mykronos-secrets": 2.38,
    "mykronos-sca": 17.78,
    "mykronos-atlas": 5.16,
    "build-and-attest": 2.58,
    "verify-artifact": 1.53,
}

# Unbounded, on keel's last six main commits (first run of each job), the
# verdict landed 11.7-23.5 minutes after the commit and the last job 12.5-28.9.
# The lanes may cost the verdict a few minutes and the last lane some more;
# these budgets are what this change claims.
VERDICT_BUDGET = 20.0
LAST_JOB_BUDGET = 30.0
# Concourse orders a lane's queue by build creation, and every build a commit
# triggers is created in the same scheduler pass, so the order inside a lane
# is not something this file controls. With the worst order (the CodeQL lane
# running mykronos-sast before sast) the verdict must still beat this.
VERDICT_WORST_ORDER_BUDGET = 30.0

VERDICT_JOB = "verify-artifact"
GATHER_JOB = "build-and-attest"

failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


HOOKS = ("ensure", "on_success", "on_failure", "on_error", "on_abort", "try")


def task_steps(step):
    """Every task step reachable from `step`, hooks included."""
    if isinstance(step, list):
        for s in step:
            yield from task_steps(s)
        return
    if not isinstance(step, dict):
        return
    if "task" in step:
        yield step
    if "do" in step:
        yield from task_steps(step["do"])
    if "in_parallel" in step:
        par = step["in_parallel"]
        yield from task_steps(par.get("steps", []) if isinstance(par, dict) else par)
    for hook in HOOKS:
        if hook in step:
            yield from task_steps(step[hook])


def runs_a_task(job):
    return any(True for _ in task_steps([job.get("plan", [])] + [job.get(h) for h in HOOKS]))


def repo_trigger(job):
    for step in job.get("plan", []):
        if isinstance(step, dict) and step.get("get") == "repo" and step.get("trigger"):
            return step
    return None


def lanes_of(job):
    return list(job.get("serial_groups") or [])


def per_commit(jobs):
    """Every job a main commit triggers, mapped to the jobs it waits on."""
    out = {}
    for name, job in jobs.items():
        step = repo_trigger(job)
        if step is not None:
            out[name] = list(step.get("passed", []))
    return out


def replay(jobs, durations, worst_order=False):
    """Replay one commit through the serial groups. Returns (start, end) in minutes.

    Concourse runs a job once every job in its `passed:` list has finished, and
    never two jobs that share a serial group at the same time. Among jobs
    waiting on the same lane, the one ready first goes first, then pipeline
    order (or its reverse, for the worst case).
    """
    order = list(jobs)
    deps = per_commit(jobs)
    groups = {n: set(lanes_of(jobs[n])) for n in deps}
    start, end, busy_until = {}, {}, {}
    pending = set(deps)
    while pending:
        ready = [n for n in pending if all(d in end for d in deps[n])]
        if not ready:
            raise AssertionError(f"unsatisfiable passed: constraints among {sorted(pending)}")

        def earliest(n):
            t = max((end[d] for d in deps[n]), default=0.0)
            return max([t] + [busy_until.get(g, 0.0) for g in groups[n]])

        rank = (lambda n: -order.index(n)) if worst_order else order.index
        name = min(ready, key=lambda n: (earliest(n), rank(n)))
        start[name] = earliest(name)
        end[name] = start[name] + durations[name]
        for g in groups[name]:
            busy_until[g] = end[name]
        pending.remove(name)
    return start, end


def timeline(jobs, start, end):
    return "\n".join(
        f"    {n:20} {start[n]:5.1f} -> {end[n]:5.1f}  {lanes_of(jobs[n])}"
        for n in sorted(start, key=lambda n: (start[n], n)))


def main():
    doc = yaml.safe_load(PIPELINE.read_text(encoding="utf-8"))
    jobs = {job["name"]: job for job in doc["jobs"]}

    print("lanes")
    heavy = [n for n, j in jobs.items() if runs_a_task(j)]
    check(f"the walk finds the jobs that run a task ({len(heavy)})", len(heavy) >= 15,
          f"only {heavy}")
    not_one = {n: lanes_of(jobs[n]) for n in heavy if len(lanes_of(jobs[n])) != 1}
    check("every job that runs a task is in exactly one serial lane", not not_one,
          f"{not_one}")
    lanes = {g for j in jobs.values() for g in lanes_of(j)}
    check(f"at most {MAX_LANES} lanes, so at most {MAX_LANES} heavy jobs at once",
          1 < len(lanes) <= MAX_LANES, f"lanes: {sorted(lanes)}")
    unlaned = sorted(n for n in jobs if n not in heavy)
    check("the only job outside a lane is set-pipeline, which runs no task",
          unlaned == ["set-pipeline"], f"{unlaned}")

    codeql = sorted(n for n in heavy
                    if any(s.get("file", "").endswith("/codeql.yml")
                           for s in task_steps(jobs[n].get("plan", []))))
    codeql_lanes = {tuple(lanes_of(jobs[n])) for n in codeql}
    check(f"both CodeQL jobs share one lane ({codeql})",
          len(codeql) >= 2 and len(codeql_lanes) == 1, f"{codeql_lanes}")

    deps = per_commit(jobs)
    gather = repo_trigger(jobs[GATHER_JOB]) or {}
    verdict_chain = set(gather.get("passed", [])) | {GATHER_JOB, VERDICT_JOB}
    ingestion = {n for n in jobs if n.startswith("mykronos-")}
    behind = []
    for n in sorted(verdict_chain):
        if n in codeql:
            continue
        shared = [m for m in ingestion if set(lanes_of(jobs[m])) & set(lanes_of(jobs[n]))]
        if shared:
            behind.append(f"{n} shares a lane with {sorted(shared)}")
    check("no verdict job but sast queues behind an ingestion job", not behind, f"{behind}")

    print("one main commit, replayed at median durations")
    missing = sorted(set(deps) - set(P50))
    check("every job a commit triggers has a measured duration", not missing,
          f"no P50 for {missing}: measure it from Concourse and add it")
    if missing:
        return
    start, end = replay(jobs, P50)
    tl = timeline(jobs, start, end)
    last = max(end, key=end.get)
    check(f"the verdict lands at {end[VERDICT_JOB]:.1f}m, under {VERDICT_BUDGET:.0f}m",
          end[VERDICT_JOB] < VERDICT_BUDGET, "\n" + tl)
    check(f"the last job ({last}) ends at {end[last]:.1f}m, under {LAST_JOB_BUDGET:.0f}m",
          end[last] < LAST_JOB_BUDGET, "\n" + tl)
    tasked = [n for n in start if n in heavy]
    peak = max(sum(1 for m in tasked if start[m] <= start[n] < end[m]) for n in tasked)
    check(f"the replay never runs more than {MAX_LANES} task jobs at once (peak {peak})",
          peak <= MAX_LANES, "\n" + tl)
    wstart, wend = replay(jobs, P50, worst_order=True)
    check(f"in the worst lane order the verdict lands at {wend[VERDICT_JOB]:.1f}m, "
          f"under {VERDICT_WORST_ORDER_BUDGET:.0f}m",
          wend[VERDICT_JOB] < VERDICT_WORST_ORDER_BUDGET, "\n" + timeline(jobs, wstart, wend))
    print(tl)

    # Not vacuous: the same replay, on a pipeline with the verdict behind ingestion.
    print("the replay is not vacuous")
    fake = {
        "a": {"plan": [{"get": "repo", "trigger": True}, {"task": "t"}], "serial_groups": ["one"]},
        "b": {"plan": [{"get": "repo", "trigger": True}, {"task": "t"}], "serial_groups": ["one"]},
        "c": {"plan": [{"get": "repo", "trigger": True, "passed": ["a"]}, {"task": "t"}],
              "serial_groups": ["two"]},
    }
    fs, fe = replay(fake, {"a": 1.0, "b": 10.0, "c": 1.0})
    check("a job waits for its lane and for its passed: jobs",
          (fs, fe) == ({"a": 0.0, "b": 1.0, "c": 1.0}, {"a": 1.0, "b": 11.0, "c": 2.0}),
          f"{fs} {fe}")
    ws, we = replay(fake, {"a": 1.0, "b": 10.0, "c": 1.0}, worst_order=True)
    check("the worst order runs the lane's other job first", ws["a"] == 10.0, f"{ws}")


main()
if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)
print("\nall passed")
