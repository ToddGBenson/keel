#!/usr/bin/env python3
"""
scripts/test-gitleaks-allowlist.sh starts every gitleaks container capped.
Refs: keel #147 review, TheHub #60980

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

print()
if failures:
    print(f"{len(failures)} failed")
    sys.exit(1)
print("all passed")
