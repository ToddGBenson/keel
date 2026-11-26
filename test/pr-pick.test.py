#!/usr/bin/env python3
"""
Tests for pull request head checks: ci/scripts/pr-pick.sh and ci/scripts/pr-checks.sh,
EXECUTED against a real local git repository standing in for GitHub. Refs: TheHub #61778

The origin has branches and `refs/pull/N/head` / `refs/pull/N/merge` refs the way
GitHub keeps them (a merge ref only while the pull request is open). curl is stubbed:
it records each start it is sent and answers it from a per-sha table, the way MyKronos
answers `/api/ingest/check-runs`.

Needs git and bash.

    python test/pr-pick.test.py
"""
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PICK = ROOT / "ci" / "scripts" / "pr-pick.sh"
CHECKS = ROOT / "ci" / "scripts" / "pr-checks.sh"
failures = []

CURL_STUB = r"""#!/usr/bin/env bash
body=""; prev=""
for a in "$@"; do [ "$prev" = "-d" ] && body="$a"; prev="$a"; done
printf '%s\n' "$body" >> "$CAPTURE"
sha=$(printf '%s' "$body" | sed -nE 's/.*"commit_sha":"([0-9a-f]+)".*/\1/p')
ans="$ANSWERS/$sha"
[ -f "$ans" ] && cat "$ans" || printf '{"name":"Concourse / keel","check_run_id":1,"status":"in_progress","conclusion":null,"outcome":"created"}'
exit "${CURL_RC:-0}"
"""


def rmtree(path, ignore_errors=False):
    """shutil.rmtree that also removes git's read-only object files (Windows)."""
    def force(func, p, _exc):
        try:
            os.chmod(p, stat.S_IWRITE)
            func(p)
        except OSError:
            pass
    shutil.rmtree(path, onerror=force if ignore_errors else None)


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def git(*args, cwd, env=None):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True,
                          text=True, env=env).stdout.strip()


CLOCK = [1_700_000_000]  # fixture commits get distinct, increasing committer times (TheHub #62064)


class Origin:
    """A bare repository with GitHub's pull request refs."""

    def __init__(self, tmp: Path):
        self.work = tmp / "work"
        self.bare = tmp / "origin.git"
        self.work.mkdir()
        git("init", "-q", "-b", "main", cwd=self.work)
        git("config", "user.email", "t@example.com", cwd=self.work)
        git("config", "user.name", "t", cwd=self.work)
        self.commit("base")
        git("init", "-q", "--bare", str(self.bare), cwd=tmp)
        git("push", "-q", str(self.bare), "main", cwd=self.work)

    def commit(self, msg, when=None, files=None):
        (self.work / "f.txt").write_text(msg + "\n")
        git("add", "f.txt", cwd=self.work)
        for rel, text in (files or {}).items():
            (self.work / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.work / rel).write_text(text, encoding="utf-8", newline="\n")
            git("add", "-f", rel, cwd=self.work)
        CLOCK[0] += 60
        stamp = f"@{when if when is not None else CLOCK[0]} +0000"
        git("commit", "-q", "-m", msg, cwd=self.work,
            env={**os.environ, "GIT_COMMITTER_DATE": stamp, "GIT_AUTHOR_DATE": stamp})
        return git("rev-parse", "HEAD", cwd=self.work)

    def branch(self, name, msg, when=None, files=None):
        git("checkout", "-q", "-B", name, "main", cwd=self.work)
        sha = self.commit(msg, when, files)
        git("push", "-q", "-f", str(self.bare), f"{name}:refs/heads/{name}", cwd=self.work)
        git("checkout", "-q", "main", cwd=self.work)
        return sha

    def detached(self, msg):
        """A commit no branch of the origin points at: a fork's head."""
        git("checkout", "-q", "--detach", "main", cwd=self.work)
        sha = self.commit(msg)
        git("push", "-q", str(self.bare), f"{sha}:refs/forks/{sha[:8]}", cwd=self.work)
        git("checkout", "-q", "main", cwd=self.work)
        return sha

    def pull(self, number, sha, open_=True):
        git("update-ref", f"refs/pull/{number}/head", sha, cwd=self.bare)
        if open_:
            git("update-ref", f"refs/pull/{number}/merge", sha, cwd=self.bare)


def pick(origin: Origin, tmp: Path, answers=None, **env_extra):
    stubs = tmp / "stubs"
    stubs.mkdir(exist_ok=True)
    curl = stubs / "curl"
    curl.write_text(CURL_STUB, encoding="utf-8", newline="\n")
    curl.chmod(curl.stat().st_mode | stat.S_IEXEC)
    ans_dir = tmp / "answers"
    rmtree(ans_dir, ignore_errors=True)
    ans_dir.mkdir()
    for sha, ans in (answers or {}).items():
        (ans_dir / sha).write_text(json.dumps(ans))
    run_dir = tmp / "build"
    rmtree(run_dir, ignore_errors=True)
    run_dir.mkdir()
    capture = tmp / "starts.jsonl"
    capture.write_text("")
    env = {**os.environ,
           "PATH": f"{stubs}{os.pathsep}{os.environ.get('PATH', '')}",
           "CURL": str(curl), "CAPTURE": str(capture), "ANSWERS": str(ans_dir),
           "REPO_SLUG": "ToddGBenson/keel", "GIT_URI": str(origin.bare),
           "MYKRONOS_INGESTION_URL": "http://mykronos.test",
           "MYKRONOS_INGESTION_TOKEN": "tok", **env_extra}
    r = subprocess.run(["bash", str(PICK)], cwd=run_dir, env=env, capture_output=True,
                       text=True, timeout=60)
    starts = [json.loads(line) for line in capture.read_text().splitlines() if line.strip()]
    return r, run_dir / "pr", starts, run_dir / "pr-sha" / "HEAD"


def sub(tmp: Path, name: str) -> Path:
    d = tmp / name
    d.mkdir()
    return d


def meta_of(pr: Path) -> Path:
    """The picker's state, beside the checkout and never inside it (TheHub #62015)."""
    return pr.parent / "pr-meta"


def done(status="completed", conclusion="success"):
    return {"name": "Concourse / keel", "check_run_id": 7, "status": status,
            "conclusion": conclusion, "outcome": "unchanged"}


def main():
    for tool in ("git", "bash"):
        if not shutil.which(tool):
            print(f"{tool} is required")
            return 1
    tmp = Path(tempfile.mkdtemp(prefix="pr-pick-"))
    try:
        o = Origin(tmp)
        a = o.branch("feat-a", "a")
        b = o.branch("feat-b", "b")
        fork = o.detached("fork")
        closed = o.branch("feat-closed", "closed")
        main_sha = git("rev-parse", "main", cwd=o.work)
        o.pull(11, a)
        o.pull(12, b)
        o.pull(13, fork)               # a fork: no branch here points at it
        o.pull(9, closed, open_=False)  # closed: no merge ref
        o.pull(8, main_sha)             # a head that is the base branch itself

        print("which heads")
        r, pr, starts, sha_file = pick(o, tmp)
        asked = [s["commit_sha"] for s in starts]
        check("the OLDEST open same-repo head is judged first (TheHub #62064)", r.returncode == 0 and asked == [a],
              f"rc={r.returncode} asked={asked}\n{r.stdout}{r.stderr}")
        check("a fork's head is never asked about", fork not in asked)
        check("a closed pull request (no merge ref) is never asked about", closed not in asked)
        check("a head that is the base branch is never asked about", main_sha not in asked)
        check("the start names the job and carries no conclusion", starts and starts[0]["job"] == "pr-checks"
              and starts[0]["phase"] == "start" and starts[0]["conclusion"] is None
              and starts[0]["repo_full_name"] == "ToddGBenson/keel", starts)
        head = (pr / ".git" / "HEAD").read_text().strip() if (pr / ".git" / "HEAD").exists() else ""
        check("the picked head is checked out detached, so check-run.sh reads its sha", head == a, head)
        check("pr-meta/.pr names the pull request, sha and branch",
              (meta_of(pr) / ".pr").exists() and (meta_of(pr) / ".pr").read_text().split() == ["11", a, "feat-a"])
        check("nothing judged is marked .none", not (meta_of(pr) / ".none").exists())
        check("the picker's state is never written into the pull request's checkout (TheHub #62015)",
              not (pr / ".pr").exists() and not (pr / ".none").exists())
        check("pr-sha/HEAD holds the head's sha alone, for the end report (review #1)",
              sha_file.exists() and sha_file.read_text().strip() == a)

        print("once per head")
        r, pr, starts, sha_file = pick(o, tmp, {a: done()})
        asked = [s["commit_sha"] for s in starts]
        check("a head with a completed check is skipped and the next one judged",
              r.returncode == 0 and asked == [a, b]
              and (pr / ".git" / "HEAD").read_text().strip() == b, f"{asked}\n{r.stdout}{r.stderr}")
        r, pr, starts, sha_file = pick(o, tmp, {a: done("in_progress", None)})
        check("a head whose check is still in progress (a run that died) is judged again",
              r.returncode == 0 and (pr / ".git" / "HEAD").read_text().strip() == a, r.stdout + r.stderr)
        r, pr, starts, sha_file = pick(o, tmp, {b: done(), a: done(conclusion="failure")})
        check("every head judged: a pass that marks pr-meta/.none and checks nothing out",
              r.returncode == 0 and (meta_of(pr) / ".none").exists() and not (pr / ".git").exists(),
              r.stdout + r.stderr)
        check("and writes no pr-sha/HEAD, so the end report posts nothing", not sha_file.exists())
        r, pr, starts, sha_file = pick(o, tmp, {b: done(), a: done()}, PR_PICK_LIMIT="1")
        check("at most PR_PICK_LIMIT starts per run", len(starts) == 1 and (meta_of(pr) / ".none").exists(),
              f"{len(starts)} starts")

        print("oldest head first (TheHub #62064)")
        # A newer push to a higher-numbered pull request does not jump the queue.
        b2 = o.branch("feat-b", "b, pushed again")
        o.pull(12, b2)
        r, pr, starts, sha_file = pick(o, tmp)
        asked = [s["commit_sha"] for s in starts]
        check("a newer push to #12 does not jump ahead of #11's older unjudged head",
              r.returncode == 0 and asked == [a], f"{asked}\n{r.stdout}{r.stderr}")
        # An old head on a high-numbered pull request beats a newer head on a lower one.
        old = o.branch("feat-old", "an old head", when=1_600_000_000)
        o.pull(20, old)
        r, pr, starts, sha_file = pick(o, tmp)
        asked = [s["commit_sha"] for s in starts]
        check("the head that has waited longest is judged first, whatever its PR number",
              r.returncode == 0 and asked == [old] and (meta_of(pr) / ".pr").read_text().split()[0] == "20",
              f"{asked}\n{r.stdout}{r.stderr}")

        print("refusals")
        r, pr, _, sha_file = pick(o, tmp, {old: {"detail": "This token is scoped to another repo"}})  # the head asked first
        check("an answer that is not created/updated/unchanged fails the step",
              r.returncode != 0 and not (meta_of(pr) / ".pr").exists() and not sha_file.exists(),
              r.stdout + r.stderr)
        r, pr, _, sha_file = pick(o, tmp, CURL_RC="22")
        check("a refused report (curl fails) fails the step", r.returncode != 0 and not (meta_of(pr) / ".pr").exists())
        r, _, _, _ = pick(o, tmp, GIT_URI="git@github.com:ToddGBenson/keel.git")
        check("an SSH uri with no GIT_PRIVATE_KEY is refused before anything is asked",
              r.returncode != 0 and "GIT_PRIVATE_KEY" in r.stderr, r.stderr)

        print("the script")
        script = PICK.read_text(encoding="utf-8")
        check("GitHub's host key is pinned, not trusted on first use",
              "StrictHostKeyChecking=yes" in script and "accept-new" not in script
              and "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" in script)
        check("it never calls the GitHub API", "api.github.com" not in script)

        print("pr-checks.sh")
        build = tmp / "checks"
        (build / "pr").mkdir(parents=True)
        (build / "pr-meta").mkdir()
        (build / "pr-meta" / ".none").write_text("")
        r = subprocess.run(["bash", str(CHECKS)], cwd=build, capture_output=True, text=True, timeout=60)
        check("nothing picked: a pass that runs nothing", r.returncode == 0 and "No pull request head" in r.stdout,
              r.stdout + r.stderr)
        (build / "pr-meta" / ".none").unlink()
        r = subprocess.run(["bash", str(CHECKS)], cwd=build, capture_output=True, text=True, timeout=60)
        check("no .pr and no .none: refused, never a vacuous pass", r.returncode != 0)
        # TheHub #62015: a `.none` committed in the pull request's own tree is content, not state.
        (build / "pr" / ".none").write_text("")
        r = subprocess.run(["bash", str(CHECKS)], cwd=build, capture_output=True, text=True, timeout=60)
        check("a .none inside pr/ is not read as 'nothing to judge' (TheHub #62015)",
              r.returncode != 0 and "No pull request head" not in r.stdout, r.stdout + r.stderr)
        (build / "pr-meta" / ".pr").write_text("11 " + "a" * 40 + " feat-a\n")
        r = subprocess.run(["bash", str(CHECKS)], cwd=build, capture_output=True, text=True, timeout=60)
        check("a picked head that is not the one checked out in pr/ is refused",
              r.returncode != 0 and "Unit suites on" not in r.stdout, r.stdout + r.stderr)
        checks_script = CHECKS.read_text(encoding="utf-8")
        check("pr-checks.sh runs the same suites as Actions' unit-suites",
              all(s in checks_script for s in ("test/*.test.py", "test/*.test.js", "SELFTEST", "EVALS")))

        print("a pull request whose tree carries the picker's marker files (TheHub #62015)")
        o2 = Origin(sub(tmp, "o2"))
        failing = {".none": "", ".pr": "0 " + "0" * 40 + " forged\n", "ci/requirements.txt": "",
                   "test/red.test.py": "import sys\nsys.exit(1)\n"}
        evil = o2.branch("feat-evil", "evil", files=failing)
        o2.pull(5, evil)
        r, pr, starts, sha_file = pick(o2, tmp / "o2", {})
        check("the head is picked and posted as in progress",
              r.returncode == 0 and [s["commit_sha"] for s in starts] == [evil], r.stdout + r.stderr)
        check("its committed .none is in the checkout (content) but the state says it is judged",
              (pr / ".none").exists() and (meta_of(pr) / ".pr").read_text().split() == ["5", evil, "feat-evil"]
              and not (meta_of(pr) / ".none").exists(), r.stdout + r.stderr)
        check("and a committed .pr cannot name another head",
              sha_file.read_text().strip() == evil and (pr / ".pr").read_text().split()[1] == "0" * 40)
        # pr-checks.sh edits git's global config: keep that out of the developer's.
        cfg_env = {**os.environ, "GIT_CONFIG_GLOBAL": str(tmp / "gitconfig-global")}
        r = subprocess.run(["bash", str(CHECKS)], cwd=pr.parent, capture_output=True, text=True,
                           timeout=300, env=cfg_env)
        check("pr-checks judges it, and the red suite fails the build rather than passing as 'none'",
              r.returncode != 0 and "No pull request head" not in r.stdout
              and f"Unit suites on #5 {evil}" in r.stdout, r.stdout + r.stderr)
        # TheHub #62268: each suite says how long it took, and the slowest are summed up at the end.
        check("each suite reports its time, and the slowest are listed at the end (TheHub #62268)",
              re.search(r"red\.test: FAIL \(\d+ s\)", r.stdout) is not None
              and re.search(r"Slowest suites \(seconds\), of \d+ s in all:\n   \d+ ", r.stdout) is not None,
              r.stdout)

        print("the head moves between ls-remote and fetch (TheHub #62015 F2)")
        o3 = Origin(sub(tmp, "o3"))
        first = o3.branch("feat-m", "first")
        o3.pull(7, first)
        moved = o3.branch("feat-other", "moved to this")
        wrapper = tmp / "o3" / "git-moving"
        wrapper.write_text('#!/usr/bin/env bash\ngit "$@"; rc=$?\n'
                           'if [ "${1:-}" = ls-remote ]; then git -C "$MOVE_BARE" update-ref refs/pull/7/head "$MOVE_TO"; fi\n'
                           'exit $rc\n', encoding="utf-8", newline="\n")
        wrapper.chmod(wrapper.stat().st_mode | stat.S_IEXEC)
        r, pr, starts, sha_file = pick(o3, tmp / "o3", {}, GIT=str(wrapper),
                                       MOVE_BARE=str(o3.bare), MOVE_TO=moved)
        check("a head that moved while it was fetched fails the step and says so",
              r.returncode != 0 and "moved from" in r.stderr and first in r.stderr and moved in r.stderr,
              r.stdout + r.stderr)
        check("nothing is recorded for the head that moved: no state, no sha for the report",
              not (meta_of(pr) / ".pr").exists() and not (meta_of(pr) / ".none").exists()
              and not sha_file.exists(), r.stdout + r.stderr)
        r2 = subprocess.run(["bash", str(CHECKS)], cwd=pr.parent, capture_output=True, text=True, timeout=60)
        check("and pr-checks refuses to judge what the failed pick left", r2.returncode != 0,
              r2.stdout + r2.stderr)
    finally:
        rmtree(tmp, ignore_errors=True)

    print()
    if failures:
        print(f"{len(failures)} failed")
        return 1
    print("all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
