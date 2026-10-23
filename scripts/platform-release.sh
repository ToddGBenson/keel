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
#   platform-release.sh verify --manifest F --bundle B --repo OWNER/REPO --tag TAG [--tree DIR]
#       Refuse unless B is a Sigstore bundle over F, made by
#       OWNER/REPO's .github/workflows/release.yml running on refs/tags/TAG
#       with GitHub's OIDC issuer. With --tree, also refuse unless DIR's
#       platform-owned files are exactly the ones F lists, byte for byte.
#
# Every refusal exits 1 and says which check refused. There is no warn-only
# mode: a signature nobody is made to fail on is decoration.
set -euo pipefail

ISSUER="https://token.actions.githubusercontent.com"
WORKFLOW_PATH=".github/workflows/release.yml"

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
  local manifest="" bundle="" repo="" tag="" tree=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --manifest) manifest="${2:-}"; shift 2 ;;
      --bundle)   bundle="${2:-}";   shift 2 ;;
      --repo)     repo="${2:-}";     shift 2 ;;
      --tag)      tag="${2:-}";      shift 2 ;;
      --tree)     tree="${2:-}";     shift 2 ;;
      *) die "unknown argument '$1'" ;;
    esac
  done
  [ -n "$repo" ] || die "--repo OWNER/REPO is required: it is the signer identity"
  [ -n "$tag" ]  || die "--tag is required: a signature is bound to the tag it was made on"
  [ -n "$manifest" ] && [ -s "$manifest" ] || die "no manifest at '${manifest}'; nothing to verify"
  # The case this exists for. An unsigned release is refused, not reported.
  [ -n "$bundle" ] && [ -s "$bundle" ] || die "UNSIGNED: no signature bundle at '${bundle}' for ${repo}@${tag}"
  command -v cosign >/dev/null 2>&1 || die "cosign is not installed; cannot verify, so this is not a pass"

  # An exact identity, not a regexp: a signature made by any other workflow,
  # branch or tag of this repository (or by a fork) does not verify.
  local identity="https://github.com/${repo}/${WORKFLOW_PATH}@refs/tags/${tag}"
  if ! cosign verify-blob \
        --bundle "$bundle" \
        --certificate-identity "$identity" \
        --certificate-oidc-issuer "$ISSUER" \
        "$manifest"; then
    die "signature does not verify for identity ${identity}"
  fi
  echo "signature: ok (${identity})"

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
  *) die "usage: $0 manifest <out-file> | verify --manifest F --bundle B --repo OWNER/REPO --tag TAG [--tree DIR]" ;;
esac
