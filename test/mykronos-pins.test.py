#!/usr/bin/env python3
"""
Every MyKronos pin in .github/workflows names one commit, and it is not a
commit known to lack mykronos #1036. Refs: TheHub #61212

The generated workflows install the MyKronos uploader three ways: the
`upload-results@<sha>` action, its `mykronos-ref:` input, and a
`pip install 'mykronos @ git+...@<sha>'` step. They sat on cce7495 (v8, 2026-08-29)
while the Concourse pin moved to v17. #1036 (13f5ab1) is the osv-scanner fix
that reads a fixed version filed under the rule's GHSA alias; without it every
atlas finding arrives with no fixed version and reads as having no fix. The
uploader normalises findings, so the backend having the fix is not enough.

Tags v0.1.0 to v16 all predate #1036 and are refused by commit. Pins must also
agree with each other: the first install in a job wins, so a second, older pin
in the same job silently downgrades the first.

    python test/mykronos-pins.test.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKFLOWS = ROOT / ".github" / "workflows"
failures = []

#: mykronos tag commits that do not contain #1036 (13f5ab1).
LACKS_1036 = {
    "e854942089327abe5d671237a683acaf8f5f7e65": "v0.1.0",
    "966aa4fc5a55bcb359f428d6b1e88ed97d3f5b34": "v1",
    "de9c3b5693e644932706e7cf236e29eb7f8ff24c": "v2",
    "353503081aaf6437398b7558e3c116de787dc380": "v3",
    "f5f7979c84334dd6de1966fe28c1ba5c9786c772": "v4",
    "31271b63e8f206f097703faf26cd0dbe9f3f2fc4": "v4.1",
    "935758eb5f678d64f76aeb22f0db86ec180d6015": "v5",
    "df529241bb4bbea6c75bd58137cb9808410598bf": "v6",
    "7e23c9b1c963c44408d9ef1b0fe727b4458b222f": "v7",
    "cce7495afafb3f22b014847bd91624ced9b8e2dd": "v8",
    "f5dcd17f357dfd6b2983f75a39cf979368239bc9": "v9",
    "768782094db3b60411f9b56568071cc984c38b02": "v10",
    "e2b725f96b01fc85613f254c65f4b5bbe9bb7bd1": "v11",
    "9b92f6eff60e69324d366780be08a74dcd8e0605": "v12",
    "71d952c0d41d69754162df36692eb5e1bf8ba690": "v13",
    "8e2e41261b9f3695a1ab3616be2db7d8095cd486": "v14",
    "2dd4e4465c21e4b6e8f2bf046c6ab565ba03b285": "v15",
    "fc65c4b942c65ac3a88b9bacdeda12246df22825": "v16",
    # binnacle's ShellCheck lane pin before TheHub #61212; untagged.
    "f8d8cfd46bea39fe4fc38242c5b7e710edfb4d9c": "f8d8cfd",
}

PIN = re.compile(
    r"(?:ToddGBenson/mykronos/actions/upload-results@"
    r"|git\+https://github\.com/ToddGBenson/mykronos@"
    r"|^\s*mykronos-ref:\s*)([0-9A-Za-z._-]+)",
    re.MULTILINE,
)


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def pins():
    found = {}
    for path in sorted(WORKFLOWS.glob("*.yml")):
        text = path.read_text(encoding="utf-8")
        for match in PIN.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            found[f"{path.name}:{line}"] = match.group(1)
    return found


def main():
    found = pins()
    check("the workflows pin MyKronos somewhere", bool(found), "(found no pins; did the pattern break?)")
    check(
        "the atlas workflow is among them",
        any(where.startswith("mykronos-atlas.yml:") for where in found),
        str(sorted(found)),
    )

    for where, ref in sorted(found.items()):
        check(f"{where} pins a full commit sha", re.fullmatch(r"[0-9a-f]{40}", ref) is not None, ref)
        check(
            f"{where} pins a commit that has #1036",
            ref not in LACKS_1036,
            f"({ref[:12]} is {LACKS_1036.get(ref)}, which predates the atlas fixed-version fix)",
        )

    commits = set(found.values())
    check("every pin names the same commit", len(commits) == 1, str(sorted(commits)))

    if failures:
        print(f"\n{len(failures)} failure(s)")
        return 1
    print("\nall checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
