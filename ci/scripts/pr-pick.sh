#!/usr/bin/env bash
# Pick one open pull request head to judge, and check it out. Refs: TheHub #61778
#
# The git resource follows `main`, so Concourse is never told a pull request was
# opened or pushed. The `pr-checks` job asks on a clock instead, and this script
# is its first task: it finds the open heads, asks MyKronos which one has no
# verdict yet, posts `start` for it (the `Concourse / <repo>` check run goes
# in_progress on that head) and leaves the head checked out in `pr/`.
#
# Which heads:
#   * `refs/pull/N/head` with a `refs/pull/N/merge` beside it. GitHub keeps the
#     merge ref only while a pull request is open, so that is "open" without a
#     GitHub API token (this pipeline holds none).
#   * Only a head that is the tip of a branch IN this repository. A fork's head
#     is never judged: running an untrusted contributor's code on a worker inside
#     the LAN is refused, and pushing a branch here takes write access.
#   * Never a head on the base branch itself: the commit chain owns that check.
#
# Once per head. MyKronos keeps one check run per (repository, commit, name) and
# answers a `start` on a head that already has one with `unchanged` and the
# existing state ("a start never reopens a verdict"). A head whose check is
# `completed` is skipped; one still `in_progress` (a run that died) is judged
# again; a new head is `created`. Newest pull request first, at most
# PR_PICK_LIMIT starts per run.
#
# Credentials: the deploy key (to read the repository, which may be private) and
# the ingestion token. Nothing here runs pull-request code: the head is fetched
# and checked out, never executed. The task that runs it gets neither credential.
#
# No head to judge is a pass with an empty `pr/` (and `pr/.none`), so the later
# tasks and the end report do nothing.
set -euo pipefail

: "${REPO_SLUG:?REPO_SLUG is required}"
: "${GIT_URI:?GIT_URI is required}"
: "${MYKRONOS_INGESTION_URL:?MYKRONOS_INGESTION_URL is required}"
: "${MYKRONOS_INGESTION_TOKEN:?MYKRONOS_INGESTION_TOKEN is required}"
BASE_BRANCH="${BASE_BRANCH:-main}"
PR_PICK_LIMIT="${PR_PICK_LIMIT:-30}"
OUT="${PR_OUT:-pr}"
GIT="${GIT:-git}"
CURL="${CURL:-curl}"
PY="${PY:-python3}"

mkdir -p "$OUT"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# SSH only for an SSH uri. GitHub's published ed25519 host key is pinned rather
# than trusted on first use. Set GIT_SSH_COMMAND to override (the tests do).
case "$GIT_URI" in
  git@*|ssh://*)
    : "${GIT_PRIVATE_KEY:?GIT_PRIVATE_KEY is required for an SSH GIT_URI}"
    umask 077
    printf '%s\n' "$GIT_PRIVATE_KEY" > "$work/key"
    printf '%s\n' 'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl' \
      > "$work/known_hosts"
    export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -i $work/key -o IdentitiesOnly=yes -o UserKnownHostsFile=$work/known_hosts -o StrictHostKeyChecking=yes}"
    ;;
esac

"$GIT" ls-remote "$GIT_URI" 'refs/heads/*' 'refs/pull/*/head' 'refs/pull/*/merge' > "$work/refs"

# Candidates, newest first: "<number> <sha> <branch>".
"$PY" - "$work/refs" "$BASE_BRANCH" > "$work/candidates" <<'PY'
import re, sys
refs = {}
for line in open(sys.argv[1], encoding="utf-8"):
    parts = line.split()
    if len(parts) == 2:
        refs[parts[1]] = parts[0]
base = sys.argv[2]
tips = {}
for ref, sha in refs.items():
    if ref.startswith("refs/heads/"):
        tips.setdefault(sha, []).append(ref[len("refs/heads/"):])
out = []
for ref, sha in refs.items():
    m = re.fullmatch(r"refs/pull/(\d+)/head", ref)
    if not m or f"refs/pull/{m.group(1)}/merge" not in refs:
        continue
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        continue
    branches = [b for b in tips.get(sha, []) if b != base]
    if not branches:
        continue  # a fork's head, or a head that is only the base branch
    out.append((int(m.group(1)), sha, sorted(branches)[0]))
for number, sha, branch in sorted(out, reverse=True):
    print(number, sha, branch)
PY

echo "$(wc -l < "$work/candidates" | tr -d ' ') open pull request head(s) on branches of ${REPO_SLUG}."

asked=0
picked=""
while read -r number sha branch; do
  [ "$asked" -ge "$PR_PICK_LIMIT" ] && break
  asked=$((asked + 1))
  body=$(printf '{"repo_full_name":"%s","commit_sha":"%s","job":"pr-checks","phase":"start","conclusion":null}' \
    "$REPO_SLUG" "$sha")
  "$CURL" --fail-with-body --silent --show-error --connect-timeout 10 --max-time 45 \
    --retry 2 --retry-delay 5 --retry-connrefused \
    -X POST \
    -H "Authorization: Bearer ${MYKRONOS_INGESTION_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$body" "${MYKRONOS_INGESTION_URL}/api/ingest/check-runs" > "$work/answer"
  verdict=$("$PY" - "$work/answer" <<'PY'
import json, sys
a = json.load(open(sys.argv[1], encoding="utf-8"))
outcome, status = a.get("outcome"), a.get("status")
if outcome in ("created", "updated"):
    print("judge")
elif outcome == "unchanged" and status != "completed":
    print("judge")       # a start that never got its end: the run died
elif outcome == "unchanged":
    print("skip")
else:
    print("refused")
PY
)
  case "$verdict" in
    judge) picked="$number $sha $branch"; break ;;
    skip) echo "#${number} ${sha:0:12} (${branch}): already judged." ;;
    *) echo "MyKronos answered the start for #${number} with something other than created/updated/unchanged:" >&2
       cat "$work/answer" >&2; exit 1 ;;
  esac
done < "$work/candidates"

if [ -z "$picked" ]; then
  echo "No pull request head needs a verdict."
  : > "$OUT/.none"
  exit 0
fi

read -r number sha branch <<< "$picked"
echo "Judging #${number} ${sha} (${branch})."
"$GIT" -C "$OUT" init -q
"$GIT" -C "$OUT" fetch -q --no-tags "$GIT_URI" "refs/pull/${number}/head"
got=$("$GIT" -C "$OUT" rev-parse FETCH_HEAD)
if [ "$got" != "$sha" ]; then
  # The branch moved between ls-remote and fetch. The start stays in progress
  # on the old head (a superseded commit; nothing merges it), and the next run
  # finds the new head as a new candidate. Never report on a sha that was not
  # checked out, so this fails with no commit in pr/ and the end report posts
  # nothing.
  echo "#${number} moved from ${sha} to ${got} while it was fetched; picking again next run." >&2
  exit 1
fi
"$GIT" -C "$OUT" -c advice.detachedHead=false checkout -q --detach "$sha"
# check-run.sh reads the sha from .git/HEAD.
[ "$(tr -d ' \n' < "$OUT/.git/HEAD")" = "$sha" ]
printf '%s %s %s\n' "$number" "$sha" "$branch" > "$OUT/.pr"
