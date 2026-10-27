#!/usr/bin/env python3
"""
Tests for signing and verifying the platform release. Refs: #144, TheHub #60936, POAM-011

Runs the REAL scripts/platform-release.sh under bash. Only cosign is stubbed on
PATH, so what is tested is the script's own decisions:

  * manifest: every TRACKED platform-owned file, hashed and sorted; untracked
    and project-owned files are not in it;
  * verify refuses an unsigned release (no bundle, empty bundle) without
    calling cosign, refuses when cosign rejects the signature, and passes the
    EXACT signer identity (release.yml on refs/tags/<tag>) and GitHub's issuer;
  * verify binds the signature to a KNOWN-GOOD workflow, not just to a tag
    name: the tag must resolve to a commit reachable from a trusted ref
    (main), and cosign must see that commit as the certificate's workflow sha.
    A tag pushed on a commit whose release.yml was rewritten (drops the G5
    approval) is refused, though its signature is otherwise valid (HubOps
    review of #145, finding 1);
  * verify refuses a tag whose commit does not DESCEND from the release floor,
    a commit hard-coded in the script, even when that commit is on main: main's
    own history holds release.yml versions that interpolated a free-text input
    into `run:` while holding `id-token: write` (wave-2 review of #145);
  * verify --tree refuses a tree whose platform files were changed or added to.

PLATFORM-OWNED (platform/MANIFEST.yml), so it reads only platform-owned files.
The tests of ci/scripts/supply-chain.sh and .github/workflows/release.yml,
which are merge-required and which a fork adapts, are in
test/supply-chain.test.py (project-owned). A fork that adapts those must be
able to edit the test that asserts on them (review of #145, finding 3).

    python test/platform-release.test.py
"""
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
FLOOR_LINE = re.compile(r'^RELEASE_FLOOR="[0-9a-f]{40}"$', re.M)
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


def git_cmd(tree: Path):
    return ["git", "-C", str(tree), "-c", "user.email=t@example.invalid", "-c", "user.name=t",
            "-c", "core.autocrlf=false", "-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false"]


def floored_script(tmp: Path, floor: str) -> Path:
    """A copy of the real script whose hard-coded floor is the fixture's floor.

    Exactly one RELEASE_FLOOR line must be replaced, so a script that loses
    its floor constant cannot pass these tests by accident."""
    text = RELEASE_SH.read_text(encoding="utf-8")
    new, n = FLOOR_LINE.subn(f'RELEASE_FLOOR="{floor}"', text)
    copy = tmp / "platform-release.floored.sh"
    copy.write_text(new, encoding="utf-8", newline="\n")
    return copy if n == 1 else RELEASE_SH


def make_tree(tmp: Path) -> Path:
    """A small git repository with platform-owned, project-owned and untracked files.

    Branch `main` carries the reviewed history. Its first commit, tagged
    v0.9.0, is BELOW the release floor: the shape of keel's pre-af878f1
    release.yml, which interpolated a dispatch input into `run:` while the job
    held `id-token: write`. The next commit is the floor, tagged v1.2.0
    (annotated).
    Branch `evil` is one commit off main, never merged, tagged v6.6.6: the
    shape of a tag pushed on a commit whose release.yml was rewritten.
    """
    tree = tmp / "tree"
    git = git_cmd(tree)
    old = tree / ".github" / "workflows" / "release.yml"
    old.parent.mkdir(parents=True)
    old.write_text("permissions: {id-token: write}\nrun: echo ${{ inputs.change_record }}\n",
                   encoding="utf-8")
    subprocess.run([*git, "init", "-q", "-b", "main"], check=True)
    subprocess.run([*git, "add", "-A"], check=True)
    subprocess.run([*git, "commit", "-q", "-m", "release.yml before the floor (injectable)"], check=True)
    subprocess.run([*git, "tag", "-a", "-m", "old release", "v0.9.0"], check=True)
    old.write_text("# authorize-release, no inputs, no id-token\n", encoding="utf-8")
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
    subprocess.run([*git, "add", "-A"], check=True)
    subprocess.run([*git, "commit", "-q", "-m", "fixture: the release floor"], check=True)
    subprocess.run([*git, "tag", "-a", "-m", "release", "v1.2.0"], check=True)
    subprocess.run([*git, "checkout", "-q", "-b", "evil"], check=True)
    (tree / ".github" / "workflows").mkdir(parents=True, exist_ok=True)
    (tree / ".github" / "workflows" / "release.yml").write_text("# no G5 gate\n", encoding="utf-8")
    subprocess.run([*git, "add", "-A"], check=True)
    subprocess.run([*git, "commit", "-q", "-m", "release.yml without authorize-release"], check=True)
    subprocess.run([*git, "tag", "v6.6.6"], check=True)
    subprocess.run([*git, "checkout", "-q", "main"], check=True)
    (tree / "scripts" / "untracked.sh").write_text("echo untracked\n", encoding="utf-8")
    return tree


def rev(tree: Path, ref: str) -> str:
    return subprocess.run(["git", "-C", str(tree), "rev-parse", ref], check=True,
                          capture_output=True, text=True).stdout.strip()


def flag(called, name):
    """The value cosign received for `name`, or None."""
    called = called or []
    if name not in called or called.index(name) + 1 >= len(called):
        return None
    return called[called.index(name) + 1]


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
    main_sha = rev(tree, "v1.2.0^{commit}")
    evil_sha = rev(tree, "v6.6.6^{commit}")
    old_sha = rev(tree, "v0.9.0^{commit}")
    script = floored_script(tmp, main_sha)
    check("the script has exactly one hard-coded RELEASE_FLOOR=\"<40-hex sha>\" line",
          len(FLOOR_LINE.findall(RELEASE_SH.read_text(encoding="utf-8"))) == 1)

    def verify(bundle, cosign_rc=0, tag="v1.2.0", tree_dir=None, manifest=out,
               git_dir=tree, trusted="main", omit=(), sh=None):
        if argv.exists():
            argv.unlink()
        cosign_stub(stubs, argv, cosign_rc)
        args = [(sh or script).as_posix(), "verify", "--manifest", manifest.as_posix(),
                "--bundle", bundle, "--repo", "owner/keel", "--tag", tag]
        if "--git" not in omit:
            args += ["--git", git_dir.as_posix()]
        if "--trusted-ref" not in omit:
            args += ["--trusted-ref", trusted]
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
          flag(called, "--certificate-identity") == want_id
          and not any("regexp" in a for a in called), str(called))
    check("verify: the issuer is GitHub's OIDC provider",
          flag(called, "--certificate-oidc-issuer") == ISSUER, str(called))
    check("verify: the bundle and the manifest are what cosign checks",
          bool(called) and called[-1] == out.as_posix() and bundle.as_posix() in called, str(called))

    # ── finding 1: bound to a known-good workflow, not to a tag name ────────
    check("verify: cosign must see the tag's COMMIT as the certificate's workflow sha",
          flag(called, "--certificate-github-workflow-sha") == main_sha, str(called))
    check("verify: ... from this repository, dispatched (release.yml's only trigger), on the tag",
          flag(called, "--certificate-github-workflow-repository") == "owner/keel"
          and flag(called, "--certificate-github-workflow-trigger") == "workflow_dispatch"
          and flag(called, "--certificate-github-workflow-ref") == "refs/tags/v1.2.0", str(called))

    rc, log, called = verify(bundle.as_posix(), tag="v6.6.6")
    check("verify: a tag on a commit NOT on the trusted ref -> refused (rewritten release.yml)",
          rc == 1 and "not reachable from" in log, log)
    check("verify: ... and refused before cosign, whatever the signature says", called is None, str(called))
    check("verify: ... naming the commit it refused", evil_sha[:12] in log, log)

    # ── wave-2 review: "on main" is not enough; main holds injectable versions ─
    rc, log, called = verify(bundle.as_posix(), tag="v0.9.0")
    check("verify: a tag on main BELOW the release floor -> refused (old, injectable release.yml)",
          rc == 1 and "release floor" in log, log)
    check("verify: ... refused before cosign, whatever the signature says", called is None, str(called))
    check("verify: ... naming the commit it refused", old_sha[:12] in log, log)

    rc, log, called = verify(bundle.as_posix(), sh=RELEASE_SH)
    check("verify: a repository that does not hold the floor commit -> refused, not skipped",
          rc == 1 and "release floor" in log and called is None, log)

    rc, log, called = verify(bundle.as_posix(), tag="v9.9.9")
    check("verify: a tag the repository does not have -> refused",
          rc == 1 and "v9.9.9" in log and called is None, log)

    rc, log, called = verify(bundle.as_posix(), omit=("--git",))
    check("verify: no --git -> refused (nothing to resolve the tag in)",
          rc == 1 and "--git" in log and called is None, log)

    rc, log, called = verify(bundle.as_posix(), omit=("--trusted-ref",))
    check("verify: no --trusted-ref -> refused (no default: HEAD may BE the tag)",
          rc == 1 and "--trusted-ref" in log and called is None, log)

    rc, log, called = verify(bundle.as_posix(), trusted="no-such-branch")
    check("verify: a trusted ref that does not exist -> refused", rc == 1 and called is None, log)

    rc, log, called = verify(bundle.as_posix(), tag="v6.6.6", trusted="evil")
    check("verify: the same tag passes when its commit IS on the trusted ref (guard)",
          rc == 0 and flag(called, "--certificate-github-workflow-sha") == evil_sha, log)

    rc, log = bash([script.as_posix(), "verify", "--manifest", out.as_posix(),
                    "--bundle", bundle.as_posix(), "--repo", "owner/keel",
                    "--git", tree.as_posix(), "--trusted-ref", "main"], cwd=tmp, stubs=stubs)
    check("verify: no --tag -> refused (a signature is bound to its tag)", rc == 1, log)

    shutil.rmtree(stubs)
    stubs.mkdir()
    rc, log = bash([script.as_posix(), "verify", "--manifest", out.as_posix(),
                    "--bundle", bundle.as_posix(), "--repo", "owner/keel", "--tag", "v1.2.0",
                    "--git", tree.as_posix(), "--trusted-ref", "main"],
                   # git stays reachable (it resolves the tag); cosign does not.
                   cwd=tmp, env_extra={"PATH": os.pathsep.join(
                       [str(stubs), str(Path(shutil.which("git")).parent), "/usr/bin", "/bin"])})
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

print()
if failures:
    print(f"{len(failures)} FAILED: {failures}")
    sys.exit(1)
print("all passed")
