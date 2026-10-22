#!/usr/bin/env python3
"""
Tests for the container-scan lane, ci/scripts/trivy.sh. Refs: TheHub #60935

Runs the REAL script under bash with trivy and its download plumbing (curl,
sha256sum, tar, install) stubbed on PATH, so what is tested is the script's own
decisions:

  * IMAGE_REF unset or empty -- nothing to scan. The lane FAILS (it used to exit
    0 with a NOT-A-PASS banner), says why, and never downloads or runs trivy;
  * IMAGE_REF set and trivy finds nothing -- passes;
  * IMAGE_REF set and trivy reports findings (exit 1) -- fails;
  * IMAGE_REF set but the pins are missing -- fails before downloading anything.

    python test/trivy-gate.test.py
"""
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "ci" / "scripts" / "trivy.sh"
failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def run(image_ref=None, trivy_rc=0, pins=True):
    """Run trivy.sh. Returns (rc, output, trivy argv, whether curl was called)."""
    tmp = Path(tempfile.mkdtemp(prefix="trivy-gate-"))
    try:
        (tmp / "repo").mkdir()
        (tmp / "container-results").mkdir()
        stubs = tmp / "stubs"
        stubs.mkdir()
        argv_log = tmp / "trivy-argv.txt"
        curl_log = tmp / "curl-called.txt"
        (stubs / "trivy").write_text(
            "#!/usr/bin/env bash\n"
            'if [ "${1:-}" = "--version" ]; then echo "trivy-stub"; exit 0; fi\n'
            f'printf "%s\\n" "$@" > "{argv_log.as_posix()}"\n'
            f"exit {trivy_rc}\n")
        (stubs / "curl").write_text(
            "#!/usr/bin/env bash\n"
            f': > "{curl_log.as_posix()}"\n'
            'while [ $# -gt 0 ]; do [ "$1" = "-o" ] && { : > "$2"; shift; }; shift; done\n')
        (stubs / "sha256sum").write_text("#!/usr/bin/env bash\ncat >/dev/null; exit 0\n")
        (stubs / "tar").write_text("#!/usr/bin/env bash\nexit 0\n")
        (stubs / "install").write_text("#!/usr/bin/env bash\nexit 0\n")
        for f in stubs.iterdir():
            f.chmod(f.stat().st_mode | stat.S_IEXEC)
        env = dict(os.environ,
                   PATH=stubs.as_posix() + os.pathsep + os.environ.get("PATH", ""))
        for k in ("IMAGE_REF", "TRIVY_VERSION", "TRIVY_SHA256"):
            env.pop(k, None)
        if pins:
            env["TRIVY_VERSION"] = "0.0.0-test"
            env["TRIVY_SHA256"] = "0" * 64
        if image_ref is not None:
            env["IMAGE_REF"] = image_ref
        p = subprocess.run(["bash", SCRIPT.as_posix()], cwd=tmp, env=env,
                           capture_output=True, text=True, timeout=60)
        argv = argv_log.read_text().split() if argv_log.is_file() else []
        return p.returncode, p.stdout + p.stderr, argv, curl_log.is_file()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


print("trivy gate")

# ── Nothing to scan is a FAILURE (TheHub #60935) ─────────────────────────────
rc, out, argv, curled = run()
check("IMAGE_REF unset: the lane FAILS", rc != 0, f"rc={rc}\n{out[-400:]}")
check("IMAGE_REF unset: says nothing was scanned",
      "IMAGE_REF is not set" in out and "FAILING" in out, out[-400:])
check("IMAGE_REF unset: trivy is never downloaded or run", not curled and not argv,
      f"curled={curled} argv={argv}")

rc, out, argv, _ = run(image_ref="")
check("IMAGE_REF empty: the lane FAILS too", rc != 0, f"rc={rc}")

rc, out, argv, _ = run(pins=False)
check("IMAGE_REF unset and no pins: fails for the no-subject reason, not the pin",
      rc != 0 and "IMAGE_REF is not set" in out, out[-400:])

# ── An image to scan ─────────────────────────────────────────────────────────
rc, out, argv, _ = run(image_ref="registry.example/app@sha256:" + "a" * 64)
check("IMAGE_REF set, nothing found: passes", rc == 0, f"rc={rc}\n{out[-400:]}")
check("IMAGE_REF set: trivy scans that image and gates with --exit-code 1",
      "image" in argv and "--exit-code" in argv and any("registry.example/app" in a for a in argv),
      f"argv={argv}")

rc, out, argv, _ = run(image_ref="registry.example/app:1", trivy_rc=1)
check("IMAGE_REF set, findings: fails", rc != 0, f"rc={rc}")

rc, out, argv, curled = run(image_ref="registry.example/app:1", pins=False)
check("IMAGE_REF set, no pins: fails before downloading", rc != 0 and not curled,
      f"rc={rc} curled={curled}")

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)
print("\nall passed")
