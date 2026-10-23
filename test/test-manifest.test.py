#!/usr/bin/env python3
"""
Tests for test/manifest.txt, the one list of test files. Refs: TheHub #60980

`./keel check` used to say "if it is green, CI is green" while running 2 of the
11 test files CI runs, and ci/scripts/ci-stage.sh named its 11 by hand, so a new
test/*.test.py that nobody wired in ran nowhere. Now both read
test/manifest.txt through scripts/test-manifest.py, and CI fails on a test file
the manifest does not name, or a manifest entry with no file behind it.

What is exercised, against the REAL scripts:

  * scripts/test-manifest.py check: an unlisted test file, a listed file that
    does not exist, a file listed twice, an unknown stage, and a missing
    manifest each exit 1 and name the offender; a consistent tree exits 0;
  * scripts/test-manifest.py run: every listed file runs, a failure in one does
    not hide the others, and a .js test with no node is a warning (CI) or a
    failure (`./keel check`), never a silent pass;
  * this repository: the manifest is consistent, it names every test file, and
    neither ci-stage.sh nor keel names a test file itself;
  * `./keel check`, run on a copy of this repository whose test/ holds only
    fixtures: an unlisted failing test turns it red and is named, a listed
    failing test turns it red and is named, `--quick` runs only the quick
    subset, and a missing node is a named warning and a non-zero exit.

    python test/test-manifest.test.py
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOL = ROOT / "scripts" / "test-manifest.py"
# Resolved from PATH, never a bare "bash": on Windows CreateProcess searches
# System32 first, and System32ash.exe is WSL, not the shell keel runs under.
BASH = shutil.which("bash") or "bash"
failures = []
# keel prints a check mark; a Windows console's cp1252 cannot encode it.
sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


PASS_PY = "import sys\nsys.exit(0)\n"
FAIL_PY = "import sys\nprint('deliberately failing')\nsys.exit(1)\n"
PASS_JS = "process.exit(0);\n"


def tree(files, manifest):
    """A temporary root holding test/<files> and test/manifest.txt (or none)."""
    tmp = Path(tempfile.mkdtemp(prefix="test-manifest-"))
    (tmp / "test").mkdir()
    for name, body in files.items():
        (tmp / "test" / name).write_text(body, encoding="utf-8")
    if manifest is not None:
        (tmp / "test" / "manifest.txt").write_text(manifest, encoding="utf-8")
    return tmp


def tool(root, *args, env=None):
    p = subprocess.run([sys.executable, TOOL.as_posix(), *args, "--root", root.as_posix()],
                       capture_output=True, text=True, encoding="utf-8",
                       errors="replace", env=env, timeout=120)
    return p.returncode, p.stdout + p.stderr


def path_without(*tools):
    """PATH minus every directory holding one of `tools`. None if that would
    also hide bash or python, which these tests need."""
    keep = []
    for d in os.environ.get("PATH", "").split(os.pathsep):
        if d and any(shutil.which(t, path=d) for t in tools):
            continue
        keep.append(d)
    path = os.pathsep.join(keep)
    if not (shutil.which("bash", path=path) and
            (shutil.which("python3", path=path) or shutil.which("python", path=path))):
        return None
    return path


print("test manifest")

# ── scripts/test-manifest.py check ──────────────────────────────────────────
if not TOOL.is_file():
    check("scripts/test-manifest.py exists", False, f"({TOOL} missing)")
else:
    t = tree({"a.test.py": PASS_PY, "b.test.js": PASS_JS},
             "test/a.test.py  test,quick  first\ntest/b.test.js  test  second\n")
    rc, out = tool(t, "check")
    check("a consistent manifest passes", rc == 0, out)
    shutil.rmtree(t, ignore_errors=True)

    t = tree({"a.test.py": PASS_PY, "orphan.test.py": FAIL_PY, "orphan2.test.js": PASS_JS},
             "test/a.test.py  test  first\n")
    rc, out = tool(t, "check")
    check("an unlisted .test.py fails and is named",
          rc == 1 and "test/orphan.test.py" in out, out)
    check("an unlisted .test.js is named too", "test/orphan2.test.js" in out, out)
    shutil.rmtree(t, ignore_errors=True)

    t = tree({"a.test.py": PASS_PY},
             "test/a.test.py  test  first\ntest/gone.test.py  lint  vanished\n")
    rc, out = tool(t, "check")
    check("an entry with no file fails and is named",
          rc == 1 and "test/gone.test.py" in out, out)
    shutil.rmtree(t, ignore_errors=True)

    t = tree({"a.test.py": PASS_PY},
             "test/a.test.py  test  first\ntest/a.test.py  lint  again\n")
    rc, out = tool(t, "check")
    check("a file listed twice fails (no test runs twice)",
          rc == 1 and "test/a.test.py" in out, out)
    shutil.rmtree(t, ignore_errors=True)

    t = tree({"a.test.py": PASS_PY}, "test/a.test.py  nightly  first\n")
    rc, out = tool(t, "check")
    check("an unknown stage fails (it would run in no stage)",
          rc == 1 and "nightly" in out, out)
    shutil.rmtree(t, ignore_errors=True)

    t = tree({"a.test.py": PASS_PY}, "test/a.test.py  test,lint  both\n")
    rc, out = tool(t, "check")
    check("an entry in two stages fails", rc == 1, out)
    shutil.rmtree(t, ignore_errors=True)

    t = tree({"a.test.py": PASS_PY}, None)
    rc, out = tool(t, "check")
    check("no manifest at all fails", rc == 1 and "manifest.txt" in out, out)
    shutil.rmtree(t, ignore_errors=True)

    # ── run ──────────────────────────────────────────────────────────────────
    t = tree({"a.test.py": FAIL_PY, "b.test.py": PASS_PY},
             "test/a.test.py  test  first\ntest/b.test.py  test  second\n"
             "test/c.test.py  lint  other stage\n")
    (t / "test" / "c.test.py").write_text(FAIL_PY, encoding="utf-8")
    rc, out = tool(t, "run", "--stage", "test")
    check("run: a failing listed test fails the stage", rc == 1, out)
    check("run: a failure does not stop the files after it",
          "second" in out and "test/b.test.py" in out, out)
    check("run: the failure is named in the summary",
          re.search(r"FAILED.*test/a\.test\.py", out) is not None, out)
    check("run --stage test does not run the lint entry", "other stage" not in out, out)
    rc, out = tool(t, "run", "--stage", "test", "--quiet")
    check("run --quiet: one ok/warn line per file",
          "ok: test/b.test.py" in out and "warn: test/a.test.py" in out
          and "deliberately failing" not in out, out)
    shutil.rmtree(t, ignore_errors=True)

    no_node = path_without("node")
    t = tree({"a.test.py": PASS_PY, "b.test.js": PASS_JS},
             "test/a.test.py  test  first\ntest/b.test.js  test  second\n")
    if no_node is None:
        print("  [skip] cannot hide node on this host without hiding bash/python")
    else:
        env = dict(os.environ, PATH=no_node)
        rc, out = tool(t, "run", "--stage", "test", "--node-missing", "fail", "--quiet", env=env)
        check("no node, --node-missing fail: named warning, non-zero exit",
              rc != 0 and "warn: node missing, skipped test/b.test.js" in out, out)
        rc, out = tool(t, "run", "--stage", "test", "--node-missing", "skip", env=env)
        check("no node, --node-missing skip (CI): said, and not a failure",
              rc == 0 and "test/b.test.js" in out and "node" in out, out)
    shutil.rmtree(t, ignore_errors=True)

# ── this repository ─────────────────────────────────────────────────────────
manifest = ROOT / "test" / "manifest.txt"
check("test/manifest.txt exists", manifest.is_file())
if TOOL.is_file() and manifest.is_file():
    rc, out = tool(ROOT, "check")
    check("this repository's manifest is consistent", rc == 0, out)
    rc, out = tool(ROOT, "list")
    listed = sorted(out.split())
    on_disk = sorted(p.relative_to(ROOT).as_posix()
                     for p in list((ROOT / "test").glob("*.test.py"))
                     + list((ROOT / "test").glob("*.test.js")))
    check("it names every test file on disk, each once",
          listed == on_disk, f"listed={listed} on_disk={on_disk}")
    lint = tool(ROOT, "list", "--stage", "lint")[1].split()
    test = tool(ROOT, "list", "--stage", "test")[1].split()
    check("every entry is in exactly one CI stage",
          sorted(lint + test) == on_disk and not set(lint) & set(test),
          f"lint={lint} test={test}")

named = re.compile(r"test/[\w.-]+\.test\.(py|js)")
stage_sh = (ROOT / "ci" / "scripts" / "ci-stage.sh").read_text(encoding="utf-8")
keel_sh = (ROOT / "keel").read_text(encoding="utf-8")
code = lambda s: "\n".join(l for l in s.splitlines() if not l.lstrip().startswith("#"))
check("ci-stage.sh names no test file itself",
      named.search(code(stage_sh)) is None, str([m.group(0) for m in named.finditer(code(stage_sh))]))
check("keel names no test file itself",
      named.search(code(keel_sh)) is None, str([m.group(0) for m in named.finditer(code(keel_sh))]))
check("ci-stage.sh lint stage checks the manifest and runs its lint entries",
      "scripts/test-manifest.py check" in stage_sh
      and re.search(r"scripts/test-manifest\.py run --stage lint", stage_sh) is not None)
check("ci-stage.sh test stage runs its test entries",
      re.search(r"scripts/test-manifest\.py run --stage test", stage_sh) is not None)

# ── ./keel check on a copy whose test/ holds only fixtures ──────────────────
def keel_copy():
    tmp = Path(tempfile.mkdtemp(prefix="keel-check-"))
    files = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True,
                           check=True).stdout.decode("utf-8").split("\0")
    for f in files:
        if not f or f.startswith("test/"):
            continue
        src = ROOT / f
        if not src.is_file():
            continue
        dst = tmp / f
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
    (tmp / "test").mkdir()
    # The guard self-test is not what is under test here, and it takes minutes
    # on Windows. It runs for real in CI and in keel check on the real tree.
    (tmp / ".claude" / "hooks" / "selftest.sh").write_text("#!/usr/bin/env bash\nexit 0\n")
    return tmp


def keel(root, *args, path=None):
    stubs = root / ".stubs"
    stubs.mkdir(exist_ok=True)
    # Never start a container from a test: docker here reports "not running",
    # so the gitleaks-allowlist step skips (a warning) instead of pulling an
    # image. A stub, not path_without: on ubuntu-latest docker shares /usr/bin
    # with bash. gitleaks, where installed, is hidden by path_without.
    (stubs / "docker").write_text("#!/usr/bin/env bash\nexit 1\n")
    (stubs / "docker").chmod(0o755)
    env = dict(os.environ, PATH=stubs.as_posix() + os.pathsep + (path or os.environ["PATH"]))
    p = subprocess.run([BASH, (root / "keel").as_posix(), "check", *args],
                       capture_output=True, text=True, encoding="utf-8",
                       errors="replace", env=env, timeout=600)
    return p.returncode, p.stdout + p.stderr


base_path = path_without("gitleaks") if shutil.which("gitleaks") else os.environ["PATH"]
if base_path is None:
    print("  [skip] keel check cases: cannot hide gitleaks on this host without "
          "hiding bash/python (it would scan a copy with no .git)")
else:
    k = keel_copy()
    try:
        t = k / "test"
        (t / "pass.test.py").write_text(PASS_PY, encoding="utf-8")
        (t / "manifest.txt").write_text("test/pass.test.py  test,quick  passing\n",
                                        encoding="utf-8")
        rc, base = keel(k, path=base_path)
        check("keel check: green with one passing listed test",
              rc == 0 and "ok: test/pass.test.py" in base, base)

        (t / "fail.test.py").write_text(FAIL_PY, encoding="utf-8")
        rc, out = keel(k, path=base_path)
        check("keel check: an unlisted failing test turns it red, and is named",
              rc != 0 and "test/fail.test.py" in out, out)

        with open(t / "manifest.txt", "a", encoding="utf-8") as fh:
            fh.write("test/fail.test.py  lint  deliberately failing\n")
        rc, out = keel(k, path=base_path)
        check("keel check: a listed failing test turns it red, and is named",
              rc != 0 and "warn: test/fail.test.py" in out, out)

        rc, out = keel(k, "--quick", path=base_path)
        check("keel check --quick: runs only the quick subset",
              rc == 0 and "ok: test/pass.test.py" in out and "fail.test.py" not in out, out)

        (t / "fail.test.py").unlink()
        (t / "manifest.txt").write_text("test/pass.test.py  test,quick  passing\n"
                                        "test/js.test.js  test  js\n", encoding="utf-8")
        (t / "js.test.js").write_text(PASS_JS, encoding="utf-8")
        nn = path_without("gitleaks", "node")
        if nn is None:
            print("  [skip] cannot hide node on this host without hiding bash/python")
        else:
            rc, out = keel(k, path=nn)
            check("keel check: no node is a named warning and a non-zero exit",
                  rc != 0 and "warn: node missing, skipped test/js.test.js" in out, out)
    finally:
        shutil.rmtree(k, ignore_errors=True)

print()
if failures:
    print(f"{len(failures)} failed")
    sys.exit(1)
print("all passed")
