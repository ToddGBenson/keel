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
# GIT_TERMINAL_PROMPT=0 so a credential prompt FAILS instead of hanging.
#
# Measured on the first real run of this script (#72): against the default
# HTTPS upstream it produced seven minutes of complete silence and had to be
# killed. `--quiet` suppressed progress, and git was waiting on a prompt nobody
# could answer. To an operator following the documented path, `keel sync` simply
# appeared dead — and the natural response to a dead sync is to stop syncing,
# which is how a fork drifts away from the platform permanently.
#
# Fail fast and say which remote, rather than hanging politely.
if ! GIT_TERMINAL_PROMPT=0 git fetch upstream --quiet --no-tags; then
  echo "" >&2
  echo "Could not fetch upstream: $(git remote get-url upstream 2>/dev/null || echo '?')" >&2
  echo "  - no network, or the remote needs credentials this shell cannot supply" >&2
  echo "  - check with: git fetch upstream" >&2
  exit 1
fi
UPSTREAM_REF="upstream/main"
git rev-parse --verify "$UPSTREAM_REF" >/dev/null 2>&1 || UPSTREAM_REF="upstream/master"
info "$(git log -1 --format='%h %s' "$UPSTREAM_REF")"

# ── Parse the manifest ───────────────────────────────────────────────────────
# DEFECT FIXED 2026-08-08: on Windows, Python's text-mode stdout translates \n to \r\n.
# Every path therefore arrived with a trailing carriage return, and `git diff -- 'path/\r'`
# matched nothing — so the sync reported "already current" on a fork that was behind.
#
# Two mitigations, deliberately belt-and-braces because the failure mode is SILENT and the
# consequence is a fork that never receives control improvements:
#   1. Python writes with an explicit "\n" via sys.stdout.buffer (no translation).
#   2. The shell strips any stray CR anyway, in case a future edit reintroduces print().
read_section() { # section name -> newline-separated paths
  python - "$1" <<'PY' | tr -d '\r'
import sys, re, pathlib
section = sys.argv[1]
txt = pathlib.Path("platform/MANIFEST.yml").read_text(encoding="utf-8")
m = re.search(rf"^{section}:\n((?:\s*-\s+.*\n|\s*#.*\n|\n)*)", txt, re.M)
if not m:
    sys.exit(0)
out = []
for line in m.group(1).split("\n"):
    s = line.strip()
    if s.startswith("- "):
        out.append(s[2:].split("#")[0].strip())
sys.stdout.buffer.write(("\n".join(out) + "\n").encode("utf-8"))
PY
}

PLATFORM_PATHS="$(read_section platform_owned)"
MERGE_PATHS="$(read_section merge_required)"

# ── 1. Platform-owned: fast-forward ──────────────────────────────────────────
say "Platform-owned paths"
changed=0
# DEFECT FIXED 2026-08-08 — the first time this script was ever run against a real fork.
#
# The loop began with an existence guard:
#     git cat-file -e "$UPSTREAM_REF:$p" || git ls-tree -d "$UPSTREAM_REF" -- "$p" || continue
# Both halves failed for every directory entry in the manifest, so EVERY platform path was
# skipped and the script cheerfully reported "already current" while the fork was several
# commits behind. A sync tool that says you are up to date when you are not is worse than
# no sync tool — the fork silently stops receiving control improvements.
#
# Two causes, either sufficient:
#   1. `git ls-tree -d <ref> -- 'path/'` returns nothing when the pathspec has a trailing
#      slash, and every directory in MANIFEST.yml has one.
#   2. On Windows/Git Bash, MSYS path conversion mangles the `<ref>:<path>` argument —
#      `upstream/main:.claude/agents/` became `upstream\main;.claude\agents\`.
#
# The guard was never needed: `git diff` against a path that does not exist upstream simply
# reports no difference, which is the behaviour we want anyway.
while IFS= read -r p; do
  [ -z "$p" ] && continue
  n=$(git diff --name-only HEAD "$UPSTREAM_REF" -- "$p" 2>/dev/null | wc -l | tr -d ' ')
  [ "${n:-0}" -eq 0 ] && continue
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
  files=$(git diff --name-only HEAD "$UPSTREAM_REF" -- "$p" 2>/dev/null || true)
  if [ -n "$files" ]; then
    needs_merge=1
    info "$p"
    while IFS= read -r f; do
      [ -n "$f" ] && printf '      %s\n' "$f"
    done <<< "$files"
  fi
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
  # Bounded, because a verification step must not be able to hang the thing it
  # verifies. Measured (#72): this self-test HANGS on Windows/Git Bash — it
  # completes in the Linux CI containers, which is why every pipeline is green
  # and an operator running `keel sync` on their own machine sees the script
  # stop dead after doing all its work. A sync that appears to hang is a sync
  # people stop running.
  #
  # `timeout` is absent on some minimal images, so fall back to running it
  # unbounded rather than skipping the check.
  if command -v timeout >/dev/null 2>&1; then
    timeout 120 bash .claude/hooks/selftest.sh >/dev/null 2>&1
    rc=$?
  else
    bash .claude/hooks/selftest.sh >/dev/null 2>&1
    rc=$?
  fi
  if [ "$rc" = "0" ]; then
    info "guard self-test: passed"
  elif [ "$rc" = "124" ]; then
    warn "guard self-test TIMED OUT after 120s — known on Windows (#72). Sync itself completed."
  else
    warn "guard self-test FAILED after sync — investigate before committing"
  fi
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
