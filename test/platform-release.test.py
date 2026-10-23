#!/usr/bin/env python3
"""
Tests for signing and verifying the platform release. Refs: #144, TheHub #60936, POAM-011

Runs the REAL scripts under bash. Only cosign (and, for the Concourse stage,
the network and the cosign download plumbing) is stubbed on PATH, so what is
tested is each script's own decisions:

scripts/platform-release.sh
  * manifest: every TRACKED platform-owned file, hashed and sorted; untracked
    and project-owned files are not in it;
  * verify refuses an unsigned release (no bundle, empty bundle) without
    calling cosign, refuses when cosign rejects the signature, and passes the
    EXACT signer identity (release.yml on refs/tags/<tag>) and GitHub's issuer;
  * verify --tree refuses a tree whose platform files were changed or added to.

ci/scripts/supply-chain.sh (Concourse build-and-attest / verify-artifact)
  * verify FAILS when there is no release, when the latest release carries no
    signature, and when the signature does not verify; it passes only when it
    does. It used to print "ADAPT: cosign verify" and exit 0 in every case;
  * build-and-attest writes the manifest that release.yml signs.

.github/workflows/release.yml
  * signing runs after the G5 approval, keyless (id-token: write), and with
    the same cosign pin Concourse verifies with.

    python test/platform-release.test.py
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
ISSUER = "https://token.actions.githubusercontent.com"
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
    env.update(env_extra or {})
    p = subprocess.run(["bash", *args], cwd=cwd, env=env, capture_output=True,
                       text=True, encoding="utf-8", errors="replace")
    return p.returncode, p.stdout + p.stderr


MANIFEST_YML = """version: 1
platform_owned:
  - scripts/
  # a comment between entries
  - docs/00-overview.md
merge_required:
  - ci/
project_owned:
  - src/
"""


def make_tree(tmp: Path) -> Path:
    """A small git repository with platform-owned, project-owned and untracked files."""
    tree = tmp / "tree"
    for rel, body in {
        "platform/MANIFEST.yml": MANIFEST_YML,
        "scripts/b.sh": "echo b\n",
        "scripts/a.sh": "echo a\n",
        "scripts/sub dir/c.py": "print('c')\n",
        "docs/00-overview.md": "# overview\n",
        "docs/99-project.md": "project doc\n",
        "ci/pipeline.yml": "jobs: []\n",
        "src/app.py": "pass\n",
    }.items():
        f = tree / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_bytes(body.encode("utf-8"))
    git = ["git", "-C", str(tree), "-c", "user.email=t@example.invalid", "-c", "user.name=t",
           "-c", "core.autocrlf=false", "-c", "commit.gpgsign=false"]
    subprocess.run([*git, "init", "-q"], check=True)
    subprocess.run([*git, "add", "-A"], check=True)
    subprocess.run([*git, "commit", "-q", "-m", "fixture"], check=True)
    (tree / "scripts" / "untracked.sh").write_text("echo untracked\n", encoding="utf-8")
    return tree


# ── scripts/platform-release.sh manifest ────────────────────────────────────
print("platform-release.sh manifest")
tmp = Path(tempfile.mkdtemp(prefix="platform-release-"))
try:
    tree = make_tree(tmp)
    out = tmp / "m.txt"
    rc, log = bash([RELEASE_SH.as_posix(), "manifest", out.as_posix()], cwd=tree)
    check("manifest: exits 0", rc == 0, log)
    lines = out.read_text(encoding="utf-8").splitlines() if out.exists() else []
    paths = [ln.split("  ", 1)[1] for ln in lines if "  " in ln]
    check("manifest: exactly the tracked platform-owned files, sorted",
          paths == ["docs/00-overview.md", "scripts/a.sh", "scripts/b.sh", "scripts/sub dir/c.py"],
          str(paths))
    check("manifest: each line is a sha256 and a path",
          all(re.fullmatch(r"[0-9a-f]{64}  \S.*", ln) for ln in lines) and len(lines) == 4, str(lines))
    check("manifest: an untracked file is not part of the release",
          not any("untracked" in p for p in paths))
    check("manifest: no CR in the output", b"\r" not in (out.read_bytes() if out.exists() else b""))

    # ── verify ──────────────────────────────────────────────────────────────
    print("platform-release.sh verify")
    stubs = tmp / "stubs"
    stubs.mkdir()
    argv = tmp / "cosign-argv.txt"

    def verify(bundle, cosign_rc=0, tag="v1.2.0", tree_dir=None, manifest=out):
        if argv.exists():
            argv.unlink()
        cosign_stub(stubs, argv, cosign_rc)
        args = [RELEASE_SH.as_posix(), "verify", "--manifest", manifest.as_posix(),
                "--bundle", bundle, "--repo", "owner/keel", "--tag", tag]
        if tree_dir is not None:
            args += ["--tree", tree_dir.as_posix()]
        rc, log = bash(args, cwd=tmp, stubs=stubs)
        called = argv.read_text(encoding="utf-8").splitlines() if argv.exists() else None
        return rc, log, called

    bundle = tmp / "m.sigstore.json"
    bundle.write_text('{"mediaType": "stub"}\n', encoding="utf-8")
    empty = tmp / "empty.json"
    empty.write_text("", encoding="utf-8")

    rc, log, called = verify((tmp / "absent.json").as_posix())
    check("verify: no bundle -> refused as UNSIGNED", rc == 1 and "UNSIGNED" in log, log)
    check("verify: no bundle -> cosign never called", called is None)

    rc, log, called = verify(empty.as_posix())
    check("verify: empty bundle -> refused as UNSIGNED", rc == 1 and "UNSIGNED" in log, log)

    rc, log, called = verify(bundle.as_posix(), cosign_rc=1)
    check("verify: a signature cosign rejects -> refused", rc == 1 and "does not verify" in log, log)

    rc, log, called = verify(bundle.as_posix(), cosign_rc=0)
    check("verify: a signature cosign accepts -> passes", rc == 0, log)
    called = called or []
    want_id = "https://github.com/owner/keel/.github/workflows/release.yml@refs/tags/v1.2.0"
    check("verify: cosign verify-blob is what runs", called[:1] == ["verify-blob"], str(called))
    check("verify: the identity is EXACT (release.yml on that tag), not a regexp",
          "--certificate-identity" in called
          and called[called.index("--certificate-identity") + 1] == want_id
          and not any("regexp" in a for a in called), str(called))
    check("verify: the issuer is GitHub's OIDC provider",
          "--certificate-oidc-issuer" in called
          and called[called.index("--certificate-oidc-issuer") + 1] == ISSUER, str(called))
    check("verify: the bundle and the manifest are what cosign checks",
          bool(called) and called[-1] == out.as_posix() and bundle.as_posix() in called, str(called))

    rc, log = bash([RELEASE_SH.as_posix(), "verify", "--manifest", out.as_posix(),
                    "--bundle", bundle.as_posix(), "--repo", "owner/keel"], cwd=tmp, stubs=stubs)
    check("verify: no --tag -> refused (a signature is bound to its tag)", rc == 1, log)

    shutil.rmtree(stubs)
    stubs.mkdir()
    rc, log = bash([RELEASE_SH.as_posix(), "verify", "--manifest", out.as_posix(),
                    "--bundle", bundle.as_posix(), "--repo", "owner/keel", "--tag", "v1"],
                   cwd=tmp, env_extra={"PATH": f"{stubs}{os.pathsep}/usr/bin{os.pathsep}/bin"})
    check("verify: no cosign installed -> refused, not passed",
          rc == 1 and "cosign is not installed" in log, log)

    rc, log, _ = verify(bundle.as_posix(), tree_dir=tree)
    check("verify --tree: the tree that was signed -> passes", rc == 0 and "tree: ok" in log, log)

    (tree / "scripts" / "a.sh").write_text("echo changed\n", encoding="utf-8")
    rc, log, _ = verify(bundle.as_posix(), tree_dir=tree)
    check("verify --tree: a changed platform file -> refused", rc == 1 and "not the signed release" in log, log)
    subprocess.run(["git", "-C", str(tree), "checkout", "-q", "--", "scripts/a.sh"], check=True)

    (tree / "scripts" / "added.sh").write_text("echo added\n", encoding="utf-8")
    subprocess.run(["git", "-C", str(tree), "add", "scripts/added.sh"], check=True)
    rc, log, _ = verify(bundle.as_posix(), tree_dir=tree)
    check("verify --tree: an added platform file -> refused", rc == 1 and "not the signed release" in log, log)
finally:
    shutil.rmtree(tmp, ignore_errors=True)


# ── ci/scripts/supply-chain.sh STAGE=verify (Concourse verify-artifact) ──────
print("supply-chain.sh STAGE=verify")


def run_verify_stage(release, cosign_rc=0):
    """`release`: None = no release (404); else the latest-release JSON body."""
    tmp = Path(tempfile.mkdtemp(prefix="verify-stage-"))
    try:
        (tmp / "repo" / "scripts").mkdir(parents=True)
        (tmp / "repo" / "ci" / "scripts").mkdir(parents=True)
        shutil.copy(RELEASE_SH, tmp / "repo" / "scripts" / "platform-release.sh")
        shutil.copy(SUPPLY_SH, tmp / "repo" / "ci" / "scripts" / "supply-chain.sh")
        (tmp / "artifact").mkdir()
        fixtures = tmp / "fixtures"
        fixtures.mkdir()
        if release is not None:
            (fixtures / "latest.json").write_text(json.dumps(release), encoding="utf-8")
        (fixtures / "platform-manifest.txt").write_text("0" * 64 + "  scripts/a.sh\n", encoding="utf-8")
        (fixtures / "platform-manifest.sigstore.json").write_text('{"stub": 1}\n', encoding="utf-8")
        stubs = tmp / "stubs"
        stubs.mkdir()
        argv = tmp / "cosign-argv.txt"
        cosign_stub(stubs, argv, cosign_rc)
        # curl: the cosign download is a no-op (cosign is the stub above);
        # the releases API answers from fixtures, or 404s (curl -f exits 22).
        write_exec(stubs / "curl",
                   "#!/usr/bin/env bash\n"
                   'out=""; url=""\n'
                   'while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; -H) shift 2;; -*) shift;; *) url="$1"; shift;; esac; done\n'
                   'case "$url" in\n'
                   '  */sigstore/cosign/*) exit 0 ;;\n'
                   f'  */releases/latest) [ -f "{fixtures.as_posix()}/latest.json" ] || exit 22; cp "{fixtures.as_posix()}/latest.json" "$out" ;;\n'
                   f'  https://assets.invalid/*) cp "{fixtures.as_posix()}/${{url##*/}}" "$out" ;;\n'
                   '  *) echo "unexpected url $url" >&2; exit 99 ;;\n'
                   'esac\n')
        write_exec(stubs / "sha256sum", "#!/usr/bin/env bash\ncat >/dev/null; exit 0\n")
        write_exec(stubs / "chmod", "#!/usr/bin/env bash\nexit 0\n")
        rc, log = bash([(tmp / "repo" / "ci" / "scripts" / "supply-chain.sh").as_posix()], cwd=tmp, stubs=stubs,
                       env_extra={"STAGE": "verify", "COSIGN_VERSION": "3.1.3", "COSIGN_SHA256": "0" * 64,
                                  "REGISTRY": "", "REPO_SLUG": "owner/keel"})
        called = argv.read_text(encoding="utf-8").splitlines() if argv.exists() else None
        return rc, log, called
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def asset(name):
    return {"name": name, "browser_download_url": f"https://assets.invalid/{name}"}


signed = {"tag_name": "v1.2.0", "assets": [asset("platform-manifest.txt"),
                                           asset("platform-manifest.sigstore.json")]}

rc, log, called = run_verify_stage(None)
check("verify-artifact: no release at all -> FAILS (nothing signed exists)",
      rc != 0 and "no published release" in log, log)

rc, log, called = run_verify_stage({"tag_name": "v1.2.0", "assets": []})
check("verify-artifact: latest release has no signature -> FAILS as UNSIGNED",
      rc != 0 and "UNSIGNED" in log, log)
check("verify-artifact: unsigned -> cosign verify-blob never reached", called is None, str(called))

rc, log, called = run_verify_stage({"tag_name": "v1.2.0", "assets": [asset("platform-manifest.txt")]})
check("verify-artifact: manifest without its bundle -> FAILS as UNSIGNED",
      rc != 0 and "UNSIGNED" in log, log)

rc, log, called = run_verify_stage(signed, cosign_rc=1)
check("verify-artifact: a signature that does not verify -> FAILS", rc != 0, log)

rc, log, called = run_verify_stage(signed, cosign_rc=0)
check("verify-artifact: a verifying signature -> passes", rc == 0 and "verified:" in log, log)
check("verify-artifact: checks release.yml's identity on the RELEASED tag",
      called is not None and
      "https://github.com/owner/keel/.github/workflows/release.yml@refs/tags/v1.2.0" in called, str(called))

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
    work.mkdir()
    repo = make_tree(tmp)
    shutil.move(str(repo), str(work / "repo"))
    (work / "repo" / "scripts").mkdir(exist_ok=True)
    shutil.copy(RELEASE_SH, work / "repo" / "scripts" / "platform-release.sh")
    subprocess.run(["git", "-C", str(work / "repo"), "add", "scripts/platform-release.sh"], check=True)
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
    job = (wf.get("jobs") or {}).get("sign-and-attest") or {}
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
    env = job.get("env") or {}
    vars_text = VARS.read_text(encoding="utf-8")
    vv = re.search(r"^cosign_version:\s*(\S+)", vars_text, re.M)
    vs = re.search(r"^cosign_sha256:\s*(\S+)", vars_text, re.M)
    check("release.yml: signs with the same cosign pin Concourse verifies with",
          vv and vs and str(env.get("COSIGN_VERSION")) == vv.group(1)
          and str(env.get("COSIGN_SHA256")) == vs.group(1), f"{env} vs vars.example.yml")
except ImportError:
    check("PyYAML is installed (pip install -r ci/requirements.txt)", False)

print()
if failures:
    print(f"{len(failures)} FAILED: {failures}")
    sys.exit(1)
print("all passed")
