#!/usr/bin/env python3
"""
Tests for ci/scripts/atlas-evidence.sh and the OSV-Scanner download in
ci/scripts/osv-scan.sh. Refs: #167

On keel build 78 the OSV-Scanner download timed out, so no osv.json was
written, and atlas-evidence.sh reported "empty counts" as `ecosystems: {}`.
MyKronos takes `ecosystems` as a LIST and answered 422, so the run that was
meant to record "the scan did not complete" recorded nothing.

The script is EXECUTED under bash against a local HTTP server that applies the
platform's rule for `ecosystems`. `python -m pip` and `python -m
mykronos.atlas_counts` are stubbed so nothing is installed.

Needs bash, curl and git.

    python test/atlas-evidence.test.py
"""
import http.server
import json
import os
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "ci" / "scripts" / "atlas-evidence.sh"
OSV_SCAN = ROOT / "ci" / "scripts" / "osv-scan.sh"
failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


received = []


class Atlas(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        received.append(body)
        # SscsEvidenceSubmission.ecosystems is list[EcosystemEvidence]: a dict
        # is a 422 `list_type` there, exactly as here.
        if not isinstance(body.get("ecosystems"), list):
            self.send_response(422)
            self.end_headers()
            self.wfile.write(b'{"detail":[{"type":"list_type","loc":["body","ecosystems"]}]}')
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({
            "accepted": 1, "trust_score": None, "min_trust_score": 50,
            "below_minimum": False, "blocking": False,
            "dependency_count": 0, "vulnerable_dependency_count": 0,
        }).encode())

    def log_message(self, *args):
        pass


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


# `python` is the image's interpreter in the task; here it is a stub for the two
# module calls the script makes, and the real interpreter for anything else.
STUB = """#!/usr/bin/env bash
if [ "$1" = "-m" ] && [ "$2" = "pip" ]; then exit 0; fi
if [ "$1" = "-m" ] && [ "$2" = "mykronos.atlas_counts" ]; then printf '[]'; exit 0; fi
exec "{real}" "$@"
"""


def run_evidence(work, port):
    bindir = work / "bin"
    bindir.mkdir()
    stub = bindir / "python"
    real = shutil.which("python3") or sys.executable
    stub.write_text(STUB.replace("{real}", Path(real).as_posix()), newline="\n")
    stub.chmod(stub.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    if not shutil.which("python3"):
        (bindir / "python3").write_text(STUB.replace("{real}", Path(real).as_posix()), newline="\n")
        (bindir / "python3").chmod(0o755)
    env = dict(os.environ,
               PATH=f"{bindir.as_posix()}{os.pathsep}{os.environ.get('PATH', '')}",
               MYKRONOS_INGESTION_URL=f"http://127.0.0.1:{port}",
               MYKRONOS_INGESTION_TOKEN="test-token",
               MYKRONOS_REF="0" * 40,
               REPO_SLUG="owner/repo")
    return subprocess.run(["bash", SCRIPT.as_posix()], cwd=work, env=env,
                          capture_output=True, text=True, timeout=120)


port = free_port()
srv = http.server.HTTPServer(("127.0.0.1", port), Atlas)
threading.Thread(target=srv.serve_forever, daemon=True).start()

print("atlas-evidence.sh with no osv.json (the scan did not complete)")
with tempfile.TemporaryDirectory() as tmp:
    work = Path(tmp)
    repo = work / "repo"
    repo.mkdir()
    git = ["git", "-C", str(repo), "-c", "user.email=t@example.invalid", "-c", "user.name=t"]
    subprocess.run(git[:3] + ["init", "-q"], check=True)
    subprocess.run(git + ["commit", "-q", "--allow-empty", "-m", "x"], check=True)
    received.clear()
    proc = run_evidence(work, port)
    check("the script exits 0", proc.returncode == 0,
          f"(exit {proc.returncode}; stderr: {proc.stderr.strip()[-300:]!r})")
    check("one evidence record was posted", len(received) == 1, f"({len(received)} posted)")
    eco = received[-1].get("ecosystems") if received else None
    check("empty counts are an empty LIST, which the platform accepts",
          eco == [], f"(got {eco!r})")
    check("it says the scan did not complete", "no osv.json" in proc.stderr)

srv.shutdown()

# A GUARD, not evidence: it reads the script rather than running it. Build 78's
# osv-scan died on one `curl: (56) ... Connection timed out` downloading the
# scanner, and nothing retried it.
print("osv-scan.sh downloads OSV-Scanner with retries")
download = [line for line in OSV_SCAN.read_text().replace("\\\n", " ").splitlines()
            if "curl" in line and "osv-scanner_linux_amd64" in line]
check("the download is one curl command", len(download) == 1, f"({len(download)} found)")
line = download[0] if download else ""
for flag in ("--retry ", "--retry-all-errors", "--connect-timeout", "--max-time"):
    check(f"the download passes {flag.strip()}", flag in line)

if failures:
    print(f"\n{len(failures)} failed")
    sys.exit(1)
print("\nall passed")
