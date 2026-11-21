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


def unwrapped(step):
    """A step, or the step a `try:` wraps (TheHub #62097: the success reports are wrapped)."""
    return step["try"] if isinstance(step, dict) and "try" in step else step


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
# input_mapping, or because its task config declares it) can run the pull request's
# script with the credential. pr-sha holds only a sha, written by pr-pick.sh.
PR_CODE = {"pr"}
CREDENTIAL_NAME = re.compile(r"TOKEN|KEY|SECRET|PASSWORD", re.I)


def task_steps_everywhere(node, out):
    """Every task step in plans and hooks, whether it loads `file:` or inlines `config:`."""
    if isinstance(node, dict):
        if "task" in node and ("file" in node or "config" in node):
            out.append(node)
        for v in node.values():
            task_steps_everywhere(v, out)
    elif isinstance(node, list):
        for v in node:
            task_steps_everywhere(v, out)
    return out


def credentials(step):
    """Params that hold a credential: by name, or (review nit a) by a `((var))` value."""
    return sorted(k for k, v in (step.get("params") or {}).items()
                  if CREDENTIAL_NAME.search(k) or "((" in str(v))


def task_config(step, load):
    """The step's task config: inline `config:`, or the `file:` loaded from main's repo/."""
    if "config" in step:
        return step.get("config") or {}
    return load(str(step["file"])) or {}


def pr_code_findings(doc, load):
    """Every way a pipeline lets pull-request code near a credential. [] is clean."""
    bad = []
    for step in task_steps_everywhere(doc["jobs"], []):
        cfg = task_config(step, load)
        declared = {i["name"] for i in cfg.get("inputs") or []}
        mapped = set((step.get("input_mapping") or {}).values())
        sees_pr = (mapped | (declared - set(step.get("input_mapping") or {}))) & PR_CODE
        creds = credentials(step)
        where = step.get("file", "inline config")
        if creds and sees_pr:
            bad.append(f"{step['task']} holds {creds} and takes pull-request code {sorted(sees_pr)} ({where})")
        if creds and "file" in step and not str(step["file"]).startswith("repo/"):
            bad.append(f"{step['task']} holds {creds} and loads its task file from {step['file']}, not main's repo/")
        # Review nit c: the task that runs pull-request code must not be able to write an
        # artifact a later (credentialed) step reads in place of pr-pick's.
        if sees_pr and (cfg.get("outputs") or step.get("output_mapping")):
            bad.append(f"{step['task']} runs pull-request code and declares outputs "
                       f"{[o.get('name') for o in cfg.get('outputs') or []]} / output_mapping "
                       f"{step.get('output_mapping')}")
    return bad


def load_from_root(rel):
    path = ROOT / rel.replace("repo/", "", 1)
    return yaml.safe_load(path.read_text(encoding="utf-8")) if path.is_file() else None


def credential_steps_never_see_pr_code(doc):
    bad = pr_code_findings(doc, load_from_root)
    check("no step holding a credential takes pull-request code as an input or loads a task "
          "file from outside main's repo/, and the task running pull-request code writes no "
          "outputs", not bad, bad)

    # The rule must be able to fail: one deliberately bad pipeline per shape.
    clean_cfg = {"inputs": [{"name": "repo"}, {"name": "pr"}], "run": {"path": "true"}}
    files = {"repo/ci/tasks/x.yml": {"inputs": [{"name": "repo"}], "run": {"path": "repo/x.sh"}},
             "repo/ci/tasks/runs-pr.yml": clean_cfg,
             "repo/ci/tasks/runs-pr-out.yml": {**clean_cfg, "outputs": [{"name": "pr-sha"}]}}
    load = files.get
    def job(*steps):
        return {"jobs": [{"name": "j", "plan": list(steps)}]}
    fixtures = {
        "a credential by name, with the pull request mapped over repo": job(
            {"task": "t", "file": "repo/ci/tasks/x.yml", "input_mapping": {"repo": "pr"},
             "params": {"MY_TOKEN": "x"}}),
        "a credential only by its ((var)) value (nit a)": job(
            {"task": "t", "file": "repo/ci/tasks/x.yml", "input_mapping": {"repo": "pr"},
             "params": {"WHATEVER": "((github_protection_token))"}}),
        "an inline config that declares pr, with a credential (nit b)": job(
            {"task": "t", "config": {"inputs": [{"name": "pr"}], "run": {"path": "pr/x.sh"}},
             "params": {"T": "((mykronos_ingestion_token))"}}),
        "a credentialed task file loaded from pull-request code": job(
            {"task": "t", "file": "pr/ci/tasks/x.yml", "params": {"MY_TOKEN": "x"}}),
        "the pull-request task declaring an output (nit c)": job(
            {"task": "t", "file": "repo/ci/tasks/runs-pr-out.yml"}),
        "the pull-request task with an output_mapping (nit c)": job(
            {"task": "t", "file": "repo/ci/tasks/runs-pr.yml", "output_mapping": {"pr-sha": "pr"}}),
    }
    for name, bad_doc in fixtures.items():
        check(f"the rule catches {name}", bool(pr_code_findings(bad_doc, load)),
              "(the deliberately bad fixture passed)")
    check("and passes a pull-request task with no credential and no outputs",
          not pr_code_findings(job({"task": "t", "file": "repo/ci/tasks/runs-pr.yml"}), load))


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

    last_step = jobs[LAST]["plan"][-1]
    last = unwrapped(last_step)
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
        h = unwrapped(pr.get(hook) or {})
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

    # [TheHub #62097] A report that cannot get through must not reach the job's own
    # failure hook, which would post `failure` for a suite that passed. Concourse runs
    # `on_failure` when the last plan step (or an `on_success` hook) fails, so the two
    # success reports are wrapped in `try:`; the step still shows red in the build.
    check("verify-artifact's success report is wrapped in try, so its failure is not the job's",
          "try" in last_step and last_step["try"].get("task") == "check-run", last_step)
    check(f"{PR_JOB}'s on_success report is wrapped in try", "try" in (pr.get("on_success") or {}),
          pr.get("on_success"))
    wrapped = [(j, h) for j, job in jobs.items() for h in ("on_failure", "on_error")
               if "try" in (job.get(h) or {})]
    check("no failure report is wrapped in try: a real failure's unreachable post stays red",
          not wrapped, wrapped)
    loose = [name for name, job in jobs.items()
             for step in job.get("plan") or [] if step.get("task") == "check-run"
             and (step.get("params") or {}).get("CONCLUSION") == "success"]
    check("no success report is left unwrapped in a plan", not loose, loose)

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


CURL_STUB = r"""#!/bin/sh
n=$(cat "$CAPTURE_DIR/n" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" > "$CAPTURE_DIR/n"
printf '%s\n' "$@" > "$CAPTURE_ARGS"
while [ $# -gt 0 ]; do
  case "$1" in -d|--data) printf '%s' "$2" > "$CAPTURE"; printf '%s\n' "$2" >> "$CAPTURE_DIR/bodies" ;; esac
  shift
done
# CURL_RCS is the exit code of each call in turn; CURL_RC answers every call after.
rc="${CURL_RC:-0}"
i=0
for r in ${CURL_RCS:-}; do
  i=$((i + 1))
  [ "$i" -eq "$n" ] && rc="$r"
done
# What `-w '\n%{http_code}'` adds, for a refusal that carries a status.
if [ "$rc" -ne 0 ] && [ -n "${CURL_CODE:-}" ]; then printf '\n%s' "$CURL_CODE"; fi
exit "$rc"
"""

# Backoff must not make the test slow: record the delay, do not wait it out.
SLEEP_STUB = r"""#!/bin/sh
printf '%s\n' "$1" >> "$CAPTURE_DIR/sleeps"
exit 0
"""


def run(head, **params):
    r, bodies, args, _ = run_full(head, **params)
    return r, (bodies[-1] if bodies else None), args


def run_full(head, **params):
    """Run the script once. Returns (result, every body sent, last curl args, sleeps)."""
    sh = shutil.which("sh")
    if not sh:
        print("sh is required to execute ci/scripts/check-run.sh")
        sys.exit(1)
    tmp = Path(tempfile.mkdtemp(prefix="check-run-"))
    try:
        stubs = tmp / "stubs"
        stubs.mkdir()
        for name, text in (("curl", CURL_STUB), ("sleep", SLEEP_STUB)):
            stub = stubs / name
            stub.write_text(text, encoding="utf-8", newline="\n")
            stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
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
            "CAPTURE_DIR": str(tmp),
            "CAPTURE": str(tmp / "body.json"),
            "CAPTURE_ARGS": str(tmp / "args.txt"),
            "MYKRONOS_INGESTION_URL": "http://mykronos.test",
            "MYKRONOS_INGESTION_TOKEN": "tok",
            "REPO_SLUG": "ToddGBenson/keel",
            **params,
        }
        r = subprocess.run([sh, str(SCRIPT)], env=env, cwd=tmp,
                           capture_output=True, text=True, timeout=30)
        bodies = ([json.loads(line) for line in (tmp / "bodies").read_text().splitlines() if line]
                  if (tmp / "bodies").exists() else [])
        args = (tmp / "args.txt").read_text().split("\n") if (tmp / "args.txt").exists() else []
        sleeps = ([int(x) for x in (tmp / "sleeps").read_text().split()]
                  if (tmp / "sleeps").exists() else [])
        return r, bodies, args, sleeps
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


def unreachable_reporter_checks():
    """[TheHub #62097] binnacle #89 passed every unit suite, then check-run.sh got curl
    exit 6 three times; the failure path then posted `failure` and a passing head was
    recorded red. These run the script with curl stubbed to exit 6 (and the others)."""
    print("-- an unreachable reporter (TheHub #62097) --")
    TRANSIENT = (6, 7, 28, 35, 52, 56)
    ok = dict(JOB="verify-artifact", PHASE="end", CONCLUSION="success")

    # a. every try unreachable, after a passing suite.
    r, bodies, _, sleeps = run_full(SHA, CURL_RC="6", **ok)
    concl = [b["conclusion"] for b in bodies]
    check("a passing suite's report retries 5 times on curl exit 6", concl[:5] == ["success"] * 5, concl)
    check("the retries back off over about two minutes",
          len(sleeps) == 4 and sleeps == sorted(sleeps) and len(set(sleeps)) == 4
          and 90 <= sum(sleeps) <= 150, sleeps)
    check("an unreachable reporter after a passing suite never posts failure",
          "failure" not in concl, concl)
    check("it exits non-zero so Concourse shows the error", r.returncode != 0, r.returncode)
    check("and says the reporter was unreachable and the suite passed",
          "reporter unreachable; suite passed" in r.stdout + r.stderr, r.stdout + r.stderr)

    # b. the one `cancelled` post, when a post gets through at the end.
    r, bodies, _, _ = run_full(SHA, CURL_RCS="6 6 6 6 6 0", **ok)
    concl = [b["conclusion"] for b in bodies]
    check("if a post then gets through it is cancelled, never failure",
          concl == ["success"] * 5 + ["cancelled"], concl)
    check("and the step still exits non-zero", r.returncode != 0)

    # c. transient exits are retried until one goes through.
    r, bodies, _, sleeps = run_full(SHA, CURL_RCS="6 6 0", **ok)
    check("a report that gets through on the third try exits 0 after 3 posts",
          r.returncode == 0 and len(bodies) == 3 and len(sleeps) == 2, (r.returncode, len(bodies), sleeps))
    for rc in TRANSIENT:
        r, bodies, _, _ = run_full(SHA, CURL_RCS=f"{rc} 0", **ok)
        check(f"curl exit {rc} is retried", r.returncode == 0 and len(bodies) == 2, (r.returncode, len(bodies)))

    # d. a refusal is an answer, not an outage: no retry, no cancelled.
    r, bodies, _, sleeps = run_full(SHA, CURL_RC="22", CURL_CODE="422", **ok)
    check("a 4xx refusal is not retried and is not turned into a cancelled",
          r.returncode != 0 and len(bodies) == 1 and not sleeps, (len(bodies), sleeps))
    r, bodies, _, _ = run_full(SHA, CURL_RCS="22 0", CURL_CODE="503", **ok)
    check("a 503 is retried", r.returncode == 0 and len(bodies) == 2, len(bodies))
    r, bodies, _, _ = run_full(SHA, CURL_RC="28", JOB="test", PHASE="end", CONCLUSION="success")
    check("a timeout (28) on a success report is retried like the rest", len(bodies) >= 5, len(bodies))

    # e. a suite that really failed still posts failure, and stays red if unreachable.
    r, bodies, _, _ = run_full(SHA, CURL_RC="6", JOB="test", PHASE="end", CONCLUSION="failure")
    concl = [b["conclusion"] for b in bodies]
    check("a real failure's report is retried 5 times and only ever says failure",
          concl == ["failure"] * 5, concl)
    check("and when it never gets through the step exits non-zero, so the build stays red",
          r.returncode != 0)
    r, bodies, _, _ = run_full(SHA, CURL_RCS="6 0", JOB="test", PHASE="end", CONCLUSION="failure")
    check("a real failure is posted as failure once a try gets through",
          r.returncode == 0 and [b["conclusion"] for b in bodies] == ["failure", "failure"])

    # f. a start that cannot get through fails the step, with no conclusion invented.
    r, bodies, _, _ = run_full(SHA, CURL_RC="6", JOB="build", PHASE="start")
    check("an unreachable start retries and exits non-zero without a conclusion",
          r.returncode != 0 and len(bodies) == 5 and all(b["conclusion"] is None for b in bodies))


def main():
    pipeline_checks()
    script_checks()
    unreachable_reporter_checks()
    print()
    if failures:
        print(f"{len(failures)} failed")
        return 1
    print("all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
