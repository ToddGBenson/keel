#!/usr/bin/env python3
"""
Tests for the SCA lane's gate, ci/scripts/grype.sh. Refs: #133

Runs the REAL script under bash with grype and its download plumbing (curl,
sha256sum, tar, install) stubbed on PATH, so what is tested is the script's own
decisions:

  * GATE unset or "true" -- the `sca` job: a finding at or above the cutoff fails
    the lane, exactly as before this change, and `--fail-on` is passed;
  * GATE="false" -- the `mykronos-sca` upload lane: findings do NOT fail the step,
    the SARIF is still written for the upload, and `--fail-on` is not passed;
  * GATE="false" and grype itself errors: the step still FAILS. A broken scanner
    must not read as a clean one;
  * GATE set to anything else fails, so a typo cannot switch the gate off;
  * NO dependency manifest fails in both modes, and grype is never run: a scan
    of nothing is not a pass (TheHub #60935, the rule `iac` follows).

    python test/grype-gate.test.py
"""
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "ci" / "scripts" / "grype.sh"
failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def run(n_findings, gate=None, grype_errors=False, manifest=True):
    """Run grype.sh. The stub grype behaves like the real one: it writes the SARIF
    to --file, exits 1 when --fail-on is given and there are findings, and exits 1
    WITHOUT a SARIF when told to simulate a tool error."""
    tmp = Path(tempfile.mkdtemp(prefix="grype-gate-"))
    try:
        (tmp / "repo").mkdir()
        if manifest:
            (tmp / "repo" / "requirements.txt").write_text("pyyaml==6.0.3\n")
        else:
            # Something to find that is NOT a manifest, and a manifest-named file
            # under .git, which the find prunes.
            (tmp / "repo" / "README.md").write_text("no dependencies\n")
            (tmp / "repo" / ".git").mkdir()
            (tmp / "repo" / ".git" / "package.json").write_text("{}\n")
        (tmp / "sca-results").mkdir()
        stubs = tmp / "stubs"
        stubs.mkdir()
        sarif = {"version": "2.1.0", "runs": [{
            "tool": {"driver": {"name": "grype"}},
            "results": [{"ruleId": f"CVE-0000-{i}", "level": "error",
                         "message": {"text": "x"}} for i in range(n_findings)]}]}
        (tmp / "stub-sarif.json").write_text(json.dumps(sarif))
        argv_log = tmp / "grype-argv.txt"
        real_py = Path(shutil.which("python3") or sys.executable).as_posix()
        (stubs / "grype").write_text(
            "#!/usr/bin/env bash\n"
            'if [ "${1:-}" = "version" ]; then echo "grype-stub"; exit 0; fi\n'
            f'printf "%s\\n" "$@" > "{argv_log.as_posix()}"\n'
            + ('echo "grype: failed to load vulnerability db" >&2; exit 1\n'
               if grype_errors else "")
            + 'out=""; fail=0\n'
            'while [ $# -gt 0 ]; do case "$1" in\n'
            '  --file) out="$2"; shift 2;;\n'
            '  --fail-on) fail=1; shift 2;;\n'
            '  *) shift;;\n'
            "esac; done\n"
            f'cp "{(tmp / "stub-sarif.json").as_posix()}" "$out"\n'
            f'if [ "$fail" -eq 1 ] && [ {n_findings} -gt 0 ]; then exit 1; fi\n'
            "exit 0\n")
        (stubs / "curl").write_text(
            "#!/usr/bin/env bash\n"
            'while [ $# -gt 0 ]; do [ "$1" = "-o" ] && { : > "$2"; shift; }; shift; done\n')
        (stubs / "sha256sum").write_text("#!/usr/bin/env bash\ncat >/dev/null; exit 0\n")
        (stubs / "tar").write_text("#!/usr/bin/env bash\nexit 0\n")
        (stubs / "install").write_text("#!/usr/bin/env bash\nexit 0\n")
        (stubs / "python3").write_text(f'#!/usr/bin/env bash\nexec "{real_py}" "$@"\n')
        for f in stubs.iterdir():
            f.chmod(f.stat().st_mode | stat.S_IEXEC)
        env = dict(os.environ, GRYPE_VERSION="0.0.0-test", GRYPE_SHA256="0" * 64,
                   SEVERITY_CUTOFF="high",
                   PATH=stubs.as_posix() + os.pathsep + os.environ.get("PATH", ""))
        env.pop("GATE", None)
        if gate is not None:
            env["GATE"] = gate
        p = subprocess.run(["bash", SCRIPT.as_posix()], cwd=tmp, env=env,
                           capture_output=True, text=True, timeout=60)
        argv = argv_log.read_text().split() if argv_log.is_file() else []
        sarif_written = (tmp / "sca-results" / "grype.sarif").is_file()
        return p.returncode, p.stdout + p.stderr, argv, sarif_written
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


print("grype gate")

# ── The `sca` job: gate unchanged ────────────────────────────────────────────
rc, out, argv, _ = run(3)
check("GATE unset: a finding at the cutoff fails the lane (unchanged)", rc != 0, f"rc={rc}")
check("GATE unset: --fail-on high is passed to grype",
      "--fail-on" in argv and "high" in argv, f"argv={argv}")

rc, out, argv, _ = run(3, gate="true")
check("GATE=true: a finding at the cutoff fails the lane", rc != 0, f"rc={rc}")

rc, out, argv, _ = run(0)
check("GATE unset: no findings passes", rc == 0, f"rc={rc}\n{out[-400:]}")

# ── The `mykronos-sca` upload lane: report, do not gate ──────────────────────
rc, out, argv, sarif = run(3, gate="false")
check("GATE=false: findings do not fail the step", rc == 0, f"rc={rc}\n{out[-400:]}")
check("GATE=false: the SARIF is still written for the upload", sarif)
check("GATE=false: --fail-on is NOT passed to grype", "--fail-on" not in argv, f"argv={argv}")

rc, out, argv, sarif = run(0, gate="false", grype_errors=True)
check("GATE=false: a grype error still FAILS the step (no vacuous pass)", rc != 0, f"rc={rc}")
check("GATE=false: and says it was a scan failure, not findings",
      "scan failure" in out, out[-400:])

# ── Nothing to scan is a FAILURE (TheHub #60935) ─────────────────────────────
rc, out, argv, sarif = run(0, manifest=False)
check("no manifest, GATE unset: the lane FAILS", rc != 0, f"rc={rc}\n{out[-400:]}")
check("no manifest: grype is never run", not argv, f"argv={argv}")
check("no manifest: says nothing was scanned, not a plumbing error",
      "no dependency manifests found" in out and "FAILING" in out, out[-400:])
check("no manifest: no SARIF is fabricated", not sarif)

rc, out, argv, _ = run(0, gate="false", manifest=False)
check("no manifest, GATE=false: the upload lane FAILS too", rc != 0, f"rc={rc}")

# ── A typo must not disable the gate ────────────────────────────────────────
rc, out, argv, _ = run(3, gate="flase")
check("GATE=<typo>: refused, not treated as false", rc != 0 and not argv, f"rc={rc} argv={argv}")

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)
print("\nall passed")
