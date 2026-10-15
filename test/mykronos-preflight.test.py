#!/usr/bin/env python3
"""
Tests for ci/scripts/mykronos-preflight.sh, EXECUTED under bash against a real
local HTTP server.

On 2026-10-15 one 20s timeout reaching Mykronos failed iac, mykronos-sast,
mykronos-secrets and mykronos-atlas together, and they stayed red until the
next commit. The preflight must re-try being unable to ask, and never the
answer:

  * a server that comes up a few seconds late is reached (exit 0);
  * a 401 -- the token is wrong -- fails at once, without retrying.

Needs bash and curl.

    python test/mykronos-preflight.test.py
"""
import http.server
import os
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "ci" / "scripts" / "mykronos-preflight.sh"
failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


class Health(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        ok = self.headers.get("Authorization") == "Bearer good"
        self.send_response(200 if ok else 401)
        self.end_headers()
        self.wfile.write(b"{}")

    def log_message(self, *args):
        pass


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def serve(port, delay):
    def run():
        time.sleep(delay)
        srv = http.server.HTTPServer(("127.0.0.1", port), Health)
        srv.timeout = 0.5
        end = time.time() + 30
        while time.time() < end:
            srv.handle_request()
        srv.server_close()
    threading.Thread(target=run, daemon=True).start()


def preflight(port, token):
    env = dict(os.environ,
               MYKRONOS_INGESTION_URL=f"http://127.0.0.1:{port}",
               MYKRONOS_INGESTION_TOKEN=token)
    start = time.time()
    proc = subprocess.run(["bash", str(SCRIPT)], env=env,
                          capture_output=True, text=True, timeout=120)
    return proc.returncode, time.time() - start, proc.stderr


port = free_port()
serve(port, 4)
code, _, err = preflight(port, "good")
check("a server that is up 4s late is reached", code == 0, f"exit={code} {err}")

port = free_port()
serve(port, 0)
time.sleep(1)
code, took, err = preflight(port, "bad")
check("a rejected token fails the step", code != 0, f"exit={code}")
check("a rejected token is not retried", took < 4, f"took {took:.1f}s")

sys.exit(1 if failures else 0)
