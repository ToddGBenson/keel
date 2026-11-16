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
import re
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
# build-and-attest gathers every verifying lane (TheHub #60850): the scanners are
# in the verdict, and full-suite (an ADAPT stub) is gone from it.
CHAIN = ["build", "lint", "test", "sast", "secrets", "sca", "iac",
         "build-and-attest", "verify-artifact"]
FIRST, LAST = "build", "verify-artifact"
# [TheHub #61778] The one reporter outside the commit chain: it judges pull request
# heads and reports on the head it checked out (pr/), never on main's commit.
PR_JOB = "pr-checks"
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


# [TheHub #61778 review #1] Artifacts that hold pull-request code. A task's `run:`
# path names an INPUT, so a credentialed step given one of these as any input (by
# input_mapping, or because its task file declares it) can run the pull request's
# script with the credential. pr-sha holds only a sha, written by pr-pick.sh.
PR_CODE = {"pr"}
CREDENTIAL = re.compile(r"TOKEN|KEY|SECRET|PASSWORD", re.I)


def task_steps_everywhere(node, out):
    if isinstance(node, dict):
        if "task" in node and "file" in node:
            out.append(node)
        for v in node.values():
            task_steps_everywhere(v, out)
    elif isinstance(node, list):
        for v in node:
            task_steps_everywhere(v, out)
    return out


def credential_steps_never_see_pr_code(doc):
    bad = []
    for step in task_steps_everywhere(doc["jobs"], []):
        creds = [k for k in (step.get("params") or {}) if CREDENTIAL.search(k)]
        if not creds:
            continue
        mapped = set((step.get("input_mapping") or {}).values()) & PR_CODE
        task_file = ROOT / str(step["file"]).replace("repo/", "", 1)
        declared = set()
        if task_file.is_file():
            declared = {i["name"] for i in (yaml.safe_load(task_file.read_text()) or {}).get("inputs") or []}
        if mapped or (declared & PR_CODE) or not str(step["file"]).startswith("repo/"):
            bad.append(f"{step['task']} ({', '.join(creds)}): "
                       f"maps {sorted(mapped)}, declares {sorted(declared & PR_CODE)}, file {step['file']}")
    check("no step holding a credential takes pull-request code as an input, or a task "
          "file from anywhere but main's repo/", not bad, bad)


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
        if name not in CHAIN and name != PR_JOB:
            check(f"{name} is outside the verdict and does not report", not reporters(job))

    pr = jobs.get(PR_JOB) or {}
    for hook, conclusion in (("on_success", "success"), ("on_failure", "failure"),
                             ("on_error", "failure")):
        h = pr.get(hook) or {}
        p = h.get("params") or {}
        check(f"{PR_JOB}.{hook} reports {conclusion} on the pull request head",
              h.get("task") == "check-run"
              and (p.get("JOB"), p.get("PHASE"), p.get("CONCLUSION")) == (PR_JOB, "end", conclusion)
              and p.get("HEAD_FILE") == "pr-sha/HEAD" and not h.get("input_mapping")
              and p.get("NO_COMMIT_OK") == "1", h)
    check(f"{PR_JOB} reports nothing from its plan (pr-pick posts the start)",
          not reporters(pr.get("plan") or []))
    check(f"{PR_JOB} never runs two at once", pr.get("serial") is True)
    pr_tasks = {s.get("task"): s for s in pr.get("plan") or [] if "task" in s}
    check(f"{PR_JOB}: the task that runs pull-request code gets no params",
          "pr-checks" in pr_tasks and not pr_tasks["pr-checks"].get("params"), pr_tasks.get("pr-checks"))
    for name, job in jobs.items():
        for step in reporters(job):
            if (step.get("params") or {}).get("NO_COMMIT_OK") and name != PR_JOB:
                check(f"only {PR_JOB} may report with no commit ({name} does)", False)

    credential_steps_never_see_pr_code(doc)

    every = reporters(doc["jobs"])
    expected = len(CHAIN) * 2 + 2 + 3
    check(f"{len(CHAIN)} jobs x 2 hooks, one start, one success", len(every) == expected, len(every))
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
        if params.get("PR_SHA"):
            (tmp / "pr-sha").mkdir()
            (tmp / "pr-sha" / "HEAD").write_text(params["PR_SHA"] + "\n", encoding="utf-8")
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

    # [TheHub #61778] pr-checks: no head was picked, so there is nothing to report.
    for head in (None, "ref: refs/heads/master"):
        r, body, _ = run(head, JOB="pr-checks", PHASE="end", CONCLUSION="success", NO_COMMIT_OK="1")
        check(f"NO_COMMIT_OK=1 with no commit ({head!r}) posts nothing and passes",
              r.returncode == 0 and body is None, r.stdout + r.stderr)
    r, body, _ = run(SHA, JOB="pr-checks", PHASE="end", CONCLUSION="failure", NO_COMMIT_OK="1")
    check("NO_COMMIT_OK=1 with a commit still reports it", r.returncode == 0 and body
          and (body["commit_sha"], body["conclusion"]) == (SHA, "failure"))

    # [TheHub #61778 review #1] pr-checks names the head's sha in a file of its own,
    # and repo/ stays main's checkout.
    r, body, _ = run("ref: refs/heads/main", JOB="pr-checks", PHASE="end", CONCLUSION="success",
                     NO_COMMIT_OK="1", HEAD_FILE="pr-sha/HEAD", PR_SHA=SHA)
    check("HEAD_FILE: the sha is read from that file, not repo/.git/HEAD",
          r.returncode == 0 and body and body["commit_sha"] == SHA, r.stdout + r.stderr)


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
