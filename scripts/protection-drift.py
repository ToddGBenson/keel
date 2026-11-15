#!/usr/bin/env python3
"""Compare live branch protection with a declared state. Refs: TheHub #60979

Called by `bash scripts/configure-github.sh --verify-only`, which does the one
GET and hands this script the response. Kept separate so the comparison has no
network, no credential and no shell quoting in it.

    python scripts/protection-drift.py branch  <declared.yaml>
    python scripts/protection-drift.py compare <declared.yaml> <live.json>

`compare` prints one line per declared field and exits 1 on any DRIFT:

    match enforce_admins = false
    DRIFT required_signatures declared=true live=false

It also refuses (exit 1) a declaration that is not one: a missing field, an
unknown field, or a value that differs from configure-github.sh's default with
no `reason:` citing a decision id (D-123, ADR-0005) or a Hub story
(TheHub #60849). A declaration that quietly records whatever is live is a
snapshot, not an intended state; the reason is what makes it one.

The declaration format is .sdlc/protection.yaml:

    version: 1
    branch: main
    fields:
      enforce_admins:
        value: false
        reason: TheHub #60849 option C ...
      ...
"""
from __future__ import annotations

import json
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover
    print("ERROR: PyYAML is required: pip install -r ci/requirements.txt", file=sys.stderr)
    sys.exit(2)

# configure-github.sh's defaults (team mode, signing available). The script is
# the source; test/protection-drift.test.py reads these from it independently,
# so the two cannot disagree silently.
DEFAULTS = {
    "enforce_admins": True,
    "required_approving_review_count": 1,
    "required_signatures": True,
    "required_linear_history": True,
    "allow_force_pushes": False,
    "required_status_checks": sorted([
        "Process compliance",
        "Platform integrity (AIC-3, AIC-8, AU-9)",
        "Dependency review (SR-3, SR-4, AIC-7)",
        "Build", "Lint & static typing", "Test & coverage",
        "SAST — CodeQL (SA-11(1))",
        "Secret scanning (IA-5)",
        "SCA — dependency vulnerabilities (RA-5, SR-3)",
        "IaC & configuration (CM-6, CM-7)",
        "Suppression audit",
        "SAST — CodeQL (SA-11(1)) (javascript-typescript)",
    ]),
}
FIELDS = tuple(DEFAULTS)
CITATION = re.compile(r"\b(?:TheHub #\d+|D-\d+|ADR-\d{4})\b")


def _enabled(live, key):
    v = live.get(key)
    if isinstance(v, dict):
        return v.get("enabled")
    return v


def live_value(live: dict, field: str):
    """The live value of a declared field, None when GitHub reports nothing."""
    if field == "required_approving_review_count":
        return (live.get("required_pull_request_reviews") or {}).get(
            "required_approving_review_count")
    if field == "required_status_checks":
        rsc = live.get("required_status_checks") or {}
        contexts = list(rsc.get("contexts") or [])
        contexts += [c.get("context") for c in rsc.get("checks") or [] if c.get("context")]
        return sorted(set(contexts))
    return _enabled(live, field)


def norm(field, value):
    if field == "required_status_checks" and isinstance(value, list):
        return sorted(set(value))
    return value


def show(value) -> str:
    if value is None:
        return "absent"
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def load_declaration(path: str) -> tuple[dict, list[str]]:
    errors: list[str] = []
    try:
        with open(path, encoding="utf-8") as fh:
            decl = yaml.safe_load(fh) or {}
    except (OSError, yaml.YAMLError) as exc:
        return {}, [f"cannot read {path}: {exc}"]
    if not isinstance(decl, dict):
        return {}, [f"{path} is not a mapping"]
    if decl.get("version") != 1:
        errors.append(f"version must be 1, got {decl.get('version')!r}")
    if not isinstance(decl.get("branch"), str) or not decl["branch"]:
        errors.append("branch: is required")
    fields = decl.get("fields")
    if not isinstance(fields, dict):
        return decl, errors + ["fields: is required"]
    for name in fields:
        if name not in FIELDS:
            errors.append(f"unknown field {name!r} (known: {', '.join(FIELDS)})")
    for name in FIELDS:
        entry = fields.get(name)
        if not isinstance(entry, dict) or "value" not in entry:
            errors.append(f"{name}: not declared (every field needs a value:)")
            continue
        value = entry["value"]
        if name == "required_status_checks":
            if not (isinstance(value, list) and all(isinstance(c, str) for c in value)):
                errors.append(f"{name}: value must be a list of check names")
                continue
        elif name == "required_approving_review_count":
            if isinstance(value, bool) or not isinstance(value, int):
                errors.append(f"{name}: value must be an integer")
                continue
        elif not isinstance(value, bool):
            errors.append(f"{name}: value must be true or false")
            continue
        if norm(name, value) != DEFAULTS[name]:
            reason = str(entry.get("reason") or "")
            if not CITATION.search(reason):
                errors.append(
                    f"{name}: declared {show(norm(name, value))} differs from configure-github.sh's "
                    f"default {show(DEFAULTS[name])}, and its reason: cites no decision id "
                    f"(D-123, ADR-0005) or Hub story (TheHub #12345): {reason!r}"
                    + (" (an unquoted ' #' starts a YAML comment: quote the reason or use >-)"
                       if reason.rstrip().endswith("TheHub") else ""))
    return decl, errors


def main(argv: list[str]) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if len(argv) >= 2 and argv[0] == "branch":
        decl, errors = load_declaration(argv[1])
        if not decl.get("branch"):
            for e in errors:
                print(f"ERROR {e}", file=sys.stderr)
            return 2
        print(decl["branch"])
        return 0
    if len(argv) != 3 or argv[0] != "compare":
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    decl, errors = load_declaration(argv[1])
    if errors:
        for e in errors:
            print(f"ERROR declaration {argv[1]}: {e}")
        return 1
    try:
        with open(argv[2], encoding="utf-8") as fh:
            live = json.load(fh)
    except (OSError, ValueError) as exc:
        print(f"ERROR live protection is not JSON: {exc}")
        return 2
    if not isinstance(live, dict) or "message" in live and "url" not in live:
        print(f"ERROR live protection unreadable: {show(live.get('message') if isinstance(live, dict) else live)}")
        return 2
    drift = 0
    for name in FIELDS:
        want = norm(name, decl["fields"][name]["value"])
        got = live_value(live, name)
        if want == got:
            print(f"match {name} = {show(want)}")
        else:
            print(f"DRIFT {name} declared={show(want)} live={show(got)}")
            drift += 1
    if drift:
        print(f"{drift} of {len(FIELDS)} declared fields drifted on {decl['branch']}")
        return 1
    print(f"all {len(FIELDS)} declared fields match on {decl['branch']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
