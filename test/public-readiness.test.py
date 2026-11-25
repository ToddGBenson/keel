#!/usr/bin/env python3
"""
keel's tracked tree is fit to be public: no personal home paths, no personal
email address, no private-network IPs, and the copyright holder's name only
where the licence needs it.
Refs: TheHub #62227 (ported from binnacle's test/public-readiness.test.py, #61131)

keel is a PUBLIC repository. A public tree is a one-way door: GitHub does not
un-index it. This test is the regression guard for the tree on every PR (it
runs in the lint stage through test/manifest.txt). It does not cover history,
issues, PR bodies or CI logs; history is an operator decision (story #62227).

What it refuses, in every tracked text file:

  * a home directory with a real account name in it (C:/Users/<name>,
    /c/Users/<name>, /home/<name>, /Users/<name>). A placeholder such as
    <you>, $HOME, %USERPROFILE% or ~ is fine, and so is /home/runner (the
    GitHub-hosted runner's home, not a person's);
  * an email address that is not a noreply, example or project address;
  * an RFC 1918 or CGNAT (Tailscale) IPv4 address;
  * the copyright holder's personal name (read from LICENSE, so this file
    never has to spell it) anywhere but LICENSE and NOTICE. Documents name a
    role, "the system owner", instead.

Each pattern is also checked against a sample it must catch and one it must
not, so a pattern that silently matches nothing fails here rather than
passing for the wrong reason.

    python test/public-readiness.test.py
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
failures = []

HOME_PATH = re.compile(
    r"(?i)(?:\b[a-z]:[\\/]+users[\\/]+|/c/users/|(?<![\w.])/home/|(?<![\w.])/Users/)"
    r"(?!<|\$|%|\{|public\b|default\b|runner\b|user\b|you\b|me\b|name\b|username\b)"
    r"([a-z0-9][a-z0-9_.-]*)"
)
EMAIL = re.compile(r"(?i)(?<![\w.%+-])[a-z0-9][a-z0-9._%+-]*@([a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,})\b")
EMAIL_OK = re.compile(
    r"(?i)(^|\.)(example\.(com|org|net|invalid)|users\.noreply\.github\.com|noreply\.github\.com"
    r"|anthropic\.com|github\.com|invalid|localhost|test)$"
)
PRIVATE_IP = re.compile(
    r"(?<![\d.])(?:10\.\d{1,3}|192\.168|172\.(?:1[6-9]|2\d|3[01])|100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7]))"
    r"\.\d{1,3}\.\d{1,3}(?![\d.])"
)
COPYRIGHT = re.compile(r"^\s*Copyright\s+\d{4}(?:-\d{4})?\s+(.+?)\s*$", re.M)

#: Files that may carry the patterns as data. This file holds them as samples.
EXEMPT = {"test/public-readiness.test.py"}
#: Files that must name the copyright holder: the licence and its notice.
NAME_OK = {"LICENSE", "NOTICE"}


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def tracked_text_files():
    out = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "-z"], check=True, capture_output=True
    ).stdout.decode("utf-8")
    for rel in filter(None, out.split("\0")):
        if rel in EXEMPT:
            continue
        path = ROOT / rel
        try:
            data = path.read_bytes()
        except OSError:
            continue
        if b"\0" in data[:8192]:
            continue
        yield rel, data.decode("utf-8", errors="replace")


def scan(text):
    """Every refused match in text, as (kind, offset)."""
    hits = [("home path", m.start()) for m in HOME_PATH.finditer(text)]
    hits += [("email", m.start()) for m in EMAIL.finditer(text) if not EMAIL_OK.search(m.group(1))]
    hits += [("private IP", m.start()) for m in PRIVATE_IP.finditer(text)]
    return hits


def holder_name():
    """The copyright holder named in LICENSE, or None when it names none."""
    m = COPYRIGHT.search((ROOT / "LICENSE").read_text(encoding="utf-8"))
    return m.group(1) if m else None


def name_pattern(name):
    # Whitespace-tolerant, so a line wrap between the two words still counts.
    return re.compile(r"(?i)\b" + r"\s+".join(map(re.escape, name.split())) + r"\b")


def patterns_catch_what_they_should():
    must = {
        "Windows home path": r"cd C:\Users\alice\Documents",
        "forward-slash Windows home path": "C:/Users/alice/Documents/Projects",
        "Git Bash home path": "cd /c/Users/alice/Documents",
        "Linux home path": "MYDIR=/home/alice/src",
        "personal email": "Author: Alice <alice@gmail.com>",
        "RFC 1918 address": "ssh 192.168.1.20",
        "Tailscale address": "curl http://100.101.12.7:8000",
    }
    must_not = {
        "placeholder home path": r"C:\Users\<you>\Projects and /c/Users/$USER and %USERPROFILE%",
        "runner home": "/home/runner/work/keel",
        "loopback": "http://127.0.0.1:8100",
        "noreply email": "Co-Authored-By: Claude <noreply@anthropic.com>",
        "GitHub noreply": "45951378+someone@users.noreply.github.com",
        "GitHub SSH remote": "git@github.com:owner/keel.git",
        "example email": "t@example.invalid",
        "a version string": "build 2.10.1.4 of 1.192.168.3",
        "curl data-from-file flag": "curl https://api.github.com/graphql -d@gql.json",
    }
    for name, sample in must.items():
        check(f"the scan catches a {name}", bool(scan(sample)), repr(sample))
    for name, sample in must_not.items():
        check(f"the scan leaves a {name} alone", not scan(sample), f"{sample!r} -> {scan(sample)}")
    pat = name_pattern("Alice Example")
    check("the name check catches the holder's name", bool(pat.search("Owner: Alice Example")))
    check("the name check catches it across a line wrap", bool(pat.search("by Alice\n   Example")))
    check("the name check leaves a login that contains it alone",
          not pat.search("github.com/AliceXExample/keel"))
    check("the copyright line is read",
          COPYRIGHT.search("   Copyright 2026 Alice Example\n").group(1) == "Alice Example")


def tree_is_clean():
    files = list(tracked_text_files())
    check("the scan reads the tracked tree", len(files) > 50, f"(read {len(files)} files)")
    found = []
    for rel, text in files:
        for kind, offset in scan(text):
            line = text.count("\n", 0, offset) + 1
            found.append(f"{rel}:{line} {kind}")
    check(
        "no tracked file names a home directory, personal email or private IP",
        not found,
        "\n         " + "\n         ".join(found),
    )

    name = holder_name()
    check("LICENSE names a copyright holder", bool(name))
    if not name:
        return
    pat = name_pattern(name)
    named = []
    for rel, text in files:
        if rel in NAME_OK:
            continue
        for m in pat.finditer(text):
            named.append(f"{rel}:{text.count(chr(10), 0, m.start()) + 1}")
    # The name itself is not printed: CI logs of a public repo are public too.
    check(
        "the copyright holder's name appears only in LICENSE and NOTICE (documents name the role)",
        not named,
        "\n         " + "\n         ".join(named),
    )


def main():
    patterns_catch_what_they_should()
    tree_is_clean()
    if failures:
        print(f"\n{len(failures)} failure(s)")
        return 1
    print("\nall checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
