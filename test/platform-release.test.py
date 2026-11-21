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
  * verify --tree refuses a tree whose platform files were changed or added to;
  * verify --key (TheHub #62072) checks the bundle against the PEM key
    .github/cosign.pub committed on the trusted ref, with no certificate flags,
    refuses a wrong key, a key only in the working tree and a key given as an
    argument, and runs the same tag, floor and tree checks; keyless is unchanged.

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
    # TheHub #62072: keyless stays the default and is unchanged, flag for flag.
    check("verify (keyless, the default): cosign's argv is exactly the keyless one, with no --key",
          called == ["verify-blob", "--bundle", bundle.as_posix(),
                     "--certificate-identity", want_id,
                     "--certificate-oidc-issuer", ISSUER,
                     "--certificate-github-workflow-repository", "owner/keel",
                     "--certificate-github-workflow-ref", "refs/tags/v1.2.0",
                     "--certificate-github-workflow-sha", main_sha,
                     "--certificate-github-workflow-trigger", "workflow_dispatch",
                     out.as_posix()], str(called))

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

    # ── TheHub #61432: the floor is per repository ─────────────────────────────
    # The real script (keel's floor, which this fixture does not hold) with the upstream
    # identity pointed at this fixture's signer: upstream keel is always held to its floor.
    up = tmp / "platform-release.upstream.sh"
    up_text, n_up = re.subn(r'^KEEL_UPSTREAM="[^"]*"$', 'KEEL_UPSTREAM="owner/keel"',
                            RELEASE_SH.read_text(encoding="utf-8"), flags=re.M)
    up.write_text(up_text, encoding="utf-8", newline="\n")
    check("the script names its upstream in exactly one KEEL_UPSTREAM=\"...\" line", n_up == 1)
    rc, log, called = verify(bundle.as_posix(), sh=up)
    check("verify: UPSTREAM keel without its floor commit -> refused, not skipped",
          rc == 1 and "release floor" in log and called is None, log)

    def verify_as(repo_name, sh=RELEASE_SH, tag="v1.2.0", git_dir=tree, trusted="main"):
        if argv.exists():
            argv.unlink()
        cosign_stub(stubs, argv, 0)
        args = [sh.as_posix(), "verify", "--manifest", out.as_posix(), "--bundle", bundle.as_posix(),
                "--repo", repo_name, "--tag", tag, "--git", git_dir.as_posix(), "--trusted-ref", trusted]
        rc, log = bash(args, cwd=tmp, stubs=stubs)
        return rc, log, (argv.read_text(encoding="utf-8").splitlines() if argv.exists() else None)

    # No implicit default: a repository's first commit may carry the pre-gate release.yml
    # (binnacle's does), so a fork with no keel history and no configured floor is refused.
    rc, log, called = verify_as("owner/fork")
    check("verify: a FORK with no keel history and no .github/release-floor -> refused, naming the file",
          rc == 1 and ".github/release-floor" in log and called is None, log)

    # A configured floor, committed on the trusted ref, moves the fork's floor forward.
    fork = tmp / "fork"
    subprocess.run(["git", "clone", "-q", tree.as_posix(), fork.as_posix()], check=True)
    fgit = git_cmd(fork)
    subprocess.run([*fgit, "checkout", "-q", "-B", "main", "origin/main"], check=True)
    for tg in ("v0.9.0", "v1.2.0"):
        subprocess.run([*fgit, "fetch", "-q", "origin", f"refs/tags/{tg}:refs/tags/{tg}"], check=False)
    (fork / ".github").mkdir(exist_ok=True)
    (fork / ".github" / "release-floor").write_text(main_sha + "\n", encoding="utf-8")
    subprocess.run([*fgit, "add", "-A"], check=True)
    subprocess.run([*fgit, "commit", "-q", "-m", "release floor"], check=True)
    rc, log, called = verify_as("owner/fork", tag="v0.9.0", git_dir=fork)
    check("verify: a fork tag BELOW its configured .github/release-floor -> refused",
          rc == 1 and "release floor" in log and called is None, log)
    rc, log, called = verify_as("owner/fork", tag="v1.2.0", git_dir=fork)
    check("verify: a FORK with no keel history and a configured floor: a tag at it -> passes",
          rc == 0 and called is not None, log)
    (fork / ".github" / "release-floor").write_text("0" * 40 + "\n", encoding="utf-8")
    subprocess.run([*fgit, "commit", "-q", "-am", "a floor not in the repository"], check=True)
    rc, log, called = verify_as("owner/fork", tag="v1.2.0", git_dir=fork)
    check("verify: a configured floor that is not in the repository -> refused",
          rc == 1 and "release-floor" in log and called is None, log)

    # The floor may only move forward: a configured floor behind the default is refused.
    keelish = tmp / "keelish"
    subprocess.run(["git", "clone", "-q", tree.as_posix(), keelish.as_posix()], check=True)
    kgit = git_cmd(keelish)
    subprocess.run([*kgit, "checkout", "-q", "-B", "main", "origin/main"], check=True)
    subprocess.run([*kgit, "fetch", "-q", "origin", "refs/tags/v0.9.0:refs/tags/v0.9.0"], check=False)
    subprocess.run([*kgit, "fetch", "-q", "origin", "refs/tags/v1.2.0:refs/tags/v1.2.0"], check=False)
    (keelish / ".github" / "release-floor").write_text(old_sha + "\n", encoding="utf-8")
    subprocess.run([*kgit, "add", "-A"], check=True)
    subprocess.run([*kgit, "commit", "-q", "-m", "try to lower the floor"], check=True)
    rc, log, called = verify_as("owner/fork", sh=script, tag="v0.9.0", git_dir=keelish)
    check("verify: a configured floor BEHIND the keel floor it would replace -> refused (forward only)",
          rc == 1 and "only move forward" in log and called is None, log)

    # The trusted ref is a branch, never a tag (review of #202): a tag spelled like a branch,
    # on a commit off main that carries its own floor file, must not stand in for main.
    tagref = tmp / "tagref"
    subprocess.run(["git", "clone", "-q", tree.as_posix(), tagref.as_posix()], check=True)
    rgit = git_cmd(tagref)
    subprocess.run([*rgit, "checkout", "-q", "-B", "main", "origin/main"], check=True)
    subprocess.run([*rgit, "fetch", "-q", "origin", "refs/tags/v1.2.0:refs/tags/v1.2.0"], check=False)
    subprocess.run([*rgit, "checkout", "-q", "-b", "offmain"], check=True)
    (tagref / ".github").mkdir(exist_ok=True)
    (tagref / ".github" / "release-floor").write_text(main_sha + "\n", encoding="utf-8")
    subprocess.run([*rgit, "add", "-A"], check=True)
    subprocess.run([*rgit, "commit", "-q", "-m", "a floor off main"], check=True)
    subprocess.run([*rgit, "tag", "release/main"], check=True)
    subprocess.run([*rgit, "checkout", "-q", "main"], check=True)
    subprocess.run([*rgit, "branch", "-q", "-D", "offmain"], check=True)
    rc, log, called = verify_as("owner/fork", tag="v1.2.0", git_dir=tagref, trusted="release/main")
    check("verify: a TAG spelled like a branch as the trusted ref -> refused (a tag cannot be the trusted ref)",
          rc == 1 and "not a branch" in log and called is None, log)
    rc, log, called = verify_as("owner/fork", tag="v1.2.0", git_dir=tagref, trusted="refs/tags/release/main")
    check("verify: refs/tags/... as the trusted ref -> refused",
          rc == 1 and "not a branch" in log and called is None, log)
    rc, log, called = verify_as("Owner/KEEL", sh=up)
    check("verify: the upstream name matched in any case (Owner/KEEL is owner/keel) -> held to keel's floor",
          rc == 1 and "fetch the full history of" in log and called is None, log)

    # A shallow clone is refused: missing history is not "no keel history".
    shallow = tmp / "shallow"
    subprocess.run(["git", "clone", "-q", "--depth", "1", "--branch", "main", f"file://{tree.as_posix()}",
                    shallow.as_posix()], check=True)
    subprocess.run([*git_cmd(shallow), "fetch", "-q", "--depth", "1", "origin", "refs/tags/v1.2.0:refs/tags/v1.2.0"], check=False)
    rc, log, called = verify_as("owner/fork", tag="v1.2.0", git_dir=shallow, trusted="HEAD")
    check("verify: a SHALLOW clone -> refused (fetch the full history)",
          rc == 1 and "shallow" in log and called is None, log)

    # A configured floor must be reachable from the trusted ref (not a commit on a side branch).
    side = tmp / "side"
    subprocess.run(["git", "clone", "-q", tree.as_posix(), side.as_posix()], check=True)
    sgit = git_cmd(side)
    subprocess.run([*sgit, "checkout", "-q", "-B", "main", "origin/main"], check=True)
    subprocess.run([*sgit, "fetch", "-q", "origin", "refs/tags/v1.2.0:refs/tags/v1.2.0"], check=False)
    subprocess.run([*sgit, "checkout", "-q", "-b", "side"], check=True)
    subprocess.run([*sgit, "commit", "-q", "--allow-empty", "-m", "a side commit"], check=True)
    side_sha = subprocess.run([*sgit, "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
    subprocess.run([*sgit, "checkout", "-q", "main"], check=True)
    (side / ".github").mkdir(exist_ok=True)
    (side / ".github" / "release-floor").write_text(side_sha + "\n", encoding="utf-8")
    subprocess.run([*sgit, "add", "-A"], check=True)
    subprocess.run([*sgit, "commit", "-q", "-m", "a floor on a side branch"], check=True)
    rc, log, called = verify_as("owner/fork", tag="v1.2.0", git_dir=side)
    check("verify: a configured floor NOT reachable from the trusted ref -> refused",
          rc == 1 and "not reachable from the trusted ref" in log and called is None, log)

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

    # ── TheHub #62072: verify --key, the public key read from the trusted ref ─
    print("platform-release.sh verify --key")
    good_pem = "-----BEGIN PUBLIC KEY-----\nR09PRC1LRVktRk9SLVRIRS1URVNU\n-----END PUBLIC KEY-----\n"
    wrong_pem = "-----BEGIN PUBLIC KEY-----\nV1JPTkctS0VZLUZPUi1USEUtVEVTVA==\n-----END PUBLIC KEY-----\n"
    good_key = tmp / "good.pub"
    good_key.write_text(good_pem, encoding="utf-8", newline="\n")
    key_copy = tmp / "cosign-key-seen.pub"
    key_path_log = tmp / "cosign-key-path.txt"

    def key_stub():
        """A cosign that records its argv and the key it was handed, and verifies
        a --key signature only when that key is good_key (a keyless call passes)."""
        write_exec(stubs / "cosign",
                   "#!/usr/bin/env bash\n"
                   'if [ "${1:-}" = "version" ]; then echo "cosign-stub"; exit 0; fi\n'
                   f'printf "%s\\n" "$@" > "{argv.as_posix()}"\n'
                   'key=""; prev=""\n'
                   'for a in "$@"; do [ "$prev" = "--key" ] && key="$a"; prev="$a"; done\n'
                   'if [ -n "$key" ]; then\n'
                   f'  printf "%s" "$key" > "{key_path_log.as_posix()}"\n'
                   f'  cp "$key" "{key_copy.as_posix()}"\n'
                   f'  cmp -s "$key" "{good_key.as_posix()}" || exit 1\n'
                   'fi\n'
                   "exit 0\n")

    def verify_key(git_dir, tag="v1.2.0", trusted="main", tree_dir=None, key_args=("--key",)):
        for f in (argv, key_copy, key_path_log):
            if f.exists():
                f.unlink()
        key_stub()
        args = [script.as_posix(), "verify", *key_args, "--manifest", out.as_posix(),
                "--bundle", bundle.as_posix(), "--repo", "owner/keel", "--tag", tag,
                "--git", git_dir.as_posix(), "--trusted-ref", trusted]
        if tree_dir is not None:
            args += ["--tree", tree_dir.as_posix()]
        rc, log = bash(args, cwd=tmp, stubs=stubs)
        return rc, log, (argv.read_text(encoding="utf-8").splitlines() if argv.exists() else None)

    # A clone whose main carries .github/cosign.pub (the good key), plus branches for the
    # other cases. All of them hold the fixture's floor (main_sha) and the three tags.
    keyed = tmp / "keyed"
    subprocess.run(["git", "clone", "-q", tree.as_posix(), keyed.as_posix()], check=True)
    kd = git_cmd(keyed)
    subprocess.run([*kd, "checkout", "-q", "-B", "main", "origin/main"], check=True)
    subprocess.run([*kd, "fetch", "-q", "origin", "refs/heads/evil:refs/remotes/origin/evil"], check=False)
    for tg in ("v0.9.0", "v1.2.0", "v6.6.6"):
        subprocess.run([*kd, "fetch", "-q", "origin", f"refs/tags/{tg}:refs/tags/{tg}"], check=False)
    pub = keyed / ".github" / "cosign.pub"

    def commit_key(branch, text):
        subprocess.run([*kd, "checkout", "-q", "-B", branch, "main"], check=True)
        pub.write_text(text, encoding="utf-8", newline="\n")
        subprocess.run([*kd, "add", "-A"], check=True)
        subprocess.run([*kd, "commit", "-q", "-m", f"{branch}: .github/cosign.pub"], check=True)
        subprocess.run([*kd, "checkout", "-q", "main"], check=True)

    commit_key("rotated", wrong_pem)
    commit_key("privkey", "-----BEGIN ENCRYPTED SIGSTORE PRIVATE KEY-----\nc2VjcmV0\n"
                          "-----END ENCRYPTED SIGSTORE PRIVATE KEY-----\n")
    pub.write_text(good_pem, encoding="utf-8", newline="\n")
    subprocess.run([*kd, "add", "-A"], check=True)
    subprocess.run([*kd, "commit", "-q", "-m", "main: .github/cosign.pub"], check=True)

    rc, log, called = verify_key(keyed)
    check("verify --key: a bundle that verifies against the trusted ref's key -> passes",
          rc == 0 and "signature: ok (key .github/cosign.pub on main" in log, log)
    called = called or []
    check("verify --key: cosign verify-blob --key runs, over the bundle and the manifest",
          called[:1] == ["verify-blob"] and flag(called, "--key") is not None
          and flag(called, "--bundle") == bundle.as_posix() and called[-1:] == [out.as_posix()], str(called))
    check("verify --key: cosign is handed the key committed on the trusted ref",
          key_copy.exists() and key_copy.read_text(encoding="utf-8") == good_pem)
    check("verify --key: no certificate-identity or issuer flag in keyed mode",
          not any(a.startswith("--certificate") for a in called), str(called))
    seen = key_path_log.read_text(encoding="utf-8") if key_path_log.exists() else ""
    check("verify --key: the key is a temporary copy, removed when the verifier exits",
          bool(seen) and not Path(seen).exists() and Path(seen) != pub, seen)

    rc, log, called = verify_key(keyed, trusted="rotated")
    check("verify --key: a WRONG key on the trusted ref -> refused (cosign rejects the signature)",
          rc == 1 and "does not verify against .github/cosign.pub" in log and called is not None, log)

    # The key exists only in the working tree (written, even staged, never committed on main).
    wt_key = tree / ".github" / "cosign.pub"
    wt_key.write_text(good_pem, encoding="utf-8", newline="\n")
    subprocess.run(["git", "-C", str(tree), "add", ".github/cosign.pub"], check=True)
    rc, log, called = verify_key(tree)
    check("verify --key: a key only in the WORKING TREE -> refused (read from the trusted ref only)",
          rc == 1 and "not committed on the trusted ref" in log, log)
    check("verify --key: ... refused before cosign", called is None, str(called))
    subprocess.run(["git", "-C", str(tree), "rm", "-q", "--cached", ".github/cosign.pub"], check=True)
    wt_key.unlink()

    rc, log, called = verify_key(keyed, key_args=("--key", good_key.as_posix()))
    check("verify --key PATH: the key cannot be an argument -> refused, cosign never called",
          rc == 1 and "unknown argument" in log and called is None, log)

    rc, log, called = verify_key(keyed, trusted="privkey")
    check("verify --key: a trusted-ref .github/cosign.pub that is not a PEM public key -> refused",
          rc == 1 and "not a PEM public key" in log and called is None, log)

    # The shared path: the tag, trusted-ref and floor checks refuse in keyed mode exactly as keyless.
    rc, log, called = verify_key(keyed, tag="v6.6.6")
    check("verify --key: a tag NOT on the trusted ref -> refused before cosign (shared check)",
          rc == 1 and "not reachable from" in log and evil_sha[:12] in log and called is None, log)
    rc, log, called = verify_key(keyed, tag="v0.9.0")
    check("verify --key: a tag BELOW the release floor -> refused before cosign (shared check)",
          rc == 1 and "release floor" in log and called is None, log)
    rc, log, called = verify_key(keyed, trusted="refs/tags/v1.2.0")
    check("verify --key: a tag as the trusted ref -> refused (shared check)",
          rc == 1 and "not a branch" in log and called is None, log)
    rc, log, called = verify_key(keyed, tree_dir=tree)
    check("verify --key --tree: the tree that was signed -> passes (shared check)",
          rc == 0 and "tree: ok" in log, log)

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
