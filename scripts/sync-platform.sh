#!/usr/bin/env bash
# Pull platform improvements from upstream into this fork.
#
#   bash scripts/sync-platform.sh              # show what changed, then apply
#   bash scripts/sync-platform.sh --check      # report only, change nothing
#
# ── THE PROBLEM THIS SOLVES ──────────────────────────────────────────────────
# Without a sync path, a fork is a one-time copy. The moment the platform improves —
# a new skill, a fixed guard hook, a tightened gate — every fork is stranded on the
# version it was born with, and the learning loop stops at the project boundary.
#
# Governed by platform/MANIFEST.yml:
#   platform_owned  -> fast-forwarded from upstream (your local edits are overwritten)
#   project_owned   -> never touched
#   merge_required  -> reported as a diff; a human merges
#
# The three-way split is the point. Silently overwriting a workflow you tuned would
# break your build; silently skipping it would strand you on an old control set.

set -euo pipefail
cd "$(dirname "$0")/.."

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

say()  { printf '\n\033[1m%s\033[0m\n' "$1"; }
info() { printf '  %s\n' "$1"; }
warn() { printf '  [warn] %s\n' "$1"; }

git rev-parse --git-dir >/dev/null 2>&1 || { echo "Not a git repository." >&2; exit 1; }

if ! git remote get-url upstream >/dev/null 2>&1; then
  echo "No 'upstream' remote. Set it to the platform base repo:" >&2
  echo "  git remote add upstream https://github.com/ToddGBenson/keel.git" >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ] && [ "$CHECK_ONLY" = "0" ]; then
  echo "Working tree is dirty. Commit or stash first — this script rewrites files." >&2
  exit 1
fi

say "Fetching upstream"
git fetch upstream --quiet
UPSTREAM_REF="upstream/main"
git rev-parse --verify "$UPSTREAM_REF" >/dev/null 2>&1 || UPSTREAM_REF="upstream/master"
info "$(git log -1 --format='%h %s' "$UPSTREAM_REF")"

# ── Parse the manifest ───────────────────────────────────────────────────────
read_section() { # section name -> newline-separated paths
  python - "$1" <<'PY'
import sys, re, pathlib
section = sys.argv[1]
txt = pathlib.Path("platform/MANIFEST.yml").read_text(encoding="utf-8")
m = re.search(rf"^{section}:\n((?:\s*-\s+.*\n|\s*#.*\n|\n)*)", txt, re.M)
if not m:
    sys.exit(0)
for line in m.group(1).split("\n"):
    s = line.strip()
    if s.startswith("- "):
        print(s[2:].split("#")[0].strip())
PY
}

PLATFORM_PATHS="$(read_section platform_owned)"
MERGE_PATHS="$(read_section merge_required)"

# ── 1. Platform-owned: fast-forward ──────────────────────────────────────────
say "Platform-owned paths"
changed=0
while IFS= read -r p; do
  [ -z "$p" ] && continue
  git cat-file -e "$UPSTREAM_REF:$p" 2>/dev/null || \
    git ls-tree -d "$UPSTREAM_REF" -- "$p" >/dev/null 2>&1 || continue
  if git diff --quiet HEAD "$UPSTREAM_REF" -- "$p" 2>/dev/null; then
    continue
  fi
  n=$(git diff --name-only HEAD "$UPSTREAM_REF" -- "$p" 2>/dev/null | wc -l | tr -d ' ')
  info "$p  ($n file(s) differ)"
  changed=$((changed+n))
  if [ "$CHECK_ONLY" = "0" ]; then
    git checkout "$UPSTREAM_REF" -- "$p" 2>/dev/null || warn "could not update $p"
  fi
done <<< "$PLATFORM_PATHS"
[ "$changed" = "0" ] && info "already current"

# ── 2. Merge-required: report, never overwrite ───────────────────────────────
say "Merge-required paths (a human decides these)"
needs_merge=0
while IFS= read -r p; do
  [ -z "$p" ] && continue
  if git diff --quiet HEAD "$UPSTREAM_REF" -- "$p" 2>/dev/null; then continue; fi
  files=$(git diff --name-only HEAD "$UPSTREAM_REF" -- "$p" 2>/dev/null)
  [ -z "$files" ] && continue
  needs_merge=1
  info "$p"
  while IFS= read -r f; do
    [ -n "$f" ] && printf '      %s\n' "$f"
  done <<< "$files"
done <<< "$MERGE_PATHS"
if [ "$needs_merge" = "0" ]; then
  info "nothing to merge"
else
  info ""
  info "Review each with:   git diff HEAD $UPSTREAM_REF -- <path>"
  info "Take upstream with: git checkout $UPSTREAM_REF -- <path>"
  warn "These carry YOUR tuning AND upstream control changes. Read before taking."
fi

# ── 3. Lessons ledger ────────────────────────────────────────────────────────
say "Lessons"
new_lessons=$(git diff --name-only HEAD "$UPSTREAM_REF" -- docs/lessons/ 2>/dev/null | grep -v README || true)
if [ -n "$new_lessons" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] && info "new/updated: $(basename "$f")"
  done <<< "$new_lessons"
  info ""
  info "These are lessons other projects learned the hard way. Read them — that is"
  info "the entire return on the fork-and-sync arrangement."
else
  info "no new lessons"
fi

# ── 4. Verify nothing broke ──────────────────────────────────────────────────
if [ "$CHECK_ONLY" = "0" ] && [ "$changed" != "0" ]; then
  say "Verifying"
  bash .claude/hooks/selftest.sh >/dev/null 2>&1 \
    && info "guard self-test: passed" \
    || warn "guard self-test FAILED after sync — investigate before committing"
  python scripts/validate-platform.py --quiet >/dev/null 2>&1 \
    && info "platform validation: pass" \
    || warn "platform validation reported issues — run it directly"
fi

say "Next"
if [ "$CHECK_ONLY" = "1" ]; then
  cat <<'EOF'
  Check-only run. Nothing changed.
  Apply with: bash scripts/sync-platform.sh
EOF
else
  cat <<'EOF'
  Review the diff, then commit as a normal change:

    git diff
    git add -A
    git commit -m "chore(platform): sync from upstream

    Refs: #<issue>"

  A platform sync is a Normal change under CM-3: it goes through a PR and a
  non-author review like anything else. It can change your controls.
EOF
fi
