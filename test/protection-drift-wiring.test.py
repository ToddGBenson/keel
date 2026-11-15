#!/usr/bin/env python3
"""
keel's own wiring of the branch-protection drift check. Refs: TheHub #60979

PROJECT-OWNED, unlike test/protection-drift.test.py. These checks read ci/
(merge_required: a fork adapts its pipeline), and a platform-owned test must
open no ci/ or .github/ file (test/supply-chain.test.py enforces that).

  * a `protection-drift` job is triggered by daily-0600 and by nothing else (a
    commit does not change GitHub's settings);
  * it runs ci/tasks/protection-drift.yml, whose script runs
    `scripts/configure-github.sh --verify-only`;
  * its token is GH_TOKEN, read from the credential manager as
    ((github_protection_token)) and from nowhere else;
  * the script fails loudly, before any API call, when that token is empty
    (Vault seals on reboot; a missing token must never read as "no drift");
  * the script never traces (`set -x`) and never prints the token;
  * test/manifest.txt runs both drift tests, so ci/scripts/ci-stage.sh does.

    python test/protection-drift-wiring.test.py
"""
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
BASH = shutil.which("bash") or "bash"
failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


print("protection-drift wiring (TheHub #60979)")
pipeline = yaml.safe_load((ROOT / "ci" / "pipeline.yml").read_text(encoding="utf-8"))
jobs = {j["name"]: j for j in pipeline.get("jobs", [])}
job = jobs.get("protection-drift") or {}
check("a protection-drift job exists", bool(job))


def steps(plan):
    for s in plan or []:
        if isinstance(s, dict):
            yield s
            for k in ("do", "ensure", "on_failure", "on_success", "try"):
                v = s.get(k)
                if isinstance(v, list):
                    yield from steps(v)
                elif isinstance(v, dict):
                    yield from steps([v])


plan = list(steps(job.get("plan")))
gets = {s["get"]: s for s in plan if "get" in s}
check("it is triggered by daily-0600", gets.get("daily-0600", {}).get("trigger") is True, str(gets))
triggers = sorted(name for name, s in gets.items() if s.get("trigger"))
check("daily-0600 is its only trigger", triggers == ["daily-0600"], str(triggers))
tasks = [s for s in plan if "task" in s]
check("it runs ci/tasks/protection-drift.yml",
      any(s.get("file") == "repo/ci/tasks/protection-drift.yml" for s in tasks), str(tasks))
params = {}
for s in tasks:
    params.update(s.get("params") or {})
check("GH_TOKEN comes from ((github_protection_token))",
      params.get("GH_TOKEN") == "((github_protection_token))", str(params))
check("no other param carries a credential",
      not [k for k, v in params.items() if k != "GH_TOKEN" and "token" in str(v).lower()], str(params))
groups = [g["name"] for g in pipeline.get("groups", []) if "protection-drift" in g.get("jobs", [])]
check("it is in the governance and scheduled groups",
      {"governance", "scheduled"} <= set(groups), str(groups))

task_path = ROOT / "ci" / "tasks" / "protection-drift.yml"
task = yaml.safe_load(task_path.read_text(encoding="utf-8")) if task_path.exists() else {}
check("the task declares GH_TOKEN", "GH_TOKEN" in (task.get("params") or {}), str(task))
args = (task.get("run") or {}).get("args") or []
check("the task runs ci/scripts/protection-drift.sh",
      "repo/ci/scripts/protection-drift.sh" in args, str(args))

script_path = ROOT / "ci" / "scripts" / "protection-drift.sh"
script = script_path.read_text(encoding="utf-8") if script_path.exists() else ""
live = [ln for ln in script.splitlines() if not ln.lstrip().startswith("#")]
check("protection-drift.sh runs `scripts/configure-github.sh --verify-only`",
      any(re.search(r"scripts/configure-github\.sh --verify-only\b", ln) for ln in live))
check("protection-drift.sh never traces (set -x)",
      not any(re.search(r"\bset\s+-[a-zA-Z]*x", ln) for ln in live), str(live))
check("protection-drift.sh never echoes the token",
      not any(re.search(r"(echo|printf).*\$\{?GH_TOKEN", ln) for ln in live), str(live))

# Fails loudly with no token, before anything else. Run from a scratch cwd: the
# script finds the repository from its own path, as the Concourse task does.
if script_path.exists():
    env = dict(os.environ)
    env["GH_TOKEN"] = ""
    p = subprocess.run([BASH, str(script_path)], cwd=str(ROOT), capture_output=True,
                       text=True, encoding="utf-8", env=env, timeout=60)
    out = p.stdout + p.stderr
    check("an empty GH_TOKEN fails the lane (non-zero)", p.returncode != 0, f"rc={p.returncode}\n{out}")
    check("and says the token is missing", "GH_TOKEN" in out and "empty" in out.lower(), out)
    check("and prints no `match` line", not re.search(r"^\s*match\b", out, re.M), out)
else:
    check("ci/scripts/protection-drift.sh exists", False)

manifest = (ROOT / "test" / "manifest.txt").read_text(encoding="utf-8")
for t in ("test/protection-drift.test.py", "test/protection-drift-wiring.test.py"):
    check(f"test/manifest.txt runs {t} in the lint stage",
          re.search(rf"^{re.escape(t)}\s+lint\b", manifest, re.M) is not None)

print()
if failures:
    print(f"{len(failures)} FAILED")
    sys.exit(1)
print("all passed")
