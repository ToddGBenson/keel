#!/usr/bin/env python3
"""
Every step of this pipeline runs on a `linux`-tagged worker. Refs: TheHub #61830

The pipeline was untagged, so every check, get and task could only land on the
Windows host's untagged worker, which was the one at 120 containers while the
Linux workers sat at 0. Nothing in this pipeline needs that host: MyKronos is
reached at its public URL, and no step names host.docker.internal, the LAN, a
local registry or Vault. So every resource (its checks), every get and put, and
every task (hooks and anchors included) carries `tags: [linux]`. set_pipeline
runs on the web node and takes no tags.

A step added without the tag would land on no worker at all on a deployment
with only tagged Linux workers, or back on the host's; either way this fails.

Needs PyYAML (ci/requirements.txt).

    python test/worker-tags.test.py
"""
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
PIPELINE = ROOT / "ci" / "pipeline.yml"
TAG = ["linux"]
failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def steps(node, path, out):
    if isinstance(node, dict):
        kind = next((k for k in ("task", "get", "put") if k in node), None)
        if kind:
            out.append((f"{path}:{kind} {node[kind]}", node.get("tags")))
        for k, v in node.items():
            steps(v, f"{path}/{k}", out)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            steps(v, f"{path}[{i}]", out)
    return out


def untagged(doc):
    bad = [f"resource {r['name']}" for r in doc.get("resources") or [] if r.get("tags") != TAG]
    for job in doc.get("jobs") or []:
        bad += [where for where, tags in steps(job, job["name"], []) if tags != TAG]
    return bad


def main():
    doc = yaml.safe_load(PIPELINE.read_text(encoding="utf-8"))
    found = steps(doc.get("jobs") or [], "jobs", [])
    check(f"the walk finds the pipeline's steps ({len(found)})", len(found) >= 50, str(len(found)))
    bad = untagged(doc)
    check("every resource, get, put and task step is tagged linux", not bad, f"{len(bad)}: {bad[:8]}")
    check("the check can fail: an untagged task is caught",
          untagged({"resources": [], "jobs": [{"name": "j", "plan": [{"task": "t"}]}]}) == ["j/plan[0]:task t"])
    check("the check can fail: an untagged resource is caught",
          untagged({"resources": [{"name": "r", "type": "time"}], "jobs": []}) == ["resource r"])
    if failures:
        print(f"\n{len(failures)} failure(s)")
        return 1
    print("\nall checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
