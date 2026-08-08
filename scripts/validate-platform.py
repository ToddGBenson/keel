#!/usr/bin/env python3
"""
Validate the platform's own integrity.

Controls: CA-2 (control assessment), AIC-3 (least agency), AIC-8 (config change control),
          AU-9 (evidence integrity), SA-15 (development standards)

This is the repeatable form of the checks that would otherwise be run by hand and therefore
eventually not run at all. It implements the tool-grant drift check that
docs/compliance/ai-inventory.md promises, and is wired into compliance-evidence.yml.

Python rather than shell because it parses YAML frontmatter and markdown tables; the
prior shell version of this logic was a stub.

Usage:  python scripts/validate-platform.py [--quiet]
Exit:   0 all checks pass · 1 one or more failures
"""

from __future__ import annotations

import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

FAILURES: list[str] = []
WARNINGS: list[str] = []
QUIET = "--quiet" in sys.argv


def ok(msg: str) -> None:
    if not QUIET:
        print(f"  [ok]   {msg}")


def fail(msg: str) -> None:
    FAILURES.append(msg)
    print(f"  [FAIL] {msg}")


def warn(msg: str) -> None:
    WARNINGS.append(msg)
    if not QUIET:
        print(f"  [warn] {msg}")


def frontmatter(path: str) -> dict[str, str] | None:
    txt = open(path, encoding="utf-8").read()
    m = re.match(r"^---\n(.*?)\n---\n", txt, re.S)
    if not m:
        return None
    out: dict[str, str] = {}
    for line in m.group(1).split("\n"):
        if ":" in line and not line.startswith((" ", "\t", "-")):
            k, _, v = line.partition(":")
            out[k.strip()] = v.strip()
    return out


# ── 1. Structural config validity ────────────────────────────────────────────
def check_config() -> None:
    print("\nConfiguration syntax")
    try:
        import yaml
    except ImportError:
        warn("pyyaml not installed — YAML validation skipped (CI validates it)")
        yaml = None  # type: ignore

    if yaml:
        for f in sorted(glob.glob(".github/**/*.yml", recursive=True)):
            try:
                yaml.safe_load(open(f, encoding="utf-8"))
            except Exception as e:  # noqa: BLE001
                fail(f"{f}: {str(e)[:90]}")
        ok(f"{len(glob.glob('.github/**/*.yml', recursive=True))} YAML files parse")

    try:
        json.load(open(".claude/settings.json", encoding="utf-8"))
        ok(".claude/settings.json parses")
    except Exception as e:  # noqa: BLE001
        fail(f".claude/settings.json: {str(e)[:90]}")


# ── 2. Agents, commands, skills are well-formed ──────────────────────────────
def check_definitions() -> None:
    print("\nAgent / command / skill definitions (AIC-8)")

    for f in sorted(glob.glob(".claude/agents/*.md")):
        fm = frontmatter(f)
        if not fm:
            fail(f"{f}: no frontmatter")
        elif not {"name", "description", "tools"} <= fm.keys():
            fail(f"{f}: frontmatter missing name/description/tools")
    ok(f"{len(glob.glob('.claude/agents/*.md'))} agents well-formed")

    for f in sorted(glob.glob(".claude/commands/*.md")):
        fm = frontmatter(f)
        if not fm or "description" not in fm:
            fail(f"{f}: missing frontmatter description")
    ok(f"{len(glob.glob('.claude/commands/*.md'))} commands well-formed")

    skills = sorted(glob.glob(".claude/skills/*/SKILL.md"))
    for f in skills:
        fm = frontmatter(f)
        dirname = os.path.basename(os.path.dirname(f))
        if not fm:
            fail(f"{f}: no frontmatter")
            continue
        if fm.get("name") != dirname:
            fail(f"{f}: name '{fm.get('name')}' != directory '{dirname}'")
        if len(fm.get("description", "")) < 60:
            warn(f"{f}: description is thin; it is how the skill gets discovered")
    ok(f"{len(skills)} skills well-formed")

    # Every skill listed in CLAUDE.md exists, and vice versa.
    claude_md = open("CLAUDE.md", encoding="utf-8").read()
    listed = set(re.findall(r"^\| `([a-z-]+)` \|", claude_md, re.M))
    on_disk = {os.path.basename(os.path.dirname(f)) for f in skills}
    for s in sorted(listed - on_disk):
        fail(f"CLAUDE.md lists skill '{s}' which does not exist")
    for s in sorted(on_disk - listed):
        fail(f"skill '{s}' exists but is not registered in CLAUDE.md")
    if listed and listed == on_disk:
        ok(f"all {len(on_disk)} skills registered in CLAUDE.md")


# ── 3. Tool-grant drift vs. the AI inventory (AIC-3) ─────────────────────────
# This is the check docs/compliance/ai-inventory.md promises. Drift between the documented
# grant and the actual one IS enforceable and IS a genuine control failure — unlike
# write-scope, which is prompt-enforced only (POAM-001).
CAP_PATTERNS = {
    "Write": re.compile(r"\bWrite\b"),
    "Edit": re.compile(r"\bEdit\b"),
    "Bash": re.compile(r"\bBash\b"),
    # The inventory uses the shorthand "Web"; agent frontmatter spells out WebSearch /
    # WebFetch. Both must normalise to the same capability or every web-capable agent
    # reports false drift — which is what happened on this checker's first run.
    "Web": re.compile(r"\bWeb(Search|Fetch)?\b"),
}


def capabilities(tools: str) -> set[str]:
    return {name for name, pat in CAP_PATTERNS.items() if pat.search(tools)}


def check_tool_grants() -> None:
    print("\nAgent tool-grant drift vs. ai-inventory.md (AIC-3, AIC-8)")
    inv_path = "docs/compliance/ai-inventory.md"
    if not os.path.exists(inv_path):
        fail(f"{inv_path} missing — the AI inventory is required (GOVERN 1.6, CM-8)")
        return

    inv = open(inv_path, encoding="utf-8").read()
    documented: dict[str, set[str]] = {}
    for row in re.findall(r"^\|\s*`([a-z-]+)`\s*\|([^\n]*)$", inv, re.M):
        agent, rest = row
        cols = [c.strip() for c in rest.split("|")]
        # Section B layout: purpose | model | tool grant | expected write scope | ...
        if len(cols) >= 3:
            documented[agent] = capabilities(cols[2])

    if not documented:
        fail("could not parse the agent table in ai-inventory.md § Section B")
        return

    actual: dict[str, set[str]] = {}
    for f in sorted(glob.glob(".claude/agents/*.md")):
        fm = frontmatter(f) or {}
        name = fm.get("name", os.path.basename(f)[:-3])
        actual[name] = capabilities(fm.get("tools", ""))

    # Scoped to THIS check. Using the global FAILURES list here would suppress the "ok"
    # whenever any unrelated earlier check failed, which makes the output misleading
    # precisely when someone is debugging a failure.
    drift = 0
    for agent in sorted(set(documented) | set(actual)):
        if agent not in actual:
            fail(f"'{agent}' is in the inventory but has no agent definition")
            drift += 1
        elif agent not in documented:
            fail(f"'{agent}' has a definition but is NOT in the AI inventory (CM-8)")
            drift += 1
        elif documented[agent] != actual[agent]:
            extra = actual[agent] - documented[agent]
            missing = documented[agent] - actual[agent]
            detail = []
            if extra:
                detail.append(f"grants {sorted(extra)} not documented")
            if missing:
                detail.append(f"documented {sorted(missing)} not granted")
            fail(f"'{agent}' tool-grant drift: {'; '.join(detail)}")
            drift += 1
    if drift == 0:
        ok(f"{len(actual)} agents match their documented tool grants")


# ── 4. Evidence integrity posture (AU-9) ─────────────────────────────────────
def check_evidence() -> None:
    print("\nEvidence integrity (AU-9)")
    gitignore = open(".gitignore", encoding="utf-8").read() if os.path.exists(".gitignore") else ""
    for pat in ("evidence/**/*.sarif", "evidence/**/*.xml"):
        if pat not in gitignore:
            fail(f".gitignore does not exclude {pat} — generated evidence must not be committed")
    if os.path.exists(".gitignore"):
        ok("generated evidence excluded from version control")

    stray = [f for f in glob.glob("evidence/**/*", recursive=True)
             if os.path.isfile(f) and f.rsplit(".", 1)[-1] in ("sarif", "xml")]
    if stray:
        fail(f"{len(stray)} generated evidence file(s) present in the tree: {stray[:3]}")
    else:
        ok("no hand-placed generated evidence in the tree")


# ── 5. Pipeline hardening (SR-3, AC-6) ───────────────────────────────────────
def check_workflows() -> None:
    print("\nWorkflow hardening (SR-3, SR-11, AC-6)")
    unpinned: list[str] = []
    no_perms: list[str] = []
    for f in sorted(glob.glob(".github/workflows/*.yml")):
        txt = open(f, encoding="utf-8").read()
        for line in txt.split("\n"):
            # Skip commented lines. The first run of this checker flagged commented-out
            # `# - uses: actions/setup-node@...` examples as unpinned actions — a checker
            # that cries wolf on documentation gets muted, and then it is not a control.
            if line.lstrip().startswith("#"):
                continue
            m = re.search(r"uses:\s*([^\s#]+)", line)
            if not m:
                continue
            use = m.group(1)
            if use.startswith("./"):
                continue
            ref = use.split("@")[-1] if "@" in use else ""
            if not re.fullmatch(r"[0-9a-f]{40}", ref):
                unpinned.append(f"{os.path.basename(f)}: {use}")
        if not re.search(r"^permissions:", txt, re.M):
            no_perms.append(os.path.basename(f))
        if "pull_request_target" in txt:
            fail(f"{os.path.basename(f)}: uses pull_request_target — prohibited on untrusted input")

    if unpinned:
        for u in unpinned:
            fail(f"action not pinned to a full SHA - {u}")
    else:
        ok("all third-party actions pinned to full commit SHAs")

    if no_perms:
        fail(f"workflow(s) without a top-level permissions block: {no_perms}")
    else:
        ok("all workflows declare least-privilege permissions")


# ── 6. Guard hooks behave as documented (CA-2) ───────────────────────────────
def check_guards() -> None:
    print("\nGuard hooks")
    st = ".claude/hooks/selftest.sh"
    if not os.path.exists(st):
        fail(f"{st} missing — guards are unverified")
        return
    ok(f"{st} present - run it: bash {st}")
    for h in ("guard-bash.sh", "guard-write.sh", "session-brief.sh"):
        if not os.path.exists(f".claude/hooks/{h}"):
            fail(f".claude/hooks/{h} missing but referenced by settings.json")


def main() -> int:
    print("=" * 62)
    print("  Platform self-validation")
    print("=" * 62)
    check_config()
    check_definitions()
    check_tool_grants()
    check_evidence()
    check_workflows()
    check_guards()

    print("\n" + "=" * 62)
    if FAILURES:
        print(f"  {len(FAILURES)} FAILURE(S), {len(WARNINGS)} warning(s)")
        print("\n  These are control failures, not style issues. File them as findings.")
        return 1
    print(f"  All checks passed ({len(WARNINGS)} warning(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
