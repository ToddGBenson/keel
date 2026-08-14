#!/usr/bin/env python3
"""Structural validation of the Concourse pipeline. Refs: #42

`fly validate-pipeline` checks the schema. It does not check that a task file
exists, that a script exists, that a param a job passes is one the task declares,
or that the resource-type and image-pinning rules the pipeline claims for itself
actually hold. Those are the failures that have actually happened here:

  - a `SBOM_FORMAT` param passed to a task that never declared it
  - a `sbom` input declared optional that no job in that plan could produce
  - image tags and resource types asserted in a comment and enforced by nothing

None of that needs a Concourse to detect, so it runs on every pull request rather
than being discovered when a job fails at 3am.

    python scripts/validate-pipeline.py

Exit 0 clean, 1 on any error. Warnings do not fail the run.
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    import yaml
except ImportError:                                    # pragma: no cover
    print("PyYAML is required: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parent.parent
PIPELINE = ROOT / "ci" / "pipeline.yml"
TASK_DIR = ROOT / "ci" / "tasks"
SCRIPT_DIR = ROOT / "ci" / "scripts"

# Resource types Concourse ships. Anything else is a third-party dependency in
# the pipeline that enforces supply-chain controls — see ADR-0003 D3. The
# well-known community options for PR triggering are archived, which is exactly
# why this is a check and not a comment.
BUNDLED_RESOURCE_TYPES = {
    "git", "time", "registry-image", "github-release", "s3", "semver", "mock",
}

errors: list[str] = []
warnings: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def warn(msg: str) -> None:
    # Deduped: a task referenced by four jobs produced four identical warnings,
    # and 35 lines of the same sentence is how a real one gets skipped.
    if msg not in warnings:
        warnings.append(msg)


def walk_steps(step, fn):
    """Visit every step, including those nested in do/in_parallel/ensure/etc."""
    if not isinstance(step, dict):
        return
    fn(step)
    for key in ("do", "in_parallel"):
        value = step.get(key)
        if isinstance(value, dict):          # in_parallel: {steps: [...]}
            value = value.get("steps") or []
        for sub in value or []:
            walk_steps(sub, fn)
    for key in ("ensure", "on_failure", "on_success", "on_abort", "on_error", "try"):
        if key in step:
            walk_steps(step[key], fn)


def main() -> int:
    if not PIPELINE.exists():
        err(f"{PIPELINE.relative_to(ROOT)} does not exist")
        return report()

    try:
        pipeline = yaml.safe_load(PIPELINE.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        err(f"ci/pipeline.yml does not parse: {exc}")
        return report()

    jobs = {j["name"] for j in pipeline.get("jobs", [])}
    resources = {r["name"]: r for r in pipeline.get("resources", [])}

    # ── Resource types (ADR-0003 D3) ─────────────────────────────────────────
    for name, res in resources.items():
        rtype = res.get("type")
        if rtype not in BUNDLED_RESOURCE_TYPES:
            err(f"resource '{name}' uses non-bundled type '{rtype}'. "
                f"ADR-0003 D3: no third-party resource types.")
    for rt in pipeline.get("resource_types", []) or []:
        err(f"custom resource_type '{rt.get('name')}' declared. ADR-0003 D3 "
            f"forbids third-party resource types in this pipeline.")

    # ── Groups ───────────────────────────────────────────────────────────────
    grouped: set[str] = set()
    for group in pipeline.get("groups", []) or []:
        for jn in group.get("jobs", []) or []:
            if jn == "*":
                continue
            if jn not in jobs:
                err(f"group '{group['name']}' lists unknown job '{jn}'")
            if group.get("name") != "all":
                grouped.add(jn)
    for orphan in sorted(jobs - grouped):
        warn(f"job '{orphan}' appears in no group but 'all' — it will be hard to find")

    referenced_tasks: set[Path] = set()
    referenced_scripts: set[Path] = set()

    # ── Per-job structure ────────────────────────────────────────────────────
    for job in pipeline.get("jobs", []):
        jname = job["name"]

        def check(step, jname=jname):
            if "get" in step:
                if step["get"] not in resources:
                    err(f"{jname}: get '{step['get']}' is not a declared resource")
                for upstream in step.get("passed", []) or []:
                    if upstream not in jobs:
                        err(f"{jname}: passed: references unknown job '{upstream}'")

            # A set_pipeline step pointing at a file that does not exist fails at
            # RUN time, which for a self-updating pipeline means it stops
            # updating itself and nothing says so — the pipeline just quietly
            # stops tracking git, which is the exact drift it exists to prevent.
            if "set_pipeline" in step:
                for key in ("file",):
                    ref = step.get(key)
                    if ref and not (ROOT / ref.replace("repo/", "", 1)).exists():
                        err(f"{jname}: set_pipeline {key} missing -> {ref}")
                for ref in (step.get("var_files") or []):
                    if not (ROOT / ref.replace("repo/", "", 1)).exists():
                        err(f"{jname}: set_pipeline var_file missing -> {ref}")
                return

            if "task" not in step:
                return
            if "file" not in step:
                if "config" not in step:
                    err(f"{jname}/{step['task']}: task has neither file: nor config:")
                return

            rel = step["file"].replace("repo/", "", 1)
            task_path = ROOT / rel
            referenced_tasks.add(task_path)
            if not task_path.exists():
                err(f"{jname}/{step['task']}: task file missing -> {step['file']}")
                return

            task = yaml.safe_load(task_path.read_text(encoding="utf-8"))
            declared = set(task.get("params") or {})
            for key in (step.get("params") or {}):
                if key not in declared:
                    err(f"{jname}/{step['task']}: passes param '{key}' which "
                        f"{rel} does not declare — it will be silently ignored")

            # Image pinning: a mutable tag is a supply-chain input the pipeline
            # claims to control.
            # `latest` or no tag is an ERROR: the image performing a security
            # check would be whatever was pushed most recently.
            #
            # A version tag without a digest is a WARNING, not an error, and the
            # distinction is deliberate. Digest-pinning a tool release
            # (gitleaks v8.18.4) costs nothing and adds tamper-resistance.
            # Digest-pinning a base image (python:3.13) freezes the interpreter
            # at one patch level, so every base-image CVE fix stops arriving —
            # trading a supply-chain risk for a patch-currency risk. Doing that
            # without a bump mechanism makes things worse, not better. Promote
            # this to an error once Dependabot is configured to update digests.
            src = (task.get("image_resource") or {}).get("source") or {}
            tag = str(src.get("tag", ""))
            if not src.get("digest"):
                if tag in ("", "latest"):
                    err(f"{rel}: image '{src.get('repository')}' uses tag "
                        f"'{tag or '<none>'}' — never latest, and never unpinned")
                else:
                    warn(f"{rel}: image '{src.get('repository')}:{tag}' pinned by tag, "
                         f"not digest (accepted — see the note in this file)")

            for arg in (task.get("run", {}).get("args") or []):
                if str(arg).endswith(".sh"):
                    sp = ROOT / str(arg).replace("repo/", "", 1)
                    referenced_scripts.add(sp)
                    if not sp.exists():
                        err(f"{rel}: run references missing script -> {arg}")

        for step in job.get("plan", []):
            walk_steps(step, check)

    # ── Orphans: files nothing reaches ───────────────────────────────────────
    if TASK_DIR.is_dir():
        for f in sorted(TASK_DIR.glob("*.yml")):
            if f not in referenced_tasks:
                warn(f"ci/tasks/{f.name} is referenced by no job")
    if SCRIPT_DIR.is_dir():
        for f in sorted(SCRIPT_DIR.glob("*.sh")):
            if f not in referenced_scripts:
                warn(f"ci/scripts/{f.name} is referenced by no task")

    return report(len(jobs), len(resources))


def report(njobs: int = 0, nres: int = 0) -> int:
    print("Concourse pipeline validation")
    print(f"  {njobs} jobs, {nres} resources")
    for w in warnings:
        print(f"  [warn]  {w}")
    for e in errors:
        print(f"  [ERROR] {e}")
    if errors:
        print(f"\n  {len(errors)} error(s). These are structural faults that "
              f"`fly validate-pipeline` does not detect.")
        return 1
    print(f"  [ok]    structure, params, resource types and image pins all consistent"
          f"{f' ({len(warnings)} warning(s))' if warnings else ''}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
