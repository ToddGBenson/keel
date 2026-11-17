#!/usr/bin/env python3
"""
scripts/test-gitleaks-allowlist.sh starts every gitleaks container capped.
Refs: keel #147 review, TheHub #60980, TheHub #61098

On 2026-10-23 eight uncapped test containers on the operator's host took TheHub
production down. `./keel check` runs scripts/test-gitleaks-allowlist.sh, which,
when gitleaks is not installed, scans through `docker run`. Every such
container must carry a CPU and a memory cap (--cpus 1 --memory 1g), so a
developer running `./keel check` can never starve the services on the host.

What is exercised, against the REAL script: docker is a stub on PATH that
records its arguments and starts nothing; gitleaks is hidden from PATH so the
docker branch is taken. The script's own verdict is ignored (the stub writes
no report), only the docker arguments are checked.

    python test/gitleaks-allowlist.test.py
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "test-gitleaks-allowlist.sh"
# Resolved from PATH, never a bare "bash": on Windows CreateProcess searches
# System32 first, and System32's bash.exe is WSL.
BASH = shutil.which("bash") or "bash"
GL_IMAGE = "zricethezav/gitleaks:"
failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def path_without(*tools):
    keep = [d for d in os.environ.get("PATH", "").split(os.pathsep)
            if d and not any(shutil.which(t, path=d) for t in tools)]
    return os.pathsep.join(keep)


print("gitleaks allowlist test: containers are capped")

tmp = Path(tempfile.mkdtemp(prefix="gl-cap-"))
try:
    stubs = tmp / "stubs"
    stubs.mkdir()
    log = tmp / "docker.log"
    # `docker version` succeeds so the script takes the docker branch; every
    # other call is recorded, one argument per line, and starts nothing.
    (stubs / "docker").write_text(
        "#!/usr/bin/env bash\n"
        "[ \"$1\" = version ] && exit 0\n"
        "printf '%s\\n' \"$@\" >> \"$DOCKER_LOG\"\n"
        "printf -- '--END--\\n' >> \"$DOCKER_LOG\"\n"
        "exit 0\n", newline="\n")
    (stubs / "docker").chmod(0o755)
    path = path_without("gitleaks") if shutil.which("gitleaks") else os.environ["PATH"]
    env = dict(os.environ, PATH=stubs.as_posix() + os.pathsep + path,
               DOCKER_LOG=log.as_posix())
    p = subprocess.run([BASH, SCRIPT.as_posix()], cwd=ROOT, capture_output=True,
                       text=True, encoding="utf-8", errors="replace", env=env,
                       timeout=300)
    out = p.stdout + p.stderr
    raw = log.read_text(encoding="utf-8") if log.is_file() else ""
    calls = [c.strip("\n").split("\n") for c in raw.split("--END--\n") if c.strip()]
    runs = [c for c in calls if c and c[0] == "run"]

    check("the script scans through docker twice (canary, then this repo)",
          len(runs) == 2, f"(saw {len(runs)} docker run call(s))\n{out}")
    for i, args in enumerate(runs, 1):
        img = next((n for n, a in enumerate(args) if a.startswith(GL_IMAGE)), len(args))
        opts = args[:img]  # docker options only; what follows the image is gitleaks'
        pairs = list(zip(opts, opts[1:]))
        check(f"docker run #{i} is removed on exit (--rm)", "--rm" in opts, f"({opts})")
        check(f"docker run #{i} is CPU-capped (--cpus 1)",
              ("--cpus", "1") in pairs or "--cpus=1" in opts, f"({opts})")
        check(f"docker run #{i} is memory-capped (--memory 1g)",
              ("--memory", "1g") in pairs or "--memory=1g" in opts, f"({opts})")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

# ── A copy with no .git, run from another directory (TheHub #61098) ─────────
# test/test-manifest.test.py runs `./keel check` on a copy of this repository
# that has no .git. The script began `cd "$(git rev-parse --show-toplevel)" ||
# exit 1`; outside a work tree that is `cd ""`, which bash 5.3 rejects ("line 22:
# cd: null directory"). ubuntu-latest moved to ubuntu-26.04, which ships bash
# 5.3 (5.2 tolerated it), so the script exited 1 with neither verdict
# and keel check went red on every Unit results run since 2026-10-28. It must
# find its repository from its own location instead, and, with no git history
# to read, scan the files (--no-git) rather than report a vacuous "clean".
print("gitleaks allowlist test: a copy with no .git")
tmp = Path(tempfile.mkdtemp(prefix="gl-nogit-"))
try:
    copy = tmp / "copy"
    (copy / "scripts").mkdir(parents=True)
    shutil.copy2(SCRIPT, copy / "scripts" / SCRIPT.name)
    shutil.copy2(ROOT / ".gitleaks.toml", copy / ".gitleaks.toml")
    elsewhere = tmp / "elsewhere"
    elsewhere.mkdir()
    stubs = tmp / "stubs"
    stubs.mkdir()
    log = tmp / "gitleaks.log"
    # A gitleaks that finds the two planted secrets only when the canary carries
    # this repository's .gitleaks.toml, and nothing in the repository scan.
    (stubs / "gitleaks").write_text(
        "#!/usr/bin/env bash\n"
        "src=; rep=\n"
        "for a in \"$@\"; do case \"$prev\" in --source) src=$a;; --report-path) rep=$a;; esac; prev=$a; done\n"
        "printf '%s\n' \"$*\" >> \"$GL_LOG\"\n"
        "if [ -f \"$src/planted.py\" ] && [ -f \"$src/.gitleaks.toml\" ]; then echo '[{},{}]' > \"$rep\"\n"
        "else echo '[]' > \"$rep\"; fi\n"
        "exit 0\n", newline="\n")
    (stubs / "gitleaks").chmod(0o755)
    env = dict(os.environ, PATH=stubs.as_posix() + os.pathsep + os.environ["PATH"],
               GL_LOG=log.as_posix())
    p = subprocess.run([BASH, (copy / "scripts" / SCRIPT.name).as_posix()],
                       cwd=elsewhere, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", env=env, timeout=300)
    out = p.stdout + p.stderr
    calls = log.read_text(encoding="utf-8").splitlines() if log.is_file() else []
    check("no .git: the script exits 0", p.returncode == 0, f"(exit {p.returncode})\n{out}")
    check("no .git: the allowlist is verified in BOTH directions",
          "BOTH directions" in out, out)
    check("no .git: the repository scan reads the files (--no-git), not a missing history",
          len(calls) == 2 and "--no-git" in calls[1].split() and "--no-git" not in calls[0].split(),
          f"({calls})")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

# ── A missing or unparsable report is an error, not "clean" (TheHub #61237) ──
# count_findings used to echo 0 for a missing, empty or unparsable report, so a
# gitleaks invocation that failed and wrote nothing satisfied step 2 ("the
# fixture must NOT be reported"). A valid `[]` is the only clean answer.
print("gitleaks allowlist test: a report that is not there fails, never reads clean")


def run_with_stub(body):
    """Run the real script with a gitleaks stub whose body decides the report."""
    t = Path(tempfile.mkdtemp(prefix="gl-report-"))
    try:
        stubs = t / "stubs"
        stubs.mkdir()
        (stubs / "gitleaks").write_text(
            "#!/usr/bin/env bash\n"
            "src=; rep=\n"
            "for a in \"$@\"; do case \"$prev\" in --source) src=$a;; --report-path) rep=$a;; esac; prev=$a; done\n"
            + body + "exit 0\n", newline="\n")
        (stubs / "gitleaks").chmod(0o755)
        env = dict(os.environ, PATH=stubs.as_posix() + os.pathsep + os.environ["PATH"])
        r = subprocess.run([BASH, SCRIPT.as_posix()], cwd=ROOT, capture_output=True,
                           text=True, encoding="utf-8", errors="replace", env=env,
                           timeout=300)
        return r.returncode, r.stdout + r.stderr
    finally:
        shutil.rmtree(t, ignore_errors=True)


FOUND = 'if [ -f "$src/planted.py" ]; then echo \'[{},{}]\' > "$rep"; else %s; fi\n'
for label, repo_report in (
        ("no report file at all", ":"),
        ("an empty report file", ': > "$rep"'),
        ("a report that is not JSON", 'echo "fatal: not a git repository" > "$rep"')):
    code, out = run_with_stub(FOUND % repo_report)
    check(f"{label}: the script exits non-zero", code != 0, f"(exit {code})\n{out}")
    check(f"{label}: it is not reported as a clean repository",
          "repository clean" not in out and "verified in BOTH" not in out, out)
code, out = run_with_stub(FOUND % "echo '[]' > \"$rep\"")
check("a valid empty list [] is still a clean repository", code == 0 and "repository clean" in out,
      f"(exit {code})\n{out}")
code, out = run_with_stub(": # canary report never written\n")
check("no canary report: the script exits non-zero", code != 0, f"(exit {code})\n{out}")

# ── The real scanner, --no-git, on a copy with no .git (TheHub #61237) ───────
# Every check above uses a stub. This one runs the real gitleaks (binary, else
# a capped container, exactly as the script does) and skips HONESTLY, with a
# reason and no [ok], when neither is available.
print("gitleaks allowlist test: the real scanner on a copy with no .git")
have_real = bool(shutil.which("gitleaks"))
if not have_real and shutil.which("docker"):
    have_real = subprocess.run(["docker", "version"], capture_output=True).returncode == 0
if not have_real:
    print("  [skip] neither gitleaks nor a working docker is available: "
          "the real --no-git path was NOT exercised this run")
else:
    tmp = Path(tempfile.mkdtemp(prefix="gl-real-"))
    try:
        copy = tmp / "copy"
        shutil.copytree(ROOT, copy, ignore=shutil.ignore_patterns(".git", "node_modules"))
        p = subprocess.run([BASH, (copy / "scripts" / SCRIPT.name).as_posix()],
                           cwd=tmp, capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=600)
        out = p.stdout + p.stderr
        check("real gitleaks, no .git: planted secrets found, allowlist verified",
              p.returncode == 0 and "BOTH directions" in out, f"(exit {p.returncode})\n{out}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

print()
if failures:
    print(f"{len(failures)} failed")
    sys.exit(1)
print("all passed")
