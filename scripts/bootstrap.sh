#!/usr/bin/env bash
# Bootstrap a fresh fork of this platform into a real project.
# Run ONCE, immediately after forking or cloning the template.
#
#   bash scripts/bootstrap.sh
#   bash scripts/bootstrap.sh --stack python --name my-service --org my-org --yes
#
# What it does:
#   1. Identifies the project (name, description, org) and the stack
#   2. Splices the stack's real commands into the workflows, replacing ADAPT: placeholders
#   3. Rewrites README for YOUR project (the platform README moves to docs/PLATFORM.md)
#   4. Clears the platform's own POA&M and evidence so you start with an honest empty ledger
#   5. Wires `upstream` so you can pull platform improvements later
#   6. Installs git hooks and runs the validators
#
# It does NOT create a GitHub repo, push, or configure branch protection.
# That is scripts/configure-github.sh, run deliberately and separately.

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

STACK=""; PNAME=""; PDESC=""; PORG=""; ASSUME_YES=0
UPSTREAM_DEFAULT="https://github.com/ToddGBenson/keel.git"

while [ $# -gt 0 ]; do
  case "$1" in
    --stack) STACK="$2"; shift 2 ;;
    --name)  PNAME="$2"; shift 2 ;;
    --desc)  PDESC="$2"; shift 2 ;;
    --org)   PORG="$2";  shift 2 ;;
    --upstream) UPSTREAM_DEFAULT="$2"; shift 2 ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

say()  { printf '\n\033[1m%s\033[0m\n' "$1"; }
info() { printf '  %s\n' "$1"; }
ask()  { # var, prompt, default
  local __v="$1" __p="$2" __d="${3:-}" __r
  if [ "$ASSUME_YES" = "1" ] || [ -n "${!__v}" ]; then return; fi
  if [ -n "$__d" ]; then read -r -p "  $__p [$__d]: " __r || true; else read -r -p "  $__p: " __r || true; fi
  printf -v "$__v" '%s' "${__r:-$__d}"
}

if [ -f .bootstrapped ]; then
  echo "Already bootstrapped (.bootstrapped exists). Delete it to re-run." >&2
  exit 1
fi

# ── 1. Identity ──────────────────────────────────────────────────────────────
say "Project identity"
ask PNAME "Project name" "$(basename "$ROOT")"
ask PDESC "One-line description" "A governed software project"
ask PORG  "GitHub org or username" "$(gh api user --jq .login 2>/dev/null || echo your-org)"
: "${PNAME:=$(basename "$ROOT")}"; : "${PDESC:=A governed software project}"; : "${PORG:=your-org}"
info "name=$PNAME  org=$PORG"

# ── 2. Stack ─────────────────────────────────────────────────────────────────
say "Stack"
if [ -z "$STACK" ]; then
  for f in package.json pyproject.toml requirements.txt go.mod Cargo.toml; do
    [ -f "$f" ] || continue
    case "$f" in
      package.json) STACK=node ;; pyproject.toml|requirements.txt) STACK=python ;;
      go.mod) STACK=go ;; Cargo.toml) STACK=rust ;;
    esac
    info "detected $f -> $STACK"; break
  done
fi
if [ -z "$STACK" ] && [ "$ASSUME_YES" != "1" ]; then
  info "Available: node  python  go  rust  none"
  ask STACK "Stack" "none"
fi
: "${STACK:=none}"
PROFILE="platform/stacks/${STACK}.yml"
[ -f "$PROFILE" ] || { echo "No such stack profile: $PROFILE" >&2; exit 1; }
info "using $PROFILE"

# ── 3. Splice the stack into the workflows ───────────────────────────────────
say "Wiring the pipeline"
python - "$PROFILE" "$STACK" <<'PY'
import re, sys, pathlib

profile_path, stack = sys.argv[1], sys.argv[2]
raw = pathlib.Path(profile_path).read_text(encoding="utf-8")

# Minimal block-scalar parser: `key: |` followed by an indented block, or `key: value`.
prof, key, buf = {}, None, []
for line in raw.split("\n"):
    if key is not None:
        if line.startswith(("  ", "\t")) or line.strip() == "":
            buf.append(line[2:] if line.startswith("  ") else line)
            continue
        prof[key] = "\n".join(buf).rstrip(); key, buf = None, []
    m = re.match(r"^([a-z_]+):\s*\|\s*$", line)
    if m:
        key = m.group(1); buf = []; continue
    m = re.match(r'^([a-z_]+):\s*"?([^"\n]*)"?\s*$', line)
    if m and not line.startswith(" "):
        prof[m.group(1)] = m.group(2).strip()
if key is not None:
    prof[key] = "\n".join(buf).rstrip()

def indent(text, n):
    pad = " " * n
    return "\n".join(pad + ln if ln.strip() else "" for ln in text.split("\n")).strip()

ci = pathlib.Path(".github/workflows/ci.yml")
t = ci.read_text(encoding="utf-8")

# Replace each ADAPT echo block with the profile's real command.
REPLACE = [
    (r'          echo "ADAPT: install with a frozen lockfile[^"]*"\n(?:\s*#[^\n]*\n)*', "install"),
    (r'          echo "ADAPT: build command"\n',                                        "build"),
    (r'          echo "ADAPT: linter"\n',                                               "lint"),
    (r'          echo "ADAPT: type checker"\n',                                         "typecheck"),
    (r'          echo "ADAPT: formatter --check"\n',                                    "format_check"),
    (r'          echo "ADAPT: unit test command with coverage output"\n',               "unit_test"),
    (r'          echo "ADAPT: integration tests against real collaborators"\n(?:\s*echo[^\n]*\n)*', "integration_test"),
    (r'          echo "ADAPT: assert coverage[^"]*"\n(?:\s*#[^\n]*\n)*',                "coverage_check"),
    (r'          echo "ADAPT: every test, including the slow ones"\n',                  "unit_test"),
    (r'          echo "ADAPT: E2E[^"]*"\n',                                             "e2e_test"),
]
for pat, field in REPLACE:
    val = prof.get(field, "").strip()
    if not val:
        continue
    t = re.sub(pat, "          " + indent(val, 10) + "\n", t, count=1)

# Insert the toolchain setup step after each checkout in the build/lint/test jobs.
setup = prof.get("setup", "").strip()
if setup:
    block = indent(setup, 6)
    t = t.replace(
        "      # ADAPT: language setup + dependency cache.",
        block + "\n\n      # Toolchain pinned by bootstrap; adjust freely from here.\n      #",
        1,
    )

ci.write_text(t, encoding="utf-8")

# SAST language in security.yml
sec = pathlib.Path(".github/workflows/security.yml")
s = sec.read_text(encoding="utf-8")
lang = prof.get("sast_language", "").strip()
if lang:
    s = re.sub(r"language: \['[^']*'\]", f"language: ['{lang}']", s, count=1)
    s = s.replace("        # ADAPT: your languages.\n", "")
else:
    # No CodeQL support for this stack — disable the job rather than let it report green
    # on an analysis that never ran. A green badge on a job that scanned nothing is the
    # most common form of false assurance in a pipeline.
    s = s.replace(
        "  sast:\n    name: SAST — CodeQL (SA-11(1))\n    runs-on: ubuntu-latest\n",
        "  sast:\n    name: SAST — CodeQL (SA-11(1))\n    if: false  # no CodeQL support for this stack; see sast_alternative\n    runs-on: ubuntu-latest\n",
        1,
    )
sec.write_text(s, encoding="utf-8")

# Extra gitignore entries
extra = prof.get("gitignore_extra", "").strip()
if extra:
    gi = pathlib.Path(".gitignore")
    g = gi.read_text(encoding="utf-8")
    if extra.split("\n")[0] not in g:
        gi.write_text(g.rstrip() + f"\n\n# ── {stack} ──\n" + extra + "\n", encoding="utf-8")

# Stash the precommit fragment for install-hooks.sh
pathlib.Path(".git/precommit-stack.sh").write_text(prof.get("precommit", ":"), encoding="utf-8")
print(f"  spliced {stack} into ci.yml and security.yml")
PY

# ── 4. Substitute placeholders ───────────────────────────────────────────────
say "Substituting project identity"
grep -rl '{{PROJECT_NAME}}\|{{GITHUB_ORG}}\|{{PROJECT_DESCRIPTION}}\|@your-org' \
  --include='*.md' --include='*.yml' --include='CODEOWNERS' \
  .github docs 2>/dev/null | while read -r f; do
  sed -i.bak \
    -e "s|{{PROJECT_NAME}}|$PNAME|g" \
    -e "s|{{PROJECT_DESCRIPTION}}|$PDESC|g" \
    -e "s|{{GITHUB_ORG}}|$PORG|g" \
    -e "s|@your-org|@$PORG|g" "$f" && rm -f "$f.bak"
done
info "identity applied to .github/ and docs/"

# ── 5. Reset the ledgers ─────────────────────────────────────────────────────
# You inherit the platform's PROCESS, not its findings. Carrying the base repo's POA&M
# into your project would be a false record on day one.
say "Resetting project ledgers"
mkdir -p docs/product evidence
mv README.md docs/PLATFORM.md 2>/dev/null || true

cat > README.md <<EOF
# $PNAME

$PDESC

Built on a governed, agent-driven SDLC — see [docs/PLATFORM.md](docs/PLATFORM.md) for how
the process works, and [CONTRIBUTING.md](CONTRIBUTING.md) to get started in 30 minutes.

**Stack:** $STACK · **Compliance anchor:** NIST SP 800-53 Rev. 5

## Quick start

\`\`\`bash
bash scripts/install-hooks.sh
python scripts/validate-platform.py
/idea  <describe a problem your users have>
\`\`\`

## Status

| | |
|---|---|
| Gates configured | G0–G5 |
| Branch protection | run \`bash scripts/configure-github.sh\` |
| Open findings | see [POA&M](docs/compliance/poam.md) |
EOF

python - <<'PY'
import pathlib, re
p = pathlib.Path("docs/compliance/poam.md")
t = p.read_text(encoding="utf-8")
head = t.split("## Register")[0]
p.write_text(head + """## Register

| ID | Weakness | Control | Risk | Owner | Due | Status |
|---|---|---|---|---|---|---|
| — | *No entries yet. Populated by `/security-gate`, `/ai-gate`, assessments, and incidents.* | | | | | |

""" + t.split("## Rules", 1)[1].join(["## Rules", ""]) if "## Rules" in t else head, encoding="utf-8")

inv = pathlib.Path("docs/compliance/ai-inventory.md")
s = inv.read_text(encoding="utf-8")
s = re.sub(r"\| — \| \*No entries yet\.\*.*\n", "| — | *No entries yet.* | | | | | | | | |\n", s)
inv.write_text(s, encoding="utf-8")
PY
info "POA&M and AI inventory reset to empty"

# ── 6. Upstream remote ───────────────────────────────────────────────────────
say "Upstream link"
if git remote get-url upstream >/dev/null 2>&1; then
  info "upstream already set: $(git remote get-url upstream)"
else
  ask UPSTREAM_DEFAULT "Platform upstream URL" "$UPSTREAM_DEFAULT"
  git remote add upstream "$UPSTREAM_DEFAULT" 2>/dev/null \
    && info "upstream -> $UPSTREAM_DEFAULT" \
    || info "could not add upstream; set it later with: git remote add upstream <url>"
fi

# ── 7. Remove bootstrap-only files ───────────────────────────────────────────
rm -f docs/adr/ADR-0001-platform-architecture.md
python - <<'PY'
import pathlib, re
p = pathlib.Path("docs/adr/README.md")
if p.exists():
    t = p.read_text(encoding="utf-8")
    t = re.sub(r"\| \[0001\][^\n]*\n", "| — | *No ADRs yet.* | | |\n", t)
    p.write_text(t, encoding="utf-8")
PY

# ── 8. Hooks and validation ──────────────────────────────────────────────────
say "Hooks and validation"
bash scripts/install-hooks.sh >/dev/null 2>&1 && info "git hooks installed"
bash .claude/hooks/selftest.sh >/dev/null 2>&1 && info "guard self-test: 20/20" \
  || info "guard self-test FAILED — investigate before proceeding"
python scripts/validate-platform.py --quiet >/dev/null 2>&1 && info "platform validation: pass" \
  || info "platform validation reported issues — run: python scripts/validate-platform.py"

date -u +"%Y-%m-%dT%H:%M:%SZ" > .bootstrapped
echo "stack=$STACK name=$PNAME org=$PORG" >> .bootstrapped

cat <<EOF

────────────────────────────────────────────────────────────────
  $PNAME is bootstrapped on the $STACK stack.

  Next:
    1. git add -A && git commit -m "chore: bootstrap $PNAME

       Refs: #0"
    2. bash scripts/configure-github.sh    <- turns the gates into real controls
    3. /idea  <a problem your users have>

  Pull platform improvements later:
    bash scripts/sync-platform.sh

  Until step 2 is done, separation of duties and G5 are documentation,
  not controls. That is the single most important thing on this list.
────────────────────────────────────────────────────────────────
EOF
