#!/usr/bin/env python3
"""
Every Concourse task yields CPU and sets no memory limit. Refs: TheHub #61062, #61009

keel's tasks run on the two workers that share one Docker host with
production (TheHub, MyKronos, Vault). On 2026-10-23 uncapped test containers on
that host took TheHub down, and on 2026-10-27 a keel commit's fan-out cost
TheHub production 11 backend worker deaths. So every task this pipeline can
run must resolve to a config with `container_limits.cpu` -- a share below the
default 1024, so under contention production wins -- and NO
`container_limits.memory`.

WHY MEMORY IS FORBIDDEN (mykronos D-174, TheHub #61009). On these workers
(cgroup v2) a task with `container_limits.memory` cannot even be created: runc
fails with "cannot enter cgroupv2 /sys/fs/cgroup/garden with domain
controllers -- it is in threaded mode". A memory cap would turn every lane into
a container-creation error. Memory is capped on the WORKER containers instead
(D-174), which bounds every task on them.

The limits half of binnacle's test/container-limits.test.py (TheHub #61040),
which a keel fork already runs; binnacle's copy also checks its own Vault
paths, which keel does not share. Graded against the REAL ci/pipeline.yml and
ci/tasks/:

  * every task step in every job (do / ensure / on_* / try / in_parallel,
    anchors expanded) resolves to a config, from `file:` or inline `config:`,
    whose container_limits set cpu within range and set no memory -- a
    step-level `container_limits:` counts, as Concourse applies it over the
    file's;
  * every ci/tasks/*.yml carries them, referenced or not, so a lane wired in
    later starts capped;
  * the walk is not vacuous: it finds the task steps it should, and a
    synthetic task without limits, or with a memory limit, is reported.

Needs PyYAML (ci/requirements.txt).

    python test/container-limits.test.py
"""
import sys
import tempfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
GIB = 1024 ** 3
DEFAULT_CPU_SHARES = 1024

failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


# ── The walk ────────────────────────────────────────────────────────────────
HOOKS = ("ensure", "on_success", "on_failure", "on_error", "on_abort", "try")


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
    if "do" in step:
        yield from task_steps(step["do"], f"{where}.do")
    if "in_parallel" in step:
        par = step["in_parallel"]
        yield from task_steps(par.get("steps", []) if isinstance(par, dict) else par,
                              f"{where}.in_parallel")
    for hook in HOOKS:
        if hook in step:
            yield from task_steps(step[hook], f"{where}.{hook}")


def cpu_problems(limits, label):
    """Why `limits` does not set an acceptable cpu share, or [] when it does."""
    if not isinstance(limits, dict) or not limits:
        return [f"{label}: no container_limits"]
    cpu = limits.get("cpu")
    if not isinstance(cpu, int) or not 0 < cpu < DEFAULT_CPU_SHARES:
        return [f"{label}: cpu {cpu!r} is not 1..{DEFAULT_CPU_SHARES - 1} shares"]
    return []


def resolve(step, root):
    """(task-config limits, step-level limits, error) for one task step."""
    if "config" in step:
        config = step["config"]
    elif "file" in step:
        rel = step["file"]
        if not rel.startswith("repo/"):
            return None, None, f"file {rel} is not in repo/"
        path = root / rel[len("repo/"):]
        if not path.is_file():
            return None, None, f"{rel} does not exist"
        config = yaml.safe_load(path.read_text(encoding="utf-8"))
    else:
        return None, None, "neither file nor config"
    return (config or {}).get("container_limits") or {}, step.get("container_limits") or {}, None


def walk(pipeline, root):
    """(task steps found, cpu problems, steps that set memory)."""
    n, cpu, memory = 0, [], []
    for job in pipeline.get("jobs", []):
        for where, step in task_steps(job.get("plan", []), job["name"]):
            n += 1
            label = f"{where} task {step['task']}"
            file_limits, step_limits, err = resolve(step, root)
            if err:
                cpu.append(f"{label}: {err}")
                continue
            # A step-level container_limits is applied over the task config's,
            # so a memory limit in EITHER reaches runc.
            cpu += cpu_problems({**file_limits, **step_limits}, label)
            if "memory" in file_limits or "memory" in step_limits:
                memory.append(label)
    return n, cpu, memory


# Modelled on mykronos #61009's test_no_task_sets_a_memory_limit_the_workers_cannot_apply.
MEMORY_REASON = (
    "container_limits.memory makes runc refuse the task container on these "
    "guardian workers ('cannot enter cgroupv2 /sys/fs/cgroup/garden with domain "
    "controllers -- it is in threaded mode'), so the task fails on every run. "
    "Memory is capped on the worker containers instead (mykronos D-174)")

pipeline = yaml.safe_load((ROOT / "ci" / "pipeline.yml").read_text(encoding="utf-8"))
n, cpu_bad, mem_bad = walk(pipeline, ROOT)

print("container limits")
check(f"the walk finds the pipeline's task steps ({n})", n >= 40, f"only {n}")
check("every task step sets a cpu share below the default", cpu_bad == [],
      "\n    " + "\n    ".join(cpu_bad))
check("no task step sets a memory limit the workers cannot apply", mem_bad == [],
      f"\n    {MEMORY_REASON}: {mem_bad[:10]}")

file_cpu_bad, file_mem_bad = [], []
for f in sorted((ROOT / "ci" / "tasks").glob("*.yml")):
    limits = (yaml.safe_load(f.read_text(encoding="utf-8")) or {}).get("container_limits")
    file_cpu_bad += cpu_problems(limits, f"ci/tasks/{f.name}")
    if isinstance(limits, dict) and "memory" in limits:
        file_mem_bad.append(f"ci/tasks/{f.name}")
check("every ci/tasks/*.yml sets cpu, referenced or not", file_cpu_bad == [], f"{file_cpu_bad}")
check("no ci/tasks/*.yml sets a memory limit the workers cannot apply", file_mem_bad == [],
      f"\n    {MEMORY_REASON}: {file_mem_bad[:10]}")

# Not vacuous: the same checker, on a pipeline that should fail it.
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    (root / "ci" / "tasks").mkdir(parents=True)
    (root / "ci" / "tasks" / "bare.yml").write_text("platform: linux\nrun: {path: true}\n")
    (root / "ci" / "tasks" / "withmem.yml").write_text(
        "platform: linux\ncontainer_limits: {cpu: 512, memory: 2147483648}\nrun: {path: true}\n")
    (root / "ci" / "tasks" / "ok.yml").write_text(
        "platform: linux\ncontainer_limits: {cpu: 512}\nrun: {path: true}\n")
    fake = {"jobs": [{"name": "j", "plan": [
        {"get": "repo"},
        {"task": "fine", "file": "repo/ci/tasks/ok.yml"},
        {"do": [{"task": "bare", "file": "repo/ci/tasks/bare.yml"}],
         "ensure": {"task": "withmem", "file": "repo/ci/tasks/withmem.yml",
                    "on_failure": {"task": "inline", "config": {"platform": "linux"}}}},
        {"task": "override", "file": "repo/ci/tasks/bare.yml",
         "container_limits": {"cpu": 256}},
        {"task": "stepmem", "file": "repo/ci/tasks/ok.yml",
         "container_limits": {"cpu": 256, "memory": GIB}},
        # A step override without memory does not hide the file's memory.
        {"task": "hiddenmem", "file": "repo/ci/tasks/withmem.yml",
         "container_limits": {"cpu": 256}},
    ]}]}
    fn, fcpu, fmem = walk(fake, root)
    check("a synthetic pipeline: all seven task steps are found", fn == 7, f"found {fn}")
    no_cpu = sorted({p.split(" task ")[1].split(":")[0] for p in fcpu})
    check("a task file and an inline config without a cpu share are each reported",
          no_cpu == ["bare", "inline"], f"{no_cpu}")
    with_mem = sorted(p.split(" task ")[1] for p in fmem)
    check("a memory limit in a task file, on a step, or under a step override is each reported",
          with_mem == ["hiddenmem", "stepmem", "withmem"], f"{with_mem}")


if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)
print("\nall passed")
