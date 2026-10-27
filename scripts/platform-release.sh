#!/usr/bin/env bash
# The platform release: what forks receive, written down, signed and checked.
# Refs: #144, TheHub #60936, POAM-011. Controls: SR-4(3), CM-14, SI-7.
#
# keel ships no image (ADR-0004). What it distributes is the set of
# platform-owned files that scripts/sync-platform.sh fast-forwards into every
# fork, over local edits, by design. So that is the thing signed: a checksum
# manifest of every tracked platform-owned file at the released tag.
#
#   platform-release.sh manifest <out-file>
#       Write "sha256  path" for every tracked file under platform_owned in
#       platform/MANIFEST.yml, sorted by path, LF line endings. Run from the
#       repository root.
#
#   platform-release.sh verify --manifest F --bundle B --repo OWNER/REPO --tag TAG
#                              --git DIR --trusted-ref REF [--tree DIR]
#       Refuse unless B is a Sigstore bundle over F, made by
#       OWNER/REPO's .github/workflows/release.yml running on refs/tags/TAG
#       with GitHub's OIDC issuer, AT THE COMMIT TAG NAMES, and that commit is
#       reachable from REF in the git repository DIR. With --tree, also refuse
#       unless DIR's platform-owned files are exactly the ones F lists.
#
#       Why the commit and the trusted ref (HubOps review of #145, finding 1):
#       the identity "release.yml@refs/tags/TAG" names a FILE PATH on a TAG, and
#       the file at that path is whatever the tagged commit says. Anyone who can
#       push a tag can push one on a commit whose release.yml drops the G5
#       approval, dispatch it, and get a signature that verifies the same.
#       Requiring the tagged commit to be on main (REF) means the workflow that
#       signed is one that went through main's review, and pinning cosign to
#       that commit (--certificate-github-workflow-sha) means the certificate
#       must say so. There is no default REF: in a checkout of the tag, HEAD IS
#       the tag and every check would pass. Concourse passes its checkout of
#       main (HEAD); release.yml passes origin/main; a fork passes upstream/main.
#
#       This is only as strong as main. Who can push to main and who can create
#       a v* tag are repository rulesets, which the operator owns
#       (docs/compliance/poam.md, POAM-011).
#
#       And "on main" is not enough on its own (wave-2 review of #145): main's
#       history holds release.yml versions that are unsafe to sign from. Before
#       af878f1, preflight held `id-token: write` and interpolated the free-text
#       input inputs.change_record into `run:`, so a tag on an old main commit
#       could mint release.yml's OIDC identity from injected code. So the tag's
#       commit must also DESCEND from RELEASE_FLOOR, hard-coded below. A
#       repository that does not hold the floor commit is refused, not skipped.
#
# Every refusal exits 1 and says which check refused. There is no warn-only
# mode: a signature nobody is made to fail on is decoration.
set -euo pipefail

ISSUER="https://token.actions.githubusercontent.com"
WORKFLOW_PATH=".github/workflows/release.yml"

# The release floor: af878f1 (#143, TheHub #60935), the first commit on main
# whose release.yml has authorize-release (G5, refusing a run with no recorded
# approval), no workflow_dispatch input, and no `id-token: write` anywhere.
# From here on the only job that can mint the signing identity is
# sign-and-attest, which needs authorize-release (#144).
# test/supply-chain.test.py re-checks every release.yml from this commit to
# HEAD. Not a parameter, and no environment override: whoever runs the
# verifier must not be able to lower it. Move it forward, never back.
RELEASE_FLOOR="af878f1517fe8352192e5f5213d3260d914d4a78"

die() { echo "REFUSED: $*" >&2; exit 1; }

# platform_owned paths from platform/MANIFEST.yml, one per line. The same
# parse sync-platform.sh uses, and for the same reason: written as bytes so
# Windows text mode cannot append a CR to every path.
platform_paths() {
  python - <<'PY' | tr -d '\r'
import pathlib, re, sys
txt = pathlib.Path("platform/MANIFEST.yml").read_text(encoding="utf-8")
m = re.search(r"^platform_owned:\n((?:\s*-\s+.*\n|\s*#.*\n|\n)*)", txt, re.M)
if not m:
    sys.exit("platform/MANIFEST.yml has no platform_owned section")
out = [l.strip()[2:].split("#")[0].strip() for l in m.group(1).split("\n") if l.strip().startswith("- ")]
sys.stdout.buffer.write(("\n".join(out) + "\n").encode("utf-8"))
PY
}

write_manifest() { # out-file ; run from the tree root
  local out="$1" paths=()
  [ -f platform/MANIFEST.yml ] || die "no platform/MANIFEST.yml in $(pwd)"
  while IFS= read -r p; do [ -n "$p" ] && paths+=("$p"); done < <(platform_paths)
  [ "${#paths[@]}" -gt 0 ] || die "platform_owned lists no paths"
  # Tracked files only: an untracked file in a working tree is not part of
  # the release. Hashed in Python, not sha256sum, so the line format is the
  # same on every machine (Windows sha256sum writes " *path"), sorted by the
  # path's bytes, LF only.
  python - "$out" "${paths[@]}" <<'PY'
import hashlib, subprocess, sys
out, paths = sys.argv[1], sys.argv[2:]
listed = subprocess.run(["git", "ls-files", "-z", "--", *paths],
                        check=True, capture_output=True).stdout
names = sorted(n for n in listed.split(bytes(1)) if n)
with open(out, "wb") as f:
    for n in names:
        with open(n, "rb") as g:
            digest = hashlib.sha256(g.read()).hexdigest()
        f.write(digest.encode("ascii") + b"  " + n + bytes([10]))
PY
  [ -s "$out" ] || die "no tracked platform-owned files; nothing to sign"
}

verify() {
  local manifest="" bundle="" repo="" tag="" tree="" gitdir="" trusted=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --manifest) manifest="${2:-}"; shift 2 ;;
      --bundle)   bundle="${2:-}";   shift 2 ;;
      --repo)     repo="${2:-}";     shift 2 ;;
      --tag)      tag="${2:-}";      shift 2 ;;
      --tree)     tree="${2:-}";     shift 2 ;;
      --git)      gitdir="${2:-}";   shift 2 ;;
      --trusted-ref) trusted="${2:-}"; shift 2 ;;
      *) die "unknown argument '$1'" ;;
    esac
  done
  [ -n "$repo" ] || die "--repo OWNER/REPO is required: it is the signer identity"
  [ -n "$tag" ]  || die "--tag is required: a signature is bound to the tag it was made on"
  [ -n "$manifest" ] && [ -s "$manifest" ] || die "no manifest at '${manifest}'; nothing to verify"
  # The case this exists for. An unsigned release is refused, not reported.
  [ -n "$bundle" ] && [ -s "$bundle" ] || die "UNSIGNED: no signature bundle at '${bundle}' for ${repo}@${tag}"
  [ -n "$gitdir" ] || die "--git DIR is required: the repository the tag is resolved in"
  [ -n "$trusted" ] || die "--trusted-ref REF is required (main): a tag alone does not say which release.yml signed"

  # The tag's commit, and that it is on the trusted ref. Before cosign: a
  # valid signature from an unreviewed workflow is still refused.
  local commit trusted_sha
  commit="$(git -C "$gitdir" rev-parse --verify --quiet "refs/tags/${tag}^{commit}")" \
    || die "tag ${tag} is not in the repository at ${gitdir}; cannot tell which commit signed it"
  trusted_sha="$(git -C "$gitdir" rev-parse --verify --quiet "${trusted}^{commit}")" \
    || die "trusted ref '${trusted}' does not resolve in ${gitdir}"
  if ! git -C "$gitdir" merge-base --is-ancestor "$commit" "$trusted_sha"; then
    die "tag ${tag} is on commit ${commit}, which is not reachable from ${trusted} (${trusted_sha}): its release.yml was never on ${trusted}, so its signature says nothing about the G5 gate"
  fi
  git -C "$gitdir" cat-file -e "${RELEASE_FLOOR}^{commit}" 2>/dev/null \
    || die "the release floor ${RELEASE_FLOOR} is not in the repository at ${gitdir}; fetch the full history of the release repository (no shallow clone) and retry"
  if ! git -C "$gitdir" merge-base --is-ancestor "$RELEASE_FLOOR" "$commit"; then
    die "tag ${tag} is on commit ${commit}, which does not descend from the release floor ${RELEASE_FLOOR}: its release.yml predates the G5 gate and could sign from injected input"
  fi
  echo "tag: ${tag} -> ${commit}, on ${trusted}, at or above the release floor ${RELEASE_FLOOR:0:12}"

  command -v cosign >/dev/null 2>&1 || die "cosign is not installed; cannot verify, so this is not a pass"

  # An exact identity, not a regexp: a signature made by any other workflow,
  # branch or tag of this repository (or by a fork) does not verify. And the
  # certificate's own claims: this repository, dispatched (release.yml's only
  # trigger), on the tag, at the commit checked above.
  local identity="https://github.com/${repo}/${WORKFLOW_PATH}@refs/tags/${tag}"
  if ! cosign verify-blob \
        --bundle "$bundle" \
        --certificate-identity "$identity" \
        --certificate-oidc-issuer "$ISSUER" \
        --certificate-github-workflow-repository "$repo" \
        --certificate-github-workflow-ref "refs/tags/${tag}" \
        --certificate-github-workflow-sha "$commit" \
        --certificate-github-workflow-trigger workflow_dispatch \
        "$manifest"; then
    die "signature does not verify for identity ${identity} at ${commit}"
  fi
  echo "signature: ok (${identity} at ${commit})"

  if [ -n "$tree" ]; then
    local fresh
    fresh="$(mktemp)"
    ( cd "$tree" && write_manifest "$fresh" ) || { rm -f "$fresh"; die "could not hash the tree at ${tree}"; }
    if ! cmp -s "$manifest" "$fresh"; then
      echo "Differences (signed manifest vs tree):" >&2
      diff "$manifest" "$fresh" >&2 || true
      rm -f "$fresh"
      die "the tree at ${tree} is not the signed release: a platform file was added, removed or changed"
    fi
    rm -f "$fresh"
    echo "tree: ok ($(wc -l < "$manifest" | tr -d ' ') platform-owned files match the signed manifest)"
  fi
}

case "${1:-}" in
  manifest) [ -n "${2:-}" ] || die "usage: $0 manifest <out-file>"; write_manifest "$2" ;;
  verify)   shift; verify "$@" ;;
  *) die "usage: $0 manifest <out-file> | verify --manifest F --bundle B --repo OWNER/REPO --tag TAG --git DIR --trusted-ref REF [--tree DIR]" ;;
esac
