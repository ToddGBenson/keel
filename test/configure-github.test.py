#!/usr/bin/env python3
"""
Tests for the merge gate scripts/configure-github.sh declares. Refs: TheHub #60978

keel's merge gate is the MyKronos `independent-review` check (decision #60849,
option C, carried out by #60978). MyKronos posts it on every pull request head
through its own GitHub App, and opens the approval request itself, but only on a
repository whose default branch already requires the check. Until #60978 the
script required twelve GitHub Actions job names instead. Every one of them comes
from a workflow reduced to `workflow_dispatch` (ci.yml, security.yml,
pr-governance.yml), so none ever arrives on a pull request: run as written, the
script blocked every merge.

Runs the REAL script under bash in a throwaway copy, with `gh` stubbed on PATH
(no network, no auth). The stub keeps the branch protection in a state file, so a
second run sees what the first one wrote:

  * with --review-app-id, and that App seen posting on this repository, the
    required checks are `independent-review` PINNED to the App (a check of the same
    name from any other app, a workflow job say, does not satisfy it), strict off
    (an up-to-date rule would move approved heads), and none of the dead contexts;
  * the pin survives a re-run: step 4's full protection PUT carries the existing
    `checks` with their app ids, not bare `contexts` (L0013, in a new field);
  * an existing unpinned `independent-review` is re-pinned, not duplicated, and
    other checks the operator added are kept;
  * no App id (a fork without MyKronos): nothing is required and the script says so;
  * an App id that has never posted here is not required (L0010: never enable a
    control nothing can satisfy, or every PR blocks); nor is the GitHub Actions app,
    since any workflow can post a check run with that name;
  * verification reports the pin, and FAILS an `independent-review` pinned to no app;
  * --dry-run writes nothing; --checks-only writes only the required checks.

    python test/configure-github.test.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "configure-github.sh"
BASH = shutil.which("bash") or "bash"
APP = 4551328
ACTIONS_APP = 15368
CHECK = "independent-review"
DEAD = "Process compliance"
failures = []
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except AttributeError:
    pass


def check(name, cond, detail=""):
    if cond:
        print(f"  ok    {name}")
    else:
        print(f"  FAIL  {name}")
        if detail:
            print("        " + str(detail).replace("\n", "\n        ")[:3000])
        failures.append(name)


# The stub. Python, behind a bash wrapper, so it runs the same on Windows and Linux.
STUB = r'''
import json, sys
state_path, log_path = sys.argv[1], sys.argv[2]
args = sys.argv[3:]
state = json.load(open(state_path, encoding="utf-8"))

def save():
    json.dump(state, open(state_path, "w", encoding="utf-8"))

def opt(name):
    return args[args.index(name) + 1] if name in args else None

if args[:1] == ["auth"]:
    sys.exit(0)
if args[:2] == ["repo", "view"]:
    field = opt("--json")
    print({"nameWithOwner": "o/r", "defaultBranchRef": "main", "description": "d"}.get(field, ""))
    sys.exit(0)
if args[:1] != ["api"]:
    sys.exit(0)

method = opt("-X") or "GET"
skip = {"-X", "-f", "-F", "-H", "--jq", "--input"}
path, i = None, 1
while i < len(args):
    if args[i] in skip:
        i += 2
        continue
    path = args[i]
    break
body = sys.stdin.read() if opt("--input") == "-" else ""
jq = opt("--jq") or ""
prot_path = "repos/o/r/branches/main/protection"

def gh_shape(p):
    """What GET returns after a PUT of payload p."""
    out = dict(p)
    for k in ("enforce_admins", "required_linear_history", "allow_force_pushes",
              "allow_deletions", "required_conversation_resolution"):
        if isinstance(p.get(k), bool):
            out[k] = {"enabled": p[k]}
    out["required_status_checks"] = rsc_shape(p.get("required_status_checks"))
    return out

def rsc_shape(r):
    if not r:
        return None
    checks = r.get("checks")
    if checks is None:
        checks = [{"context": c, "app_id": None} for c in r.get("contexts") or []]
    checks = [{"context": c["context"], "app_id": c.get("app_id")} for c in checks]
    return {"strict": r.get("strict", False), "contexts": [c["context"] for c in checks],
            "checks": checks}

if method != "GET":
    with open(log_path, "a", encoding="utf-8") as log:
        log.write(json.dumps({"method": method, "path": path, "body": body}) + "\n")
    if method == "PUT" and path == prot_path:
        state["protection"] = gh_shape(json.loads(body))
    elif method == "PATCH" and path == prot_path + "/required_status_checks":
        prot = state.get("protection")
        if not prot or not prot.get("required_status_checks"):
            print('{"message":"Required status checks not enabled"}')
            sys.exit(1)
        prot["required_status_checks"] = rsc_shape(json.loads(body))
    save()
    sys.exit(0)

if path == prot_path:
    prot = state.get("protection")
    if prot is None:
        print('{"message":"Branch not protected"}')
        sys.exit(1)
    if "contexts" in jq and "strict" in jq:
        # The jq the script used before #60978 to preserve existing checks.
        r = prot.get("required_status_checks")
        print(json.dumps({"strict": r["strict"], "contexts": r["contexts"]}) if r else "null")
    else:
        print(json.dumps(prot))
    sys.exit(0)
if path.startswith("repos/o/r/commits/") and "/check-runs" in path:
    ref = path.split("/")[4]
    print(json.dumps({"check_runs": state.get("check_runs", {}).get(ref, [])}))
    sys.exit(0)
if path.startswith("repos/o/r/pulls"):
    print(json.dumps(state.get("pulls", [])))
    sys.exit(0)
if path == "user":
    print({".id": "1", '.two_factor_authentication // "unknown"': "true"}.get(jq, '{"id": 1}'))
    sys.exit(0)
if path == "repos/o/r":
    print('{"secret_scanning": {"status": "enabled"}}' if jq else "{}")
    sys.exit(0)
print("")
sys.exit(0)
'''


def run(argv, protection=None, runs_on=None, app_id=APP, slug="mykronos-platform", env_extra=None):
    """Run the real script in a throwaway copy. Returns (rc, output, writes, state)."""
    tmp = Path(tempfile.mkdtemp(prefix="configure-github-"))
    try:
        (tmp / "scripts").mkdir()
        shutil.copy2(SCRIPT, tmp / "scripts" / "configure-github.sh")
        wf = tmp / ".github" / "workflows"
        wf.mkdir(parents=True)
        (wf / "ok.yml").write_text("permissions: {}\njobs: {}\n", encoding="utf-8")
        for f in ("SECURITY.md", "LICENSE", "CONTRIBUTING.md"):
            (tmp / f).write_text("x\n", encoding="utf-8")
        stubs = tmp / "stubs"
        stubs.mkdir()
        state = {"protection": protection, "check_runs": {}, "pulls": [
            {"number": 7, "head": {"sha": "prhead"}}]}
        if runs_on:
            state["check_runs"][runs_on] = [
                {"name": "library-allowlist", "app": {"id": app_id, "slug": slug}}]
        (stubs / "state.json").write_text(json.dumps(state), encoding="utf-8")
        (stubs / "stub.py").write_text(STUB, encoding="utf-8")
        (stubs / "gh").write_text(
            '#!/usr/bin/env bash\nexec "$STUB_PY" "$STUB_DIR/stub.py" '
            '"$STUB_DIR/state.json" "$STUB_DIR/writes.log" "$@"\n', newline="\n")
        # Owner-only (CodeQL py/overly-permissive-file).
        os.chmod(stubs / "gh", 0o700)
        env = dict(os.environ)
        env["PATH"] = str(stubs) + os.pathsep + env.get("PATH", "")
        env["STUB_PY"] = sys.executable
        env["STUB_DIR"] = str(stubs)
        # The operator's own git config must not decide the signing branch.
        env["GIT_CONFIG_GLOBAL"] = os.devnull
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env.pop("KEEL_REVIEW_APP_ID", None)
        env.update(env_extra or {})
        p = subprocess.run([BASH, "scripts/configure-github.sh", *argv], cwd=str(tmp),
                           capture_output=True, text=True, encoding="utf-8", env=env,
                           stdin=subprocess.DEVNULL, timeout=600)
        log = stubs / "writes.log"
        writes = [json.loads(line) for line in log.read_text(encoding="utf-8").splitlines()] \
            if log.exists() else []
        final = json.loads((stubs / "state.json").read_text(encoding="utf-8"))
        return p.returncode, p.stdout + p.stderr, writes, final
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def required(state):
    r = (state.get("protection") or {}).get("required_status_checks") or {}
    return r


def pinned(state, app=APP):
    return {"context": CHECK, "app_id": app} in (required(state).get("checks") or [])


def protection_with(checks, strict=False):
    return {
        "enforce_admins": {"enabled": True},
        "required_pull_request_reviews": {"required_approving_review_count": 0,
                                          "require_code_owner_reviews": False,
                                          "dismiss_stale_reviews": True},
        "required_status_checks": {"strict": strict,
                                   "contexts": [c["context"] for c in checks],
                                   "checks": checks},
    }


def enabled():
    """Protection with required checks enabled and empty, so --checks-only can PATCH."""
    return protection_with([])


# Full runs are slow on Windows (one process per gh call and per JSON read), so only
# the cases about steps 1 to 4 run the whole script; the rest use --checks-only.
print("configure-github.sh: the merge gate is MyKronos independent-review (TheHub #60978)")

# 1. Fresh repository, App id given, App seen on the default branch head.
rc, out, writes, st = run(["--yes", "--solo", "--review-app-id", str(APP)], runs_on="main")
r = required(st)
check("independent-review is required, pinned to the MyKronos App", pinned(st), r or out)
check("no dead Actions context is required (they never arrive on a PR)",
      DEAD not in (r.get("contexts") or []) and len(r.get("contexts") or []) == 1, r)
check("strict is off: an up-to-date rule would move approved heads", r.get("strict") is False, r)
check("verification names the pinned check",
      f"[ok]   {CHECK} required, pinned to App {APP}" in out, out[-2500:])

# 2. A PR head is enough evidence too (the App posts library-allowlist there).
rc, out, writes, st = run(["--yes", "--checks-only", "--review-app-id", str(APP)],
                          protection=enabled(), runs_on="prhead")
check("an App check run on an open PR head counts as the App posting here", pinned(st), out[-2000:])

# 3. Re-run with the pin in place: step 4's PUT must carry it, app id included.
existing = [{"context": CHECK, "app_id": APP}, {"context": "own-check", "app_id": 99}]
rc, out, writes, st = run(["--yes", "--solo", "--review-app-id", str(APP)],
                          protection=protection_with(existing), runs_on="main")
puts = [w for w in writes if w["method"] == "PUT" and w["path"].endswith("/protection")]
put_rsc = json.loads(puts[0]["body"]).get("required_status_checks") if puts else None
check("step 4's protection PUT keeps the existing checks WITH their app ids",
      bool(put_rsc) and {"context": CHECK, "app_id": APP} in (put_rsc.get("checks") or []),
      put_rsc or out[-2000:])
check("a re-run keeps the operator's own required check, and the pin",
      pinned(st) and {"context": "own-check", "app_id": 99} in (required(st).get("checks") or []),
      required(st))

# 4. An unpinned independent-review (any app may post it) is re-pinned, once.
rc, out, writes, st = run(["--yes", "--checks-only", "--review-app-id", str(APP)],
                          protection=protection_with([{"context": CHECK, "app_id": None}]),
                          runs_on="main")
names = [c["context"] for c in required(st).get("checks") or []]
check("an unpinned independent-review is re-pinned, not duplicated",
      pinned(st) and names.count(CHECK) == 1, required(st))

# 5. No App id: a fork without MyKronos requires nothing and says so.
rc, out, writes, st = run(["--yes", "--checks-only"], protection=enabled(), runs_on="main")
check("without an App id nothing is required", not required(st).get("checks"), required(st))
check("without an App id the script says the merge gate is not configured",
      "--review-app-id" in out and "not required" in out, out[-2500:])

# 6. KEEL_REVIEW_APP_ID is the same as the flag.
rc, out, writes, st = run(["--yes", "--checks-only"], protection=enabled(), runs_on="main",
                          env_extra={"KEEL_REVIEW_APP_ID": str(APP)})
check("KEEL_REVIEW_APP_ID works like --review-app-id", pinned(st), out[-2000:])

# 7. The App has never posted here: requiring it would block every PR.
rc, out, writes, st = run(["--yes", "--checks-only", "--review-app-id", str(APP)],
                          protection=enabled(), runs_on=None)
check("an App never seen on this repository is not required (L0010)",
      not pinned(st), required(st))
check("... and the script says why, and fails the run",
      "has not posted" in out and rc != 0, out[-2500:])

# 8. The GitHub Actions app: any workflow job can post a check called independent-review.
rc, out, writes, st = run(["--yes", "--checks-only", "--review-app-id", str(ACTIONS_APP)],
                          protection=enabled(), runs_on="main", app_id=ACTIONS_APP, slug="github-actions")
check("the GitHub Actions app is refused as the review App",
      not pinned(st, ACTIONS_APP) and rc != 0 and "github-actions" in out, out[-2000:])

# 9. Verification fails an independent-review that any app could satisfy.
rc, out, writes, st = run(["--yes", "--checks-only", "--dry-run"],
                          protection=protection_with([{"context": CHECK, "app_id": None}]))
check("verification FAILS an independent-review pinned to no app",
      f"[FAIL] {CHECK}" in out and rc != 0, out[-2000:])

# 10. --dry-run writes nothing and says what it would require.
rc, out, writes, st = run(["--yes", "--solo", "--dry-run", "--review-app-id", str(APP)],
                          runs_on="main")
check("--dry-run writes nothing", writes == [], writes)
check("--dry-run says it would require the pinned check",
      f"would require {CHECK}" in out and str(APP) in out, out[-2000:])

# 11. --checks-only touches the required checks and nothing else.
rc, out, writes, st = run(["--yes", "--checks-only", "--review-app-id", str(APP)],
                          protection=enabled(), runs_on="main")
paths = sorted({(w["method"], w["path"]) for w in writes})
check("--checks-only writes only the required status checks",
      paths == [("PATCH", "repos/o/r/branches/main/protection/required_status_checks")],
      paths)
check("--checks-only applies the pin", pinned(st), required(st))
check("--checks-only verifies the checks and exits 0", rc == 0, out[-2500:])

print()
if failures:
    print(f"{len(failures)} failure(s)")
    sys.exit(1)
print("all passed")
