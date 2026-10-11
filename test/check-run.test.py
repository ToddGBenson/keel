#!/usr/bin/env python3
"""
Tests for the `Concourse / keel` check-run wiring. Refs: #107

Two halves, both against the real files rather than a re-implementation:

  * ci/pipeline.yml: `build` reports the start before it builds, `verify-artifact`
    reports success as its last step, every job in the commit chain reports
    failure from `on_failure:` and `on_error:`, nothing outside the chain reports,
    and nothing retries the report;
  * ci/scripts/check-run.sh, EXECUTED under sh with curl stubbed on PATH: the body
    it sends, that a refused report fails the step, and that it refuses to report
    when there is no full sha to name.

Needs PyYAML (ci/requirements.txt) and `sh`.

    python test/check-run.test.py
"""
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
PIPELINE = ROOT / "ci" / "pipeline.yml"
SCRIPT = ROOT / "ci" / "scripts" / "check-run.sh"
TASK_FILE = "repo/ci/tasks/check-run.yml"
CHAIN = ["build", "lint", "test", "full-suite", "build-and-attest", "verify-artifact"]
FIRST, LAST = "build", "verify-artifact"
SHA = "0123456789abcdef0123456789abcdef01234567"
failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def reporters(node):
    found = []

    def walk(n):
        if isinstance(n, dict):
            if n.get("task") == "check-run":
                found.append(n)
            for v in n.values():
                walk(v)
        elif isinstance(n, list):
            for v in n:
                walk(v)

    walk(node)
    return found


def upstream_of(jobs, target):
    seen, pending = set(), [target]
    while pending:
        for step in jobs[pending.pop()]["plan"]:
            for up in step.get("passed") or []:
                if up not in seen:
                    seen.add(up)
                    pending.append(up)
    return seen


def pipeline_checks():
    print("-- ci/pipeline.yml --")
    doc = yaml.safe_load(PIPELINE.read_text(encoding="utf-8"))
    jobs = {j["name"]: j for j in doc["jobs"]}

    check("verify-artifact waits on the whole chain",
          upstream_of(jobs, LAST) == set(CHAIN) - {LAST}, sorted(upstream_of(jobs, LAST)))

    plan = jobs[FIRST]["plan"]
    names = [s.get("task") for s in plan]
    start = plan[names.index("check-run")] if "check-run" in names else {}
    check("build reports the start before it builds",
          "check-run" in names and names.index("check-run") < names.index("build"))
    check("the start carries no conclusion",
          start.get("params", {}).get("PHASE") == "start"
          and "CONCLUSION" not in start.get("params", {}))

    last = jobs[LAST]["plan"][-1]
    check("verify-artifact reports success as its last step",
          last.get("task") == "check-run"
          and (last["params"].get("JOB"), last["params"].get("PHASE"),
               last["params"].get("CONCLUSION")) == (LAST, "end", "success"), last)

    for job in CHAIN:
        for hook in ("on_failure", "on_error"):
            h = jobs[job].get(hook) or {}
            p = h.get("params") or {}
            check(f"{job}.{hook} reports failure",
                  h.get("task") == "check-run"
                  and (p.get("JOB"), p.get("PHASE"), p.get("CONCLUSION")) == (job, "end", "failure"),
                  h)

    for name, job in jobs.items():
        if name not in CHAIN:
            check(f"{name} is outside the verdict and does not report", not reporters(job))

    every = reporters(doc["jobs"])
    check("6 jobs x 2 hooks, one start, one success", len(every) == 14, len(every))
    for step in every:
        p = step.get("params") or {}
        ok = (step.get("file") == TASK_FILE and "attempts" not in step and step.get("timeout")
              and p.get("MYKRONOS_INGESTION_TOKEN") == "((mykronos_ingestion_token))"
              and p.get("REPO_SLUG") == "((github_owner))/((github_repo))")
        if not ok:
            check("every report: the task file, a timeout, no attempts, the ingestion token",
                  False, step)
            break
    else:
        check("every report: the task file, a timeout, no attempts, the ingestion token", True)

    script = SCRIPT.read_text(encoding="utf-8")
    check("the script never calls GitHub", "api.github.com" not in script)


CURL_STUB = """#!/bin/sh
printf '%s\\n' "$@" > "$CAPTURE_ARGS"
while [ $# -gt 0 ]; do
  case "$1" in -d|--data) printf '%s' "$2" > "$CAPTURE" ;; esac
  shift
done
exit "${CURL_RC:-0}"
"""


def run(head, **params):
    sh = shutil.which("sh")
    if not sh:
        print("sh is required to execute ci/scripts/check-run.sh")
        sys.exit(1)
    tmp = Path(tempfile.mkdtemp(prefix="check-run-"))
    try:
        stubs = tmp / "stubs"
        stubs.mkdir()
        curl = stubs / "curl"
        curl.write_text(CURL_STUB, encoding="utf-8", newline="\n")
        curl.chmod(curl.stat().st_mode | stat.S_IEXEC)
        (tmp / "repo").mkdir()
        if head is not None:
            (tmp / "repo" / ".git").mkdir()
            (tmp / "repo" / ".git" / "HEAD").write_text(head + "\n", encoding="utf-8")
        env = {
            **os.environ,
            "PATH": f"{stubs}{os.pathsep}{os.environ.get('PATH', '')}",
            "CAPTURE": str(tmp / "body.json"),
            "CAPTURE_ARGS": str(tmp / "args.txt"),
            "MYKRONOS_INGESTION_URL": "http://mykronos.test",
            "MYKRONOS_INGESTION_TOKEN": "tok",
            "REPO_SLUG": "ToddGBenson/keel",
            **params,
        }
        r = subprocess.run([sh, str(SCRIPT)], env=env, cwd=tmp,
                           capture_output=True, text=True, timeout=30)
        body = json.loads((tmp / "body.json").read_text()) if (tmp / "body.json").exists() else None
        args = (tmp / "args.txt").read_text().split("\n") if (tmp / "args.txt").exists() else []
        return r, body, args
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def script_checks():
    print("-- ci/scripts/check-run.sh --")
    r, body, args = run(SHA, JOB="build", PHASE="start")
    check("a start exits 0", r.returncode == 0, r.stdout + r.stderr)
    check("a start sends the commit and no conclusion", body == {
        "repo_full_name": "ToddGBenson/keel", "commit_sha": SHA,
        "job": "build", "phase": "start", "conclusion": None}, body)
    check("it posts to /api/ingest/check-runs with --fail-with-body",
          "--fail-with-body" in args and "http://mykronos.test/api/ingest/check-runs" in args)
    check("the token goes in the Authorization header", "Authorization: Bearer tok" in args)

    r, body, _ = run(SHA, JOB="verify-artifact", PHASE="end", CONCLUSION="success")
    check("a success sends the conclusion", r.returncode == 0 and body
          and (body["job"], body["phase"], body["conclusion"]) == ("verify-artifact", "end", "success"))

    r, body, _ = run(SHA, JOB="test", PHASE="end", CONCLUSION="failure")
    check("a failure sends the conclusion", r.returncode == 0 and body
          and body["conclusion"] == "failure")

    r, _, _ = run(SHA, JOB="build", PHASE="start", CURL_RC="22")
    check("a refused report fails the step", r.returncode != 0)

    r, body, _ = run(SHA, JOB="test", PHASE="end")
    check("an end with no conclusion is refused before it sends", r.returncode != 0 and body is None)

    for head in (None, "ref: refs/heads/main", "abc1234"):
        r, body, _ = run(head, JOB="test", PHASE="end", CONCLUSION="failure")
        check(f"no full sha ({head!r}) fails rather than guessing",
              r.returncode != 0 and body is None)


def main():
    pipeline_checks()
    script_checks()
    print()
    if failures:
        print(f"{len(failures)} failed")
        return 1
    print("all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
