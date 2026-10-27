#!/usr/bin/env python3
"""
Tests for keel's own supply-chain lanes. Refs: #144, TheHub #60936, POAM-011

PROJECT-OWNED (under test/ in platform/MANIFEST.yml), because what it asserts
on is merge-required: ci/scripts/supply-chain.sh and
.github/workflows/release.yml are files a fork adapts (to build and sign an
image, say). A fork that does must be able to edit this test. Until the
HubOps review of #145 (finding 3) these checks lived in the platform-owned
test/platform-release.test.py, which sync-platform.sh overwrites: a fork that
adapted supply-chain.sh got a test it could not edit and that failed forever.
The verifier itself, scripts/platform-release.sh, is tested there.

Runs the REAL scripts under bash; cosign, curl and the cosign download
plumbing are stubbed on PATH.

ci/scripts/supply-chain.sh STAGE=verify (Concourse verify-artifact)
  * NO RELEASE YET (the API's 404) is ADVISORY, exit 0, until the first signed
    release exists: keel had none when this shipped, and a lane red on every
    main commit until an operator acts teaches people to ignore it (finding 2);
  * a rate-limited or refused API call is NOT "no release": it fails, and says
    it could not check (finding 4). An optional GITHUB_API_TOKEN authenticates
    the call, through a header file rather than argv;
  * once a release exists it FAILS when unsigned, when the signature does not
    verify, and when the release's tag is on a commit that is not on main
    (finding 1); it passes only when all of that holds.
  * build-and-attest writes the manifest that release.yml signs.

.github/workflows/release.yml
  * signing runs after the G5 approval, keyless, with the same cosign pin
    Concourse verifies with, and verifies against main before publishing.

    python test/supply-chain.test.py
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
RELEASE_SH = ROOT / "scripts" / "platform-release.sh"
SUPPLY_SH = ROOT / "ci" / "scripts" / "supply-chain.sh"
RELEASE_YML = ROOT / ".github" / "workflows" / "release.yml"
VARS = ROOT / "ci" / "vars.example.yml"
MANIFEST = ROOT / "platform" / "MANIFEST.yml"
failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def write_exec(path: Path, text: str):
    path.write_text(text, encoding="utf-8", newline="\n")
    path.chmod(path.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)


def cosign_stub(stubs: Path, log: Path, rc: int):
    """A cosign that records its argv and answers verify-blob with `rc`."""
    write_exec(stubs / "cosign",
               "#!/usr/bin/env bash\n"
               'if [ "${1:-}" = "version" ]; then echo "cosign-stub"; exit 0; fi\n'
               f'printf "%s\\n" "$@" > "{log.as_posix()}"\n'
               f"exit {rc}\n")


def bash(args, cwd, stubs=None, env_extra=None):
    env = dict(os.environ)
    if stubs is not None:
        env["PATH"] = f"{stubs}{os.pathsep}{env['PATH']}"
    env.pop("GITHUB_API_TOKEN", None)
    env.update(env_extra or {})
    p = subprocess.run(["bash", *args], cwd=cwd, env=env, capture_output=True,
                       text=True, encoding="utf-8", errors="replace")
    return p.returncode, p.stdout + p.stderr


def flag(called, name):
    called = called or []
    if name not in called or called.index(name) + 1 >= len(called):
        return None
    return called[called.index(name) + 1]


def git(repo: Path, *args, capture=False):
    cmd = ["git", "-C", str(repo), "-c", "user.email=t@example.invalid", "-c", "user.name=t",
           "-c", "core.autocrlf=false", "-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false", *args]
    p = subprocess.run(cmd, check=True, capture_output=True, text=True)
    return p.stdout.strip() if capture else None


# ── ci/scripts/supply-chain.sh STAGE=verify (Concourse verify-artifact) ──────
print("supply-chain.sh STAGE=verify")


FLOOR_LINE = re.compile(r'^RELEASE_FLOOR="[0-9a-f]{40}"$', re.M)


def run_verify_stage(release, cosign_rc=0, status=None, env_extra=None, manifest_text=None):
    """`release`: None = no body; else the latest-release JSON body.
    `status`: the releases API's HTTP status (default 200 with a body, else 404).
    `manifest_text`: the release's platform-manifest.txt asset; by default the
    true manifest of v1.2.0's tree (what release.yml would have signed).

    repo/ is a git repository like Concourse's checkout of main: HEAD is main.
    Its root commit, v0.9.0, is below the release floor (the floor is the next
    commit, hard-coded into the copied platform-release.sh); v1.2.0 is on main
    above it; v6.6.6 is on a commit that was never merged; and main has moved
    on after v1.2.0, changing a platform file.
    Returns (rc, log, cosign argv or None, curl log text, tag shas)."""
    tmp = Path(tempfile.mkdtemp(prefix="verify-stage-"))
    try:
        repo = tmp / "repo"
        (repo / "scripts").mkdir(parents=True)
        (repo / "ci" / "scripts").mkdir(parents=True)
        (repo / "platform").mkdir(parents=True)
        git(repo, "init", "-q", "-b", "main")
        (repo / "old-release.yml").write_text("id-token: write; ${{ inputs.change_record }}\n",
                                              encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", "below the floor")
        git(repo, "tag", "-a", "-m", "old release", "v0.9.0")
        git(repo, "commit", "-q", "--allow-empty", "-m", "the release floor")
        floor = git(repo, "rev-parse", "HEAD", capture=True)
        (repo / "scripts" / "platform-release.sh").write_text(
            FLOOR_LINE.sub(f'RELEASE_FLOOR="{floor}"', RELEASE_SH.read_text(encoding="utf-8")),
            encoding="utf-8", newline="\n")
        shutil.copy(SUPPLY_SH, repo / "ci" / "scripts" / "supply-chain.sh")
        (repo / "platform" / "MANIFEST.yml").write_text(
            "version: 1\nplatform_owned:\n  - scripts/\n  - platform/\nmerge_required:\n  - ci/\n",
            encoding="utf-8", newline="\n")
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", "main")
        git(repo, "tag", "-a", "-m", "release", "v1.2.0")
        true_manifest = tmp / "true-manifest.txt"
        subprocess.run(["bash", (repo / "scripts" / "platform-release.sh").as_posix(), "manifest",
                        true_manifest.as_posix()], cwd=repo, check=True, capture_output=True)
        git(repo, "checkout", "-q", "-b", "evil")
        (repo / "evil.txt").write_text("release.yml without its G5 gate\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", "evil")
        git(repo, "tag", "v6.6.6")
        git(repo, "checkout", "-q", "main")
        # main moves on after the release and changes a platform file: --tree
        # must check the TAG's tree, not this checkout of main.
        (repo / "scripts" / "later.sh").write_text("echo later\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", "a later main commit")
        shas = {t: git(repo, "rev-parse", f"{t}^{{commit}}", capture=True)
                for t in ("v0.9.0", "v1.2.0", "v6.6.6")}
        (tmp / "artifact").mkdir()
        fixtures = tmp / "fixtures"
        fixtures.mkdir()
        if release is not None:
            (fixtures / "latest.json").write_text(json.dumps(release), encoding="utf-8")
        code = status if status is not None else (200 if release is not None else 404)
        if code != 200 and release is None:
            (fixtures / "latest.json").write_text('{"message": "stub"}', encoding="utf-8")
        (fixtures / "platform-manifest.txt").write_bytes(
            manifest_text.encode("utf-8") if manifest_text is not None else true_manifest.read_bytes())
        (fixtures / "platform-manifest.sigstore.json").write_text('{"stub": 1}\n', encoding="utf-8")
        stubs = tmp / "stubs"
        stubs.mkdir()
        argv = tmp / "cosign-argv.txt"
        curl_log = tmp / "curl.log"
        cosign_stub(stubs, argv, cosign_rc)
        # curl: records its argv and every header it sends (a `-H @file` is
        # read), answers the releases API with `code` (no -f: the script reads
        # the status itself) and the asset URLs from fixtures.
        write_exec(stubs / "curl",
                   "#!/usr/bin/env bash\n"
                   f'L="{curl_log.as_posix()}"\n'
                   'echo "ARGV: $*" >> "$L"\n'
                   'out=""; url=""; wfmt=""\n'
                   'while [ $# -gt 0 ]; do case "$1" in\n'
                   '  -o) out="$2"; shift 2;;\n'
                   '  -w) wfmt="$2"; shift 2;;\n'
                   '  -H) case "$2" in @*) while IFS= read -r h; do echo "HEADER: $h" >> "$L"; done < "${2#@}";;'
                   ' *) echo "HEADER: $2" >> "$L";; esac; shift 2;;\n'
                   '  -*) shift;;\n'
                   '  *) url="$1"; shift;;\n'
                   'esac; done\n'
                   'case "$url" in\n'
                   '  */sigstore/cosign/*) exit 0 ;;\n'
                   f'  */releases/latest) cp "{fixtures.as_posix()}/latest.json" "$out";'
                   f' [ -n "$wfmt" ] && printf "%s" "{code}"; exit 0 ;;\n'
                   f'  https://assets.invalid/*) cp "{fixtures.as_posix()}/${{url##*/}}" "$out" ;;\n'
                   '  *) echo "unexpected url $url" >&2; exit 99 ;;\n'
                   'esac\n')
        write_exec(stubs / "sha256sum", "#!/usr/bin/env bash\ncat >/dev/null; exit 0\n")
        write_exec(stubs / "chmod", "#!/usr/bin/env bash\nexit 0\n")
        env = {"STAGE": "verify", "COSIGN_VERSION": "3.1.3", "COSIGN_SHA256": "0" * 64,
               "REGISTRY": "", "REPO_SLUG": "owner/keel"}
        env.update(env_extra or {})
        rc, log = bash([(repo / "ci" / "scripts" / "supply-chain.sh").as_posix()], cwd=tmp,
                       stubs=stubs, env_extra=env)
        called = argv.read_text(encoding="utf-8").splitlines() if argv.exists() else None
        clog = curl_log.read_text(encoding="utf-8") if curl_log.exists() else ""
        return rc, log, called, clog, shas
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def asset(name):
    return {"name": name, "browser_download_url": f"https://assets.invalid/{name}"}


def signed(tag="v1.2.0"):
    return {"tag_name": tag, "assets": [asset("platform-manifest.txt"),
                                        asset("platform-manifest.sigstore.json")]}


# finding 2: no release yet is advisory, not red
rc, log, called, clog, _ = run_verify_stage(None)
check("verify-artifact: NO RELEASE YET (404) -> advisory, exit 0, until the first signed release",
      rc == 0 and "ADVISORY" in log and "no release yet" in log, log)
check("verify-artifact: no release -> says plainly nothing was verified",
      "nothing was verified" in log, log)
check("verify-artifact: no release -> cosign verify-blob never reached", called is None, str(called))

# finding 4: a refused or rate-limited API call is not "no release"
for code in (403, 429):
    rc, log, called, clog, _ = run_verify_stage(None, status=code)
    check(f"verify-artifact: API HTTP {code} -> FAILS (could not check), not advisory",
          rc != 0 and "ADVISORY" not in log, log)
    check(f"verify-artifact: API HTTP {code} -> reported as a rate limit / refusal, not as 'no release'",
          "rate limit" in log and "no release yet" not in log and "no published release" not in log, log)
rc, log, called, clog, _ = run_verify_stage(None, status=500)
check("verify-artifact: API HTTP 500 -> FAILS with the status", rc != 0 and "500" in log, log)

rc, log, called, clog, _ = run_verify_stage(None, env_extra={"GITHUB_API_TOKEN": "tok-sentinel-123"})
check("verify-artifact: GITHUB_API_TOKEN authenticates the releases API call",
      "HEADER: Authorization: Bearer tok-sentinel-123" in clog, clog)
check("verify-artifact: ... through a header file, never on curl's argv",
      not any("tok-sentinel-123" in ln for ln in clog.splitlines() if ln.startswith("ARGV:")), clog)
check("verify-artifact: ... and never printed", "tok-sentinel-123" not in log, log)
rc, log, called, clog, _ = run_verify_stage(None)
check("verify-artifact: no token -> no Authorization header", "Authorization" not in clog, clog)

# once a release exists, everything is a hard failure
rc, log, called, clog, _ = run_verify_stage({"tag_name": "v1.2.0", "assets": []})
check("verify-artifact: latest release has no signature -> FAILS as UNSIGNED",
      rc != 0 and "UNSIGNED" in log, log)
check("verify-artifact: unsigned -> cosign verify-blob never reached", called is None, str(called))

rc, log, called, clog, _ = run_verify_stage({"tag_name": "v1.2.0", "assets": [asset("platform-manifest.txt")]})
check("verify-artifact: manifest without its bundle -> FAILS as UNSIGNED",
      rc != 0 and "UNSIGNED" in log, log)

rc, log, called, clog, _ = run_verify_stage(signed(), cosign_rc=1)
check("verify-artifact: a signature that does not verify -> FAILS", rc != 0, log)

rc, log, called, clog, shas = run_verify_stage(signed(), cosign_rc=0)
check("verify-artifact: a verifying signature -> passes", rc == 0 and "verified:" in log, log)
check("verify-artifact: checks release.yml's identity on the RELEASED tag",
      called is not None and
      "https://github.com/owner/keel/.github/workflows/release.yml@refs/tags/v1.2.0" in called, str(called))
check("verify-artifact: pins the certificate to the tag's commit on main (finding 1)",
      flag(called, "--certificate-github-workflow-sha") == shas["v1.2.0"], str(called))

check("verify-artifact: --tree: the signed manifest is checked against the TAG's tree (Low, wave-2 review)",
      "tree: ok" in log, log)

rc, log, called, clog, _ = run_verify_stage(signed(), cosign_rc=0,
                                            manifest_text="0" * 64 + "  scripts/a.sh\n")
check("verify-artifact: --tree: a signed manifest that is not the tag's tree -> FAILS",
      rc != 0 and "not the signed release" in log, log)

rc, log, called, clog, _ = run_verify_stage(signed("v0.9.0"), cosign_rc=0)
check("verify-artifact: a release tagged on main BELOW the release floor -> FAILS before cosign",
      rc != 0 and "release floor" in log and called is None, log)

rc, log, called, clog, _ = run_verify_stage(signed("v6.6.6"), cosign_rc=0)
check("verify-artifact: a release tagged on a commit NOT on main -> FAILS, even with a valid signature",
      rc != 0 and "not reachable from" in log and called is None, log)

rc, log = bash([SUPPLY_SH.as_posix()], cwd=ROOT,
               env_extra={"STAGE": "verify", "COSIGN_VERSION": "x", "COSIGN_SHA256": "y", "REPO_SLUG": ""})
check("verify-artifact: no REPO_SLUG -> FAILS before anything is fetched", rc != 0 and "REPO_SLUG" in log, log)

check("supply-chain.sh: no ADAPT echo stands in for a cosign call",
      not re.search(r'echo\s+"ADAPT: cosign', SUPPLY_SH.read_text(encoding="utf-8")))


# ── ci/scripts/supply-chain.sh STAGE=build-and-attest ───────────────────────
print("supply-chain.sh STAGE=build-and-attest")
tmp = Path(tempfile.mkdtemp(prefix="build-stage-"))
try:
    work = tmp / "work"
    repo = work / "repo"
    for rel, body in {
        "platform/MANIFEST.yml": "version: 1\nplatform_owned:\n  - scripts/\nmerge_required:\n  - ci/\n",
        "scripts/a.sh": "echo a\n",
        "ci/pipeline.yml": "jobs: []\n",
    }.items():
        f = repo / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_bytes(body.encode("utf-8"))
    shutil.copy(RELEASE_SH, repo / "scripts" / "platform-release.sh")
    git(repo, "init", "-q", "-b", "main")
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "fixture")
    (work / "sbom").mkdir()
    (work / "sbom" / "sbom.json").write_text("{}", encoding="utf-8")
    (work / "artifact").mkdir()
    stubs = tmp / "stubs"
    stubs.mkdir()
    cosign_stub(stubs, tmp / "argv.txt", 0)
    write_exec(stubs / "curl", "#!/usr/bin/env bash\nexit 0\n")
    write_exec(stubs / "chmod", "#!/usr/bin/env bash\nexit 0\n")
    rc, log = bash([SUPPLY_SH.as_posix()], cwd=work, stubs=stubs,
                   env_extra={"STAGE": "build-and-attest", "COSIGN_VERSION": "3.1.3",
                              "COSIGN_SHA256": "0" * 64, "REGISTRY": ""})
    produced = work / "artifact" / "platform-manifest.txt"
    check("build-and-attest: exits 0", rc == 0, log)
    check("build-and-attest: writes the manifest release.yml signs",
          produced.exists() and "scripts/platform-release.sh" in produced.read_text(encoding="utf-8"), log)
finally:
    shutil.rmtree(tmp, ignore_errors=True)


# ── .github/workflows/release.yml ───────────────────────────────────────────
print("release.yml sign-and-attest")
try:
    import yaml  # PyYAML, from ci/requirements.txt
    wf = yaml.safe_load(RELEASE_YML.read_text(encoding="utf-8"))
    jobs = wf.get("jobs") or {}
    job = jobs.get("sign-and-attest") or {}
    check("release.yml: a sign-and-attest job exists", bool(job))
    check("release.yml: it runs only after the G5 approval", job.get("needs") == "authorize-release",
          str(job.get("needs")))
    perms = job.get("permissions") or {}
    check("release.yml: keyless (id-token: write) and attesting (attestations: write)",
          perms.get("id-token") == "write" and perms.get("attestations") == "write", str(perms))
    steps = "\n".join(str(s.get("run", "")) + str(s.get("uses", "")) for s in job.get("steps", []))
    check("release.yml: cosign sign-blob writes a bundle", "cosign sign-blob --yes --bundle" in steps)
    check("release.yml: provenance is attested", "actions/attest-build-provenance@" in steps)
    check("release.yml: the verifier runs, and must refuse an unsigned release",
          "platform-release.sh verify" in steps and "a release with no signature" in steps)
    check("release.yml: the verifier checks the tag against origin/main (finding 1)",
          re.search(r"--git\s+\.\s+--trusted-ref\s+origin/main", steps) is not None, steps)
    checkout = next((s for s in job.get("steps", []) if "actions/checkout@" in str(s.get("uses", ""))), {})
    check("release.yml: sign-and-attest checks out full history, so origin/main exists",
          str((checkout.get("with") or {}).get("fetch-depth")) == "0", str(checkout))
    pre = "\n".join(str(s.get("run", "")) for s in (jobs.get("preflight") or {}).get("steps", []))
    check("release.yml: preflight refuses a tag whose commit is not on main",
          "merge-base --is-ancestor" in pre and "origin/main" in pre, pre[:200])
    env = job.get("env") or {}
    vars_text = VARS.read_text(encoding="utf-8")
    vv = re.search(r"^cosign_version:\s*(\S+)", vars_text, re.M)
    vs = re.search(r"^cosign_sha256:\s*(\S+)", vars_text, re.M)
    check("release.yml: signs with the same cosign pin Concourse verifies with",
          vv and vs and str(env.get("COSIGN_VERSION")) == vv.group(1)
          and str(env.get("COSIGN_SHA256")) == vs.group(1), f"{env} vs vars.example.yml")
except ImportError:
    check("PyYAML is installed (pip install -r ci/requirements.txt)", False)


# ── wave-2 review: the release floor is a commit whose release.yml is safe ──
# platform-release.sh refuses any tag that does not descend from RELEASE_FLOOR.
# That is only worth something if no release.yml from the floor to HEAD can
# sign without the G5 gate: every job holding `id-token: write` must need
# authorize-release, and no `${{ inputs.* }}` may reach the workflow (before
# af878f1, preflight interpolated inputs.change_record into `run:` while
# holding id-token: write). Checked on every revision of release.yml between
# the floor and HEAD, so moving the floor back below an unsafe one fails here.
print("release floor")
fm = re.search(r'^RELEASE_FLOOR="([0-9a-f]{40})"$', RELEASE_SH.read_text(encoding="utf-8"), re.M)
check("platform-release.sh: RELEASE_FLOOR is a hard-coded full sha", fm is not None)
floor = fm.group(1) if fm else ""
have = floor and subprocess.run(["git", "-C", str(ROOT), "cat-file", "-e", f"{floor}^{{commit}}"],
                                capture_output=True).returncode == 0
if not have:
    # A template fork or a shallow clone does not hold keel's history. The
    # verifier refuses in that case (tested in platform-release.test.py); this
    # check of keel's own history can only run where the history is.
    print(f"  [skip] floor {floor[:12]} is not in this clone's history")
else:
    floor_on_head = subprocess.run(["git", "-C", str(ROOT), "merge-base", "--is-ancestor", floor, "HEAD"],
                                   capture_output=True).returncode == 0
    check("release floor: HEAD descends from it (a release from HEAD is not refused)", floor_on_head)
    revs = [floor] + subprocess.run(
        ["git", "-C", str(ROOT), "log", "--format=%H", f"{floor}..HEAD", "--", ".github/workflows/release.yml"],
        check=True, capture_output=True, text=True).stdout.split()
    try:
        import yaml
        for sha in revs:
            src = subprocess.run(["git", "-C", str(ROOT), "show", f"{sha}:.github/workflows/release.yml"],
                                 capture_output=True, text=True, encoding="utf-8")
            if src.returncode != 0:
                check(f"release floor: release.yml exists at {sha[:12]}", False, src.stderr)
                continue
            text = src.stdout
            check(f"release.yml@{sha[:12]}: no ${{{{ inputs.* }}}} reaches the workflow",
                  re.search(r"\$\{\{\s*(github\.event\.)?inputs\.", text) is None)
            wfd = yaml.safe_load(text) or {}
            top = wfd.get("permissions") or {}
            check(f"release.yml@{sha[:12]}: no top-level id-token: write",
                  not (isinstance(top, dict) and top.get("id-token") == "write") and top != "write-all")
            for name, j in (wfd.get("jobs") or {}).items():
                perms = j.get("permissions") or {}
                if (isinstance(perms, dict) and perms.get("id-token") == "write") or perms == "write-all":
                    needs = j.get("needs")
                    needs = [needs] if isinstance(needs, str) else list(needs or [])
                    check(f"release.yml@{sha[:12]}: job {name} holds id-token: write only after authorize-release",
                          "authorize-release" in needs, str(needs))
    except ImportError:
        check("PyYAML is installed (pip install -r ci/requirements.txt)", False)


# ── finding 3: a platform-owned test reads only platform-owned files ─────────
print("platform-owned tests")
mtxt = MANIFEST.read_text(encoding="utf-8")
sec = re.search(r"^platform_owned:\n((?:\s*-\s+.*\n|\s*#.*\n|\n)*)", mtxt, re.M)
owned_tests = [ln.strip()[2:].split("#")[0].strip() for ln in (sec.group(1) if sec else "").split("\n")
               if ln.strip().startswith("- test/") and ln.strip().endswith(".py")]
check("MANIFEST: test/platform-release.test.py is platform-owned (it tests the platform verifier)",
      "test/platform-release.test.py" in owned_tests, str(owned_tests))
check("MANIFEST: test/supply-chain.test.py is NOT platform-owned (a fork edits it)",
      "test/supply-chain.test.py" not in owned_tests, str(owned_tests))
for rel in owned_tests:
    text = (ROOT / rel).read_text(encoding="utf-8") if (ROOT / rel).exists() else ""
    reads = re.findall(r'ROOT\s*/\s*"(ci|\.github)"', text)
    check(f"{rel}: opens no merge-required file of this repository (ci/, .github/)", not reads, str(reads))

print()
if failures:
    print(f"{len(failures)} FAILED: {failures}")
    sys.exit(1)
print("all passed")
