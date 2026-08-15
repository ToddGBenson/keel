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
    m = re.match(r"^([a-z0-9_]+):\s*\|\s*$", line)
    if m:
        key = m.group(1); buf = []; continue
    # DEFECT FIXED 2026-08-08: both key regexes were `[a-z_]+`, which excludes DIGITS.
    # `e2e_test` therefore never parsed as a key and was silently dropped from every stack
    # profile — leaving its ADAPT placeholder in the generated pipeline, where the step
    # would "pass" by echoing. Silent key loss in a config parser is the worst kind.
    m = re.match(r'^([a-z0-9_]+):\s*"?([^"\n]*)"?\s*$', line)
    if m and not line.startswith(" "):
        prof[m.group(1)] = m.group(2).strip()
if key is not None:
    prof[key] = "\n".join(buf).rstrip()

def indent(text, n):
    # DEFECT FIXED 2026-08-08: this ended with .strip(), which removes leading whitespace
    # from the WHOLE result — i.e. the pad on the first line only. Every spliced block
    # emitted its first line at column 0 and the rest correctly indented, producing invalid
    # YAML that no local check caught because bootstrap had never been run. L0005.
    pad = " " * n
    lines = text.strip("\n").split("\n")
    return "\n".join(pad + ln if ln.strip() else "" for ln in lines)

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
    # indent() now supplies the pad for every line including the first; prepending here
    # as well would double-indent line 1.
    t = re.sub(pat, indent(val, 10) + "\n", t, count=1)

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

# Any `echo "ADAPT: ..."` still present is an unreplaced COMMAND placeholder — the step
# would "pass" by echoing. Comments mentioning ADAPT are fine and are not matched here.
leftover = re.findall(r'echo "ADAPT: ([^"]{0,60})', t)
if leftover:
    print("  [warn] " + str(len(leftover)) + " command placeholder(s) not replaced:")
    for L in leftover:
        print("           echo \"ADAPT: " + L + "...")
    print("           The stack profile has no value for these. Fill them in manually,")
    print("           or the pipeline will report success for a step that ran an echo.")

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

# ── 4. Substitute project identity ───────────────────────────────────────────
# DEFECTS FIXED 2026-08-08, found the first time this script was actually run:
#
#  (1) `grep -rl ... | while read` under `set -euo pipefail`: grep exits 1 when it matches
#      nothing, which killed bootstrap outright. Once the base repo's own placeholders were
#      substituted, NOTHING matched — so bootstrap failed 100% of the time. The template's
#      primary function was broken and no test caught it, because the script had never been
#      run end to end. L0005 exactly.
#
#  (2) It only rewrote the literal `@your-org`. The base repo carries a REAL owner so its
#      own CI works, which meant every fork silently inherited the upstream author as
#      CODEOWNER — a stranger with review authority over your repo.
#
# Now: replace whatever owner is actually present, and never let a no-match be fatal.
say "Substituting project identity"

# Current CODEOWNERS owner (the base repo's, or a previous fork's).
OLD_OWNER="$(grep -m1 -oE '@[A-Za-z0-9._/-]+' .github/CODEOWNERS 2>/dev/null | head -1 | tr -d '@' | cut -d/ -f1 || true)"
OLD_REPO_SLUG="$(grep -m1 -oE 'github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+' .github/ISSUE_TEMPLATE/config.yml 2>/dev/null | head -1 | cut -d/ -f2-3 || true)"

files="$(grep -rl -e '{{PROJECT_NAME}}' -e '{{GITHUB_ORG}}' -e '{{PROJECT_DESCRIPTION}}' \
           ${OLD_OWNER:+-e "@$OLD_OWNER"} ${OLD_REPO_SLUG:+-e "$OLD_REPO_SLUG"} \
           --include='*.md' --include='*.yml' --include='CODEOWNERS' \
           .github docs 2>/dev/null || true)"

count=0
if [ -n "$files" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    sed -i.bak \
      -e "s|{{PROJECT_NAME}}|$PNAME|g" \
      -e "s|{{PROJECT_DESCRIPTION}}|$PDESC|g" \
      -e "s|{{GITHUB_ORG}}|$PORG|g" \
      ${OLD_OWNER:+-e "s|@$OLD_OWNER|@$PORG|g"} \
      ${OLD_REPO_SLUG:+-e "s|$OLD_REPO_SLUG|$PORG/$PNAME|g"} \
      "$f" 2>/dev/null && rm -f "$f.bak"
    count=$((count+1))
  done <<< "$files"
fi
info "identity applied to $count file(s)"
[ -n "$OLD_OWNER" ] && [ "$OLD_OWNER" != "$PORG" ] \
  && info "CODEOWNERS reassigned: @$OLD_OWNER -> @$PORG" \
  || true

# ── 5. Reset the ledgers ─────────────────────────────────────────────────────
# You inherit the platform's PROCESS, not its findings. Carrying the base repo's POA&M
# into your project would be a false record on day one.
say "Resetting project ledgers"
mkdir -p docs/product evidence
mv README.md docs/PLATFORM.md 2>/dev/null || true

# ── Evidence: the platform's gate records are NOT yours ───────────────────────
# This block used to be missing, and the omission was invisible because the
# header of this script claimed it had happened. Measured on the first real run
# (#70): a freshly bootstrapped project inherited FOURTEEN evidence directories
# of the platform's self-reviews, and its own control-liveness check duly
# reported "G3 Code Complete: 13 records, ever fired: yes" for a repository that
# had done nothing at all.
#
# That is the exact false assurance the liveness check exists to detect,
# manufactured by the bootstrap of the tool that detects it. An empty ledger is
# the whole point of starting a project: you have no evidence yet, and saying so
# is the only honest first state.
evidence_inherited=$(find evidence -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
if [ "${evidence_inherited}" != "0" ]; then
  find evidence -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} + 2>/dev/null || true
  info "cleared ${evidence_inherited} inherited evidence bundle(s) — you start with none"
fi

# Per-repo ledgers whose contents mean something else in your repository: the
# liveness baseline is a ratchet, and inheriting one already set to the
# platform's position hides your own first regressions. The merge-reconciliation
# file references the PLATFORM's pull-request numbers, which are different pull
# requests in your repository.
rm -f .merge-reconciled.json
rm -f .control-liveness.json   # regenerated from your (empty) evidence below

# ── ADRs: theirs are decisions ABOUT the platform ─────────────────────────────
# Kept, not deleted — they explain the process you have just inherited, and
# throwing them away means the first person to ask "why does the orchestrator
# approve gates?" has nowhere to look. But they are not YOUR decisions, and one
# of them (ADR-0004, "keel is a template, not a service") is actively false
# about your project. Moved aside so `docs/adr/` is empty for your first real
# architectural decision.
if compgen -G "docs/adr/ADR-*.md" >/dev/null 2>&1; then
  mkdir -p docs/adr/platform
  mv docs/adr/ADR-*.md docs/adr/platform/ 2>/dev/null || true
  cat > docs/adr/platform/README.md <<'ADREOF'
# Inherited platform decisions

These ADRs were written by the **platform**, about the platform. They are kept because they
explain the process this project inherited — why gates work the way they do, why CI is split
the way it is, who approves what.

**They are not this project's decisions.** Your ADRs go in `docs/adr/`, numbered from 0001.

At least one of these is *false about your project* by design: the platform records that it is
a template with no product and no production environment. Yours has both. Read them as history
you were handed, not as statements about your system.
ADREOF
  info "inherited ADRs moved to docs/adr/platform/ — docs/adr/ is yours"
fi

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
bash .claude/hooks/selftest.sh >/dev/null 2>&1 && info "guard self-test: passed" \
  || info "guard self-test FAILED — investigate before proceeding"
python scripts/validate-platform.py --quiet >/dev/null 2>&1 && info "platform validation: pass" \
  || info "platform validation reported issues — run: python scripts/validate-platform.py"

# Your liveness baseline, generated from YOUR evidence — which is now none. The
# ratchet has to start at your zero, not the platform's, or your first regression
# is measured against somebody else's position and passes.
python scripts/control-liveness.py --update-baseline >/dev/null 2>&1 \
  && info "control-liveness baseline set to your (empty) starting position" \
  || info "could not write .control-liveness.json — run: python scripts/control-liveness.py --update-baseline"

# Validate what we just generated. Bootstrap previously emitted invalid YAML and still
# printed its success banner — a generator that does not check its own output is a
# generator you cannot trust.
say "Verifying generated workflows"
if python -c "
import yaml, glob, sys
bad = 0
for f in sorted(glob.glob('.github/workflows/*.yml')):
    try:
        yaml.safe_load(open(f, encoding='utf-8'))
    except Exception as e:
        print('  [FAIL] ' + f + ': ' + str(e)[:80]); bad = 1
sys.exit(bad)
" 2>/dev/null; then
  info "all workflows parse"
else
  echo "" >&2
  echo "  BOOTSTRAP PRODUCED INVALID YAML. Not marking this repo as bootstrapped." >&2
  echo "  Recover: git checkout .github/workflows/ && re-run bootstrap" >&2
  exit 1
fi

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
