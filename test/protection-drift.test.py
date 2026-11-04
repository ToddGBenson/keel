#!/usr/bin/env python3
"""
Branch-protection drift: live GitHub settings against a declared state. Refs: TheHub #60979

OPERATING.md said `required_signatures` is enforced on `main`; the API said it
was off. configure-github.sh writes `enforce_admins: true`; live was false. Its
verification ran only inside the apply path, so nothing re-read the settings
after setup, and every false claim lasted until somebody audited by hand.

`bash scripts/configure-github.sh --verify-only` compares the live settings with
.sdlc/protection.yaml. This test runs it against two recorded API responses with
`gh` (and, separately, `curl`) stubbed on PATH, so no network or credential is
involved:

  * the matching response exits 0 and prints one `match` line per declared field;
  * the response with enforce_admins drifted exits 1 and prints
    `DRIFT enforce_admins declared=false live=true`, the other fields `match`;
  * every API call it makes is a GET: no -X/--method other than GET, and no
    -f/-F/--field/--raw-field/--input, which make `gh api` send a POST;
  * a protection response it cannot read (403/404) is a failure, never a match;
  * with no `gh`, it reads the API with curl and GH_TOKEN, and the token is not
    in curl's argv or in the output;
  * a declared value that differs from configure-github.sh's default and has no
    `reason:` citing a decision id or Hub story is refused;
  * .sdlc/protection.yaml declares all six fields, and each one that differs from
    configure-github.sh's default carries such a reason;
  * OPERATING.md says `required_signatures` is enforced if and only if
    .sdlc/protection.yaml declares it true.

PLATFORM-OWNED (platform/MANIFEST.yml): it opens no ci/ or .github/ file. The
pipeline wiring is asserted in the project-owned test/protection-drift-wiring.test.py.

Needs PyYAML (ci/requirements.txt).

    python test/protection-drift.test.py
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
CONFIGURE = ROOT / "scripts" / "configure-github.sh"
DECLARATION = ROOT / ".sdlc" / "protection.yaml"
OPERATING = ROOT / "OPERATING.md"
FIXTURES = ROOT / "test" / "fixtures"
MATCH = FIXTURES / "protection-live-match.json"
DRIFTED = FIXTURES / "protection-live-enforce-admins-drift.json"
DECLARED_FIXTURE = FIXTURES / "protection-declared.yaml"
BASH = shutil.which("bash") or "bash"

FIELDS = (
    "enforce_admins",
    "required_approving_review_count",
    "required_signatures",
    "required_linear_history",
    "allow_force_pushes",
    "required_status_checks",
)
# A decision id (D-123, ADR-0005) or a Hub story (TheHub #60849).
CITATION = re.compile(r"\b(?:TheHub #\d+|D-\d+|ADR-\d{4})\b")
SENTINEL_TOKEN = "github_pat_SENTINEL0000000000000000000060979"

failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def write_stub(path, body):
    path.write_text(body, newline="\n")
    # Owner-only: run by this test's own user (CodeQL py/overly-permissive-file).
    os.chmod(path, 0o700)


GH_STUB = r'''#!/usr/bin/env bash
# Records every call; serves $STUB_FIXTURE for the protection GET.
printf '%s\n' "$*" >> "$STUB_LOG"
if [ "${1:-}" = "api" ]; then
  case "${2:-}" in
    */branches/*/protection)
      cat "$STUB_FIXTURE"
      exit "${STUB_EXIT:-0}" ;;
  esac
fi
echo '{"message":"stub: unexpected call"}'
exit 1
'''

CURL_STUB = r'''#!/usr/bin/env bash
# Records argv and whether stdin carried the token; serves $STUB_FIXTURE.
printf 'ARGV %s\n' "$*" >> "$STUB_LOG"
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
stdin="$(cat)"
case "$stdin" in *"$GH_TOKEN"*) echo "STDIN carries the token" >> "$STUB_LOG" ;; esac
cat "$STUB_FIXTURE" > "${out:-/dev/stdout}"
printf '200'
'''


def run_verify(fixture, declared, stub_exit=0, with_gh=True):
    """Run --verify-only with stubs on PATH. Returns (rc, output, calls)."""
    tmp = Path(tempfile.mkdtemp(prefix="protection-drift-"))
    try:
        stubs = tmp / "stubs"
        stubs.mkdir()
        log = tmp / "calls.log"
        log.write_text("")
        env = dict(os.environ)
        env.update({"STUB_LOG": str(log), "STUB_FIXTURE": str(fixture),
                    "STUB_EXIT": str(stub_exit)})
        if with_gh:
            write_stub(stubs / "gh", GH_STUB)
            env["PATH"] = str(stubs) + os.pathsep + env.get("PATH", "")
            env.pop("GH_TOKEN", None)
        else:
            # A PATH with no gh on it: the stubs, bash's own directory (coreutils)
            # and python's. curl is the stub.
            write_stub(stubs / "curl", CURL_STUB)
            keep = [str(stubs)]
            for tool in ("bash", "python3", "python", "mktemp", "cat"):
                found = shutil.which(tool)
                if found and os.path.dirname(found) not in keep:
                    keep.append(os.path.dirname(found))
            keep = [d for d in keep if d == str(stubs) or not (Path(d) / "gh").exists()
                    and not (Path(d) / "gh.exe").exists()]
            env["PATH"] = os.pathsep.join(keep)
            env["GH_TOKEN"] = SENTINEL_TOKEN
        p = subprocess.run([BASH, str(CONFIGURE), "--verify-only", "--repo", "fixture/repo",
                            "--declared", str(declared)],
                           cwd=str(ROOT), capture_output=True, text=True, encoding="utf-8",
                           env=env, timeout=120)
        return p.returncode, p.stdout + p.stderr, log.read_text().splitlines()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def result_lines(out):
    return [ln.strip() for ln in out.splitlines()
            if re.match(r"\s*(match|DRIFT)\b", ln)]


def only_gets(calls):
    bad = []
    for c in calls:
        words = c.split()
        if words[:1] != ["api"]:
            bad.append(c)
            continue
        for i, w in enumerate(words):
            if w in ("-X", "--method") and (i + 1 >= len(words) or words[i + 1].upper() != "GET"):
                bad.append(c)
            if re.match(r"--method=(?!GET$)", w) or re.match(r"-X(?!GET$).+", w):
                bad.append(c)
            if w in ("-f", "-F", "--field", "--raw-field", "--input"):
                bad.append(c)
    return bad


print("Branch-protection drift check (TheHub #60979)")

# ── 1. the matching response ─────────────────────────────────────────────────
print("matching response")
rc, out, calls = run_verify(MATCH, DECLARED_FIXTURE)
lines = result_lines(out)
check("--verify-only exits 0 when live matches the declaration", rc == 0, f"rc={rc}\n{out}")
check("one result line per declared field (6)", len(lines) == 6, str(lines))
check("every line is `match`", lines and all(ln.startswith("match ") for ln in lines), str(lines))
for f in FIELDS:
    check(f"`{f}` is compared", any(re.match(rf"match {f}\b", ln) for ln in lines), str(lines))
check("it called the API at least once", bool(calls), str(calls))
check("every API call is a GET", not only_gets(calls), str(only_gets(calls)))

# ── 2. enforce_admins drifted ────────────────────────────────────────────────
print("enforce_admins drifted")
rc, out, calls = run_verify(DRIFTED, DECLARED_FIXTURE)
lines = result_lines(out)
check("--verify-only exits 1 on drift", rc == 1, f"rc={rc}\n{out}")
check("prints `DRIFT enforce_admins declared=false live=true`",
      "DRIFT enforce_admins declared=false live=true" in lines, str(lines))
check("the other five fields still print `match`",
      sum(1 for ln in lines if ln.startswith("match ")) == 5, str(lines))
check("every API call is a GET", not only_gets(calls), str(only_gets(calls)))

# ── 3. an unreadable response is a failure, not a match ──────────────────────
print("unreadable protection")
tmpd = Path(tempfile.mkdtemp(prefix="protection-drift-404-"))
try:
    notfound = tmpd / "404.json"
    notfound.write_text('{"message":"Not Found","status":"404"}\n')
    rc, out, _ = run_verify(notfound, DECLARED_FIXTURE, stub_exit=1)
    check("a 404 from the protection GET exits non-zero", rc not in (0,), f"rc={rc}\n{out}")
    check("and prints no `match` line", not any(ln.startswith("match ") for ln in result_lines(out)),
          out)
finally:
    shutil.rmtree(tmpd, ignore_errors=True)

# ── 4. no gh: curl with GH_TOKEN, and the token stays out of argv and output ─
print("curl path (no gh on PATH)")
rc, out, calls = run_verify(MATCH, DECLARED_FIXTURE, with_gh=False)
check("--verify-only exits 0 through curl", rc == 0, f"rc={rc}\n{out}")
check("it used curl", any(c.startswith("ARGV ") for c in calls), str(calls))
check("the token reached curl on stdin", "STDIN carries the token" in calls, str(calls))
check("the token is not in curl's argv",
      not any(SENTINEL_TOKEN in c for c in calls if c.startswith("ARGV ")), str(calls))
check("the token is not in the output", SENTINEL_TOKEN not in out, out)
check("curl made GETs only (no -X, -d, --data, -T)",
      not any(re.search(r"(^|\s)(-X|--request|-d|--data\S*|-T|--upload-file)(\s|$)", c)
              for c in calls if c.startswith("ARGV ")), str(calls))


# ── 5. configure-github.sh's defaults, read from the script itself ───────────
def script_defaults():
    text = CONFIGURE.read_text(encoding="utf-8")

    def json_bool(key):
        m = re.search(rf'^\s*"{key}": (true|false),?\s*$', text, re.M)
        return None if not m else m.group(1) == "true"

    m = re.search(r'else REVIEW_COUNT=(\d+)', text)
    checks = re.search(r"^CHECKS=\(\n(.*?)^\)", text, re.M | re.S)
    contexts = re.findall(r'"([^"]+)"', re.sub(r"#.*", "", checks.group(1))) if checks else None
    return {
        "enforce_admins": json_bool("enforce_admins"),
        # team mode, the script's default MODE
        "required_approving_review_count": int(m.group(1)) if m else None,
        # step 4b POSTs required_signatures whenever signing works
        "required_signatures": "protection/required_signatures" in text and True,
        "required_linear_history": json_bool("required_linear_history"),
        "allow_force_pushes": json_bool("allow_force_pushes"),
        "required_status_checks": sorted(contexts) if contexts is not None else None,
    }


def norm(field, value):
    return sorted(value) if field == "required_status_checks" and isinstance(value, list) else value


DEFAULTS = script_defaults()
print("configure-github.sh defaults")
for f, v in DEFAULTS.items():
    check(f"default for {f} is readable from configure-github.sh", v is not None, str(v))

# ── 6. a divergent value with no reason is refused ───────────────────────────
print("declaration without a reason")
tmpd = Path(tempfile.mkdtemp(prefix="protection-drift-reason-"))
try:
    bad = yaml.safe_load(DECLARED_FIXTURE.read_text(encoding="utf-8"))
    bad["fields"]["enforce_admins"].pop("reason", None)
    bad_path = tmpd / "no-reason.yaml"
    bad_path.write_text(yaml.safe_dump(bad), encoding="utf-8")
    rc, out, _ = run_verify(MATCH, bad_path)
    check("a divergent enforce_admins with no reason exits non-zero", rc != 0, f"rc={rc}\n{out}")
    check("and names the field", "enforce_admins" in out, out)

    bad["fields"]["enforce_admins"]["reason"] = "because it is off"
    bad_path.write_text(yaml.safe_dump(bad), encoding="utf-8")
    rc, out, _ = run_verify(MATCH, bad_path)
    check("a reason that cites no decision id or Hub story is refused", rc != 0, f"rc={rc}\n{out}")
finally:
    shutil.rmtree(tmpd, ignore_errors=True)

# ── 7. this repository's declaration ─────────────────────────────────────────
print(".sdlc/protection.yaml")
check(".sdlc/protection.yaml exists", DECLARATION.exists())
decl = yaml.safe_load(DECLARATION.read_text(encoding="utf-8")) if DECLARATION.exists() else {}
fields = (decl or {}).get("fields") or {}
check("it names a branch", bool((decl or {}).get("branch")), str(decl))
for f in FIELDS:
    entry = fields.get(f)
    check(f"declares {f}", isinstance(entry, dict) and "value" in entry, str(entry))
    if not isinstance(entry, dict) or "value" not in entry or DEFAULTS.get(f) is None:
        continue
    if norm(f, entry["value"]) != norm(f, DEFAULTS[f]):
        reason = str(entry.get("reason") or "")
        check(f"{f} differs from configure-github.sh's default ({json.dumps(DEFAULTS[f])}) "
              f"and its reason cites a decision id or Hub story",
              bool(CITATION.search(reason)), repr(reason))

# ── 8. OPERATING.md agrees with the declaration about signatures ─────────────
print("OPERATING.md")
op = OPERATING.read_text(encoding="utf-8")
claims_on = re.search(r"`required_signatures` is enforced on `main`", op) is not None
declared_sig = (fields.get("required_signatures") or {}).get("value")
check("OPERATING.md says required_signatures is enforced iff .sdlc/protection.yaml declares it true",
      claims_on == (declared_sig is True),
      f"OPERATING.md claims enforced={claims_on}, declared={declared_sig}")

print()
if failures:
    print(f"{len(failures)} FAILED")
    sys.exit(1)
print("all passed")
