#!/usr/bin/env python3
"""
dailycheck — a daily health and security posture report for one machine.

    python src/dailycheck.py                 human-readable report
    python src/dailycheck.py --json          machine-readable
    python src/dailycheck.py --out ~/reports write the JSON report there

Exit code: 0 = nothing failed, 1 = at least one FAIL. Cron-friendly.

── DESIGN CONSTRAINTS, from the G2 threat model ─────────────────────────────
This module deliberately has NO network capability. There is no socket import, no HTTP
client, and nothing that sends a packet to another host (T1). "Check my home network" most
naturally reads as *scan the network*, and an unattended daily port-scan of a LAN can trip an
IDS, breach an ISP's AUP, and is exactly what malware looks like. Device inventory (a later
story) reads the OS neighbour table — passive, no packets.

Everything is read-only and unprivileged. A probe that cannot run reports SKIPPED, never
PASS (T3) — a check that quietly claims success it did not observe is worse than no check.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path

SCHEMA = "dailycheck/1"

# Explicit numbers, because "unhealthy" is not a vibe (U5).
THRESHOLDS = {
    "disk_percent": 85,      # warn above this
    "backup_age_hours": 48,
    "cert_expiry_days": 30,
}

PROBE_TIMEOUT = 5  # seconds; a hanging probe must not stall the daily run (T5)


class ProbeUnavailable(Exception):
    """Raised when a probe cannot run — missing tool, missing permission, wrong OS.

    Distinct from a failure: not knowing is not the same as being broken."""


@dataclass
class Result:
    name: str
    status: str      # PASS | WARN | FAIL | SKIPPED
    detail: str = ""
    value: float | None = None


@dataclass
class Report:
    results: list[Result]
    host: str
    system: str


# ── probe plumbing ───────────────────────────────────────────────────────────
def safe_probe(name: str, fn) -> Result:
    """Run a probe so that no failure mode can be mistaken for success (T3, T5)."""
    try:
        return fn()
    except ProbeUnavailable as e:
        return Result(name, "SKIPPED", f"unavailable: {e}")
    except subprocess.TimeoutExpired:
        return Result(name, "SKIPPED", f"probe timed out after {PROBE_TIMEOUT}s")
    except Exception as e:  # noqa: BLE001 (#13) — deliberate: a broken probe must not
        # end the daily run. This is the T5 control, not an oversight; see the threat model.
        return Result(name, "SKIPPED", f"probe error: {type(e).__name__}: {e}")


def _run(argv: list[str]) -> str:
    """Run a fixed argv with a timeout. Never shell=True, never interpolated input (T4)."""
    if not shutil.which(argv[0]):
        raise ProbeUnavailable(f"{argv[0]} not found")
    proc = subprocess.run(argv, capture_output=True, text=True, timeout=PROBE_TIMEOUT)
    return proc.stdout


def evaluate_threshold(name: str, value: float, limit: float) -> Result:
    status = "WARN" if value > limit else "PASS"
    return Result(name, status, f"{value:g} (threshold {limit:g})", float(value))


# ── the checks ───────────────────────────────────────────────────────────────
def check_disk() -> Result:
    usage = shutil.disk_usage(Path.home().anchor or "/")
    pct = usage.used / usage.total * 100
    r = evaluate_threshold("disk space", round(pct, 1), THRESHOLDS["disk_percent"])
    free_gb = usage.free / 1e9
    r.detail = f"{pct:.1f}% used, {free_gb:.1f} GB free (warn above {THRESHOLDS['disk_percent']}%)"
    return r


def check_uptime_reboot_pending() -> Result:
    """A machine that has not rebooted in a long time is often carrying unapplied updates."""
    system = platform.system()
    if system == "Linux" and Path("/var/run/reboot-required").exists():
        return Result("reboot pending", "WARN", "a reboot is required to finish updates")
    if system == "Linux":
        return Result("reboot pending", "PASS", "no reboot flagged")
    raise ProbeUnavailable(f"no unprivileged reboot-pending signal on {system}")


def check_firewall() -> Result:
    system = platform.system()
    if system == "Windows":
        out = _run(["netsh", "advfirewall", "show", "allprofiles", "state"])
        states = [l for l in out.splitlines() if "State" in l]
        if not states:
            raise ProbeUnavailable("could not read firewall state")
        if any("OFF" in s.upper() for s in states):
            return Result("firewall", "FAIL", "at least one profile is OFF")
        return Result("firewall", "PASS", "all profiles ON")
    if system == "Darwin":
        out = _run(["/usr/libexec/ApplicationFirewall/socketfilterfw", "--getglobalstate"])
        return Result("firewall", "PASS" if "enabled" in out.lower() else "FAIL", out.strip()[:80])
    if system == "Linux":
        out = _run(["ufw", "status"])           # raises ProbeUnavailable if ufw absent
        return Result("firewall", "PASS" if "active" in out.lower() else "FAIL", out.splitlines()[0][:80])
    raise ProbeUnavailable(f"unsupported OS: {system}")


def check_disk_encryption() -> Result:
    system = platform.system()
    if system == "Windows":
        # manage-bde needs elevation to report; unprivileged -> SKIPPED, not PASS (T3)
        out = _run(["manage-bde", "-status", "-p"])
        if "Percentage Encrypted" not in out:
            raise ProbeUnavailable("needs elevation to read BitLocker status")
        return Result("disk encryption", "PASS" if "100%" in out else "WARN", "BitLocker reported")
    if system == "Darwin":
        out = _run(["fdesetup", "status"])
        return Result("disk encryption", "PASS" if "On" in out else "FAIL", out.strip()[:80])
    raise ProbeUnavailable(f"no unprivileged encryption probe on {system}")


def check_pending_updates() -> Result:
    system = platform.system()
    if system == "Linux":
        out = _run(["apt-get", "-s", "upgrade"])
        n = sum(1 for l in out.splitlines() if l.startswith("Inst "))
        if n == 0:
            return Result("pending updates", "PASS", "up to date", 0)
        return Result("pending updates", "WARN", f"{n} package(s) pending", float(n))
    raise ProbeUnavailable(f"no unprivileged update probe on {system}")


def check_listening_services() -> Result:
    """Inventory this host's own listeners. Reads local state only — sends nothing (T1)."""
    system = platform.system()
    argv = ["netstat", "-an"] if system == "Windows" else ["netstat", "-an"]
    out = _run(argv)
    listening = [l for l in out.splitlines() if "LISTEN" in l.upper()]
    # Anything bound to a wildcard address is reachable from the LAN — worth surfacing.
    external = [l for l in listening if "0.0.0.0:" in l or "[::]:" in l]
    if external:
        return Result("listening services", "WARN",
                      f"{len(listening)} listening, {len(external)} on all interfaces",
                      float(len(external)))
    return Result("listening services", "PASS", f"{len(listening)} listening, none wildcard-bound",
                  float(len(listening)))


def check_home_permissions() -> Result:
    """A world-writable home directory is a real and quiet local risk."""
    if platform.system() == "Windows":
        raise ProbeUnavailable("POSIX mode bits do not apply on Windows")
    mode = Path.home().stat().st_mode
    if mode & 0o002:
        return Result("home permissions", "FAIL", "home directory is world-writable")
    return Result("home permissions", "PASS", f"mode {oct(mode & 0o777)}")


CHECKS = [
    ("disk space", check_disk),
    ("firewall", check_firewall),
    ("disk encryption", check_disk_encryption),
    ("pending updates", check_pending_updates),
    ("reboot pending", check_uptime_reboot_pending),
    ("listening services", check_listening_services),
    ("home permissions", check_home_permissions),
]


def run_all() -> Report:
    return Report(
        results=[safe_probe(name, fn) for name, fn in CHECKS],
        host=platform.node(),
        system=f"{platform.system()} {platform.release()}",
    )


# ── output ───────────────────────────────────────────────────────────────────
def exit_code(results: list[Result]) -> int:
    return 1 if any(r.status == "FAIL" for r in results) else 0


def resolve_report_path(base: Path, filename: str) -> Path:
    """Confine the report to `base`. Refuses traversal (T6)."""
    base = Path(base).resolve()
    target = (base / filename).resolve()
    if not str(target).startswith(str(base) + os.sep) and target != base / filename:
        raise ValueError(f"refusing to write outside {base}: {filename}")
    if base not in target.parents and target.parent != base:
        raise ValueError(f"refusing to write outside {base}: {filename}")
    return target


def write_report(report: Report, base: Path, filename: str = "dailycheck.json") -> Path:
    target = resolve_report_path(base, filename)
    target.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema": SCHEMA,
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "host": report.host,
        "system": report.system,
        "results": [asdict(r) for r in report.results],
    }
    target.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return target


ICON = {"PASS": "PASS", "WARN": "WARN", "FAIL": "FAIL", "SKIPPED": "----"}


def render_text(report: Report, out=sys.stdout) -> None:
    counts: dict[str, int] = {}
    print(f"dailycheck — {report.host} ({report.system})", file=out)
    print(f"{datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}\n", file=out)
    for r in report.results:
        counts[r.status] = counts.get(r.status, 0) + 1
        print(f"  [{ICON[r.status]}]  {r.name:<22} {r.detail}", file=out)
    print("", file=out)
    summary = "  ".join(f"{k}: {v}" for k, v in sorted(counts.items()))
    print(f"  {summary}", file=out)
    if counts.get("SKIPPED"):
        print("\n  SKIPPED means the check could not run — it is NOT a pass.", file=out)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Daily health and security posture report.")
    ap.add_argument("--json", action="store_true", help="print JSON instead of text")
    ap.add_argument("--out", metavar="DIR", help="also write the JSON report to DIR")
    args = ap.parse_args(argv)

    report = run_all()
    if args.json:
        print(json.dumps({"schema": SCHEMA, "host": report.host,
                          "results": [asdict(r) for r in report.results]}, indent=2))
    else:
        render_text(report)
    if args.out:
        path = write_report(report, Path(args.out))
        print(f"\n  report written: {path}")
    return exit_code(report.results)


if __name__ == "__main__":
    sys.exit(main())
