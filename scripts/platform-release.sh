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
#   platform-release.sh verify --key --manifest F --bundle B --repo OWNER/REPO --tag TAG
#                              --git DIR --trusted-ref REF [--tree DIR]
#       The same, for a KEYED signature (TheHub #62072, 61779): a release
#       signed in Concourse with a key held in Vault transit, which has no
#       OIDC identity for Fulcio to certify. B must verify against the PEM
#       public key .github/cosign.pub AS COMMITTED ON REF (git show REF:...),
#       with `cosign verify-blob --key` and no certificate-identity flags: a
#       key signature carries no certificate to hold them against.
#       The key is reviewed content on the trusted ref, like
#       .github/release-floor. It is never taken from the working tree or
#       from an argument (`--key` takes no value), because whoever runs the
#       verifier, or whoever pushed the tag, must not choose the key that
#       checks the signature. No key on REF is a refusal.
#       The tag, trusted-ref, release-floor and --tree checks are the same
#       code in both modes; only the signature check differs. Keyless stays
#       the default.
#
#       And "on main" is not enough on its own (wave-2 review of #145): main's
#       history holds release.yml versions that are unsafe to sign from. Before
#       af878f1, preflight held `id-token: write` and interpolated the free-text
#       input inputs.change_record into `run:`, so a tag on an old main commit
#       could mint release.yml's OIDC identity from injected code. So the tag's
#       commit must also DESCEND from the release floor (TheHub #61432: per
#       repository, see release_floor() below). A shallow clone is refused, not
#       skipped, and upstream keel is always held to its own floor.
#
# Every refusal exits 1 and says which check refused. There is no warn-only
# mode: a signature nobody is made to fail on is decoration.
set -euo pipefail

ISSUER="https://token.actions.githubusercontent.com"
WORKFLOW_PATH=".github/workflows/release.yml"
# The keyed mode's public key, read only from the trusted ref (TheHub #62072).
KEY_PATH=".github/cosign.pub"

# The release floor: af878f1 (#143, TheHub #60935), the first commit on main
# whose release.yml has authorize-release (G5, refusing a run with no recorded
# approval), no workflow_dispatch input, and no `id-token: write` anywhere.
# From here on the only job that can mint the signing identity is
# sign-and-attest, which needs authorize-release (#144).
# test/supply-chain.test.py re-checks every release.yml from this commit to
# HEAD. Not a parameter, and no environment override: whoever runs the
# verifier must not be able to lower it. Move it forward, never back.
RELEASE_FLOOR="af878f1517fe8352192e5f5213d3260d914d4a78"
# The repository whose release.yml the floor above was measured on. A signature from it is
# always held to RELEASE_FLOOR, whatever the clone holds.
KEEL_UPSTREAM="ToddGBenson/keel"

# TheHub #61432: the floor is per repository. RELEASE_FLOOR is keel's own commit, and a
# repository made from keel without its history (a template copy, binnacle) does not hold it,
# so every one of its releases was refused. The floor that applies:
#   1. a shallow clone is refused: missing history is not "no keel history";
#   2. a repository whose trusted ref descends from RELEASE_FLOOR (keel, a GitHub fork with
#      keel's history), or whose signer is KEEL_UPSTREAM, is held to RELEASE_FLOOR. Holding the
#      object is not enough: a clone that fetched keel as a remote holds it off its main;
#   3. any other repository is held to its own floor: the commit sha in .github/release-floor
#      as committed on the TRUSTED ref. That is reviewed content, not a parameter, so whoever
#      runs the verifier cannot lower it. It must be in the repository and reachable from the
#      trusted ref. It names the first commit whose release.yml has the G5 gate and takes no
#      workflow input as program text (keel's af878f1 fix). With no such file the release is
#      refused. There is no implicit default: a repository's first commit may carry the
#      pre-gate release.yml (binnacle's does), so the root is not a safe floor.
# A repository whose trusted ref holds RELEASE_FLOOR may still configure a floor, but only one that descends
# from RELEASE_FLOOR: a configured floor can only move the floor forward.
# The trusted ref names a BRANCH, never a tag (TheHub #61432 review). A short name is looked up
# only among branches (refs/remotes/<name>, refs/heads/<name>, refs/remotes/origin/<name>), so a
# tag spelled like a branch cannot stand in for it. HEAD is the caller's own checkout (Concourse's
# get of main). Anything else, a tag or a sha included, is refused.
resolve_trusted() { # $1 git dir, $2 ref -> prints its commit
  local gitdir=$1 ref=$2 full="" c
  case "$ref" in
    HEAD) full=HEAD ;;
    refs/heads/*|refs/remotes/*) full=$ref ;;
    refs/*) die "trusted ref '${ref}' is not a branch (refs/heads/ or refs/remotes/); a tag cannot be the trusted ref" ;;
    *)
      for c in "refs/remotes/${ref}" "refs/heads/${ref}" "refs/remotes/origin/${ref}"; do
        if git -C "$gitdir" show-ref --verify --quiet "$c"; then full=$c; break; fi
      done
      [ -n "$full" ] || die "trusted ref '${ref}' is not a branch in ${gitdir} (looked for refs/remotes/${ref}, refs/heads/${ref} and refs/remotes/origin/${ref}); a tag cannot be the trusted ref" ;;
  esac
  git -C "$gitdir" rev-parse --verify --quiet "${full}^{commit}" \
    || die "trusted ref '${ref}' does not resolve in ${gitdir}"
}
release_floor() { # $1 git dir, $2 trusted sha, $3 OWNER/REPO -> prints the floor sha
  local gitdir=$1 trusted=$2 repo=$3 cfg base=""
  [ "$(git -C "$gitdir" rev-parse --is-shallow-repository 2>/dev/null)" = "false" ] \
    || die "the repository at ${gitdir} is a shallow clone (or not a repository); fetch its full history (no --depth) and retry: the release floor cannot be judged on part of it"
  # keel's floor applies where the TRUSTED REF descends from it, not wherever its object is: a
  # repository without keel's history whose clone also fetched keel (an upstream remote, to sync
  # the platform) holds the object off its main, and is held to its own floor like any other.
  # Upstream keel is held to RELEASE_FLOOR whatever its trusted ref holds.
  if [ "$(printf '%s' "$repo" | tr 'A-Z' 'a-z')" = "$(printf '%s' "$KEEL_UPSTREAM" | tr 'A-Z' 'a-z')" ]; then
    git -C "$gitdir" cat-file -e "${RELEASE_FLOOR}^{commit}" 2>/dev/null \
      || die "the release floor ${RELEASE_FLOOR} is not in the repository at ${gitdir}; fetch the full history of ${KEEL_UPSTREAM} and retry"
    base=$RELEASE_FLOOR
  elif git -C "$gitdir" cat-file -e "${RELEASE_FLOOR}^{commit}" 2>/dev/null \
       && git -C "$gitdir" merge-base --is-ancestor "$RELEASE_FLOOR" "$trusted"; then
    base=$RELEASE_FLOOR
  fi
  # An absent file is "no configured floor"; a file that exists but cannot be read is refused,
  # never read as absent (review nit: it fell back to keel's floor silently).
  cfg=""
  if git -C "$gitdir" cat-file -e "${trusted}:.github/release-floor" 2>/dev/null; then
    cfg=$(git -C "$gitdir" show "${trusted}:.github/release-floor") \
      || die "cannot read .github/release-floor on the trusted ref"
    cfg=$(printf '%s' "$cfg" | tr -d ' \t\r\n')
    [ -n "$cfg" ] || die ".github/release-floor on the trusted ref is empty"
  fi
  if [ -z "$cfg" ]; then
    [ -n "$base" ] && { printf '%s' "$base"; return 0; }
    die "${repo} does not hold keel's release floor and its trusted ref has no .github/release-floor; commit that file (through a reviewed PR) naming the first commit whose release.yml has the G5 gate and passes workflow inputs as data"
  fi
  printf '%s' "$cfg" | grep -qE '^[0-9a-f]{40}$' \
    || die ".github/release-floor on the trusted ref is not a 40-character commit sha"
  git -C "$gitdir" cat-file -e "${cfg}^{commit}" 2>/dev/null \
    || die ".github/release-floor names ${cfg}, which is not in the repository at ${gitdir}"
  git -C "$gitdir" merge-base --is-ancestor "$cfg" "$trusted" \
    || die ".github/release-floor names ${cfg}, which is not reachable from the trusted ref"
  if [ -n "$base" ]; then
    git -C "$gitdir" merge-base --is-ancestor "$base" "$cfg" \
      || die ".github/release-floor names ${cfg}, which does not descend from the floor it would replace (${base:0:12}): a configured floor may only move forward"
  fi
  printf '%s' "$cfg"
}

# TheHub #62061: a configured floor is reviewed content, but in a repository without keel's floor
# commit nothing held it forward, and main may need no approval: a PR moving .github/release-floor
# back to the root commit, once merged, let a tag on the root verify, though the root's release.yml
# signed from injected input. So the release.yml of EVERY commit from a CONFIGURED floor to the
# tag's commit (the floor's, each commit in floor..commit including merges, and the tag's own; each
# distinct version read once) must carry the G5 gate:
#   - no `id-token: write` (nor write-all) at the top level;
#   - a job holding `id-token: write` (or write-all) runs in the `production` environment, or needs,
#     directly or through other jobs, one that does, with no `if:` and no `continue-on-error` on
#     the signing job or on any job between it and the production job (`if: always()` would run
#     it when production was rejected);
#   - inside a `run:` (or an action's `script:`), every ${{ }} expression is one of a short list
#     that cannot carry caller text: secrets.*, a fixed github.* value (sha, run_id, run_number,
#     run_attempt, repository, repository_owner, server_url, api_url, workspace, job, workflow),
#     runner.*. Inputs reach the shell through env:, as data. Anything else is refused, so inputs
#     in any form (inputs['x'], format(), toJSON(inputs)), job outputs, matrix values, steps
#     outputs, env.* and github.ref_name are all refused there.
# It reads the workflow, not the repository's settings: whether `production` has required
# reviewers is the environment's configuration, and is not checked here. keel's own built-in floor
# is keel's reviewed history and is not walked.
# Read with PyYAML, from bytes; without it the floor cannot be judged, and the release is refused.
release_yml_gated() { # $1 git dir, $2 floor, $3 commit
  local gitdir=$1 floor=$2 commit=$3 blob kind seen=" " out first list c
  list=$(git -C "$gitdir" rev-list "${floor}..${commit}") \
    || die "cannot list the commits from the release floor ${floor:0:12} to ${commit:0:12}"
  # One line per commit, "<commit>:<path> <commit>", for one cat-file: its blob id, or "missing".
  list=$(for c in "$floor" "$commit" $list; do printf '%s:%s %s\n' "$c" "$WORKFLOW_PATH" "$c"; done \
         | git -C "$gitdir" cat-file --batch-check='%(objectname) %(objecttype) %(rest)') \
    || die "cannot read ${WORKFLOW_PATH} at the commits from the release floor ${floor:0:12}"
  while read -r blob kind first; do
    [ "$kind" = blob ] || continue           # no release.yml at that commit: nothing signs there
    case "$seen" in *" $blob "*) continue ;; esac
    seen="$seen$blob "
    out=$(git -C "$gitdir" cat-file blob "$blob" 2>/dev/null | python -c '
import re, sys
try:
    import yaml
except ImportError:
    sys.exit("PyYAML is not installed (pip install pyyaml), so its G5 gate cannot be read")
try:
    wf = yaml.safe_load(sys.stdin.buffer.read()) or {}
except yaml.YAMLError as exc:
    sys.exit(f"it is not valid YAML ({exc.__class__.__name__})")
if not isinstance(wf, dict):
    sys.exit("it is not a workflow mapping")
def signs(p):
    return p == "write-all" or (isinstance(p, dict) and p.get("id-token") == "write")
SAFE = re.compile(r"\s*(secrets\.[A-Za-z_][A-Za-z0-9_]*|runner\.[A-Za-z_]+"
                  r"|github\.(sha|run_id|run_number|run_attempt|repository|repository_owner"
                  r"|server_url|api_url|workspace|job|workflow))\s*")
def scripts(node):
    if isinstance(node, dict):
        for k, v in node.items():
            if k in ("run", "script") and isinstance(v, str):
                yield v
            yield from scripts(v)
    elif isinstance(node, list):
        for v in node:
            yield from scripts(v)
def unsafe(text):
    rest = text
    while "${{" in rest:
        rest = rest.split("${{", 1)[1]
        if "}}" not in rest:
            return True
        expr, rest = rest.split("}}", 1)
        if not SAFE.fullmatch(expr):
            return True
    return False
bad = []
if signs(wf.get("permissions")):
    bad.append("id-token: write at the top level")
jobs = wf.get("jobs") or {}
jobs = jobs if isinstance(jobs, dict) else {}
def env_name(j):
    e = j.get("environment") if isinstance(j, dict) else None
    return e.get("name") if isinstance(e, dict) else e
def behind(name, seen=()):
    j = jobs.get(name)
    if not isinstance(j, dict) or name in seen:
        return False
    if "continue-on-error" in j:
        return False
    if env_name(j) == "production":
        return True
    if "if" in j:
        return False
    needs = j.get("needs") or []
    needs = [needs] if isinstance(needs, str) else needs
    return any(behind(n, seen + (name,)) for n in needs if isinstance(n, str))
for name, j in jobs.items():
    if isinstance(j, dict) and signs(j.get("permissions")) and not behind(name):
        bad.append(f"job {name} holds id-token: write outside the production environment, or "
                   "behind it with an if: or continue-on-error that can run it without approval")
if any(unsafe(v) for v in scripts(wf)):
    bad.append("a ${{ }} expression in run: or script: that is not on the allowed list "
               "(inputs reach the shell through env:)")
if bad:
    sys.exit("; ".join(bad))
' 2>&1) || die "the release floor ${floor:0:12} is not safe: ${WORKFLOW_PATH} at ${first:0:12} lacks the G5 gate (${out}). Move .github/release-floor (through a reviewed PR) to the first commit whose ${WORKFLOW_PATH} has it"
  done <<< "$list"
}

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

# Keyless (the default): a Fulcio certificate for release.yml on the tag.
verify_keyless() { # $1 bundle, $2 manifest, $3 OWNER/REPO, $4 tag, $5 tag's commit
  local bundle=$1 manifest=$2 repo=$3 tag=$4 commit=$5
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
}

# Keyed (--key): the public key committed on the trusted ref, nowhere else.
KEYFILE=""
verify_keyed() { # $1 bundle, $2 manifest, $3 git dir, $4 trusted ref name, $5 its commit
  local bundle=$1 manifest=$2 gitdir=$3 trusted=$4 trusted_sha=$5 first
  git -C "$gitdir" cat-file -e "${trusted_sha}:${KEY_PATH}" 2>/dev/null \
    || die "--key: ${KEY_PATH} is not committed on the trusted ref ${trusted} (${trusted_sha}); the key is read from there only, never from the working tree or an argument. Commit it through a reviewed PR"
  KEYFILE="$(mktemp)"
  trap 'rm -f "$KEYFILE"' EXIT
  git -C "$gitdir" show "${trusted_sha}:${KEY_PATH}" > "$KEYFILE" \
    || die "--key: cannot read ${KEY_PATH} on the trusted ref"
  first="$(grep -v '^[[:space:]]*$' "$KEYFILE" | head -n 1 | tr -d '\r')"
  [ "$first" = "-----BEGIN PUBLIC KEY-----" ] \
    || die "--key: ${KEY_PATH} on the trusted ref is not a PEM public key (its first line is not -----BEGIN PUBLIC KEY-----)"
  if ! cosign verify-blob \
        --bundle "$bundle" \
        --key "$KEYFILE" \
        "$manifest"; then
    die "signature does not verify against ${KEY_PATH} on ${trusted} (${trusted_sha:0:12})"
  fi
  echo "signature: ok (key ${KEY_PATH} on ${trusted} at ${trusted_sha:0:12})"
}

verify() {
  local manifest="" bundle="" repo="" tag="" tree="" gitdir="" trusted="" keyed=0
  while [ $# -gt 0 ]; do
    case "$1" in
      # No value: the key is never an argument (TheHub #62072).
      --key)      keyed=1;           shift ;;
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
  trusted_sha="$(resolve_trusted "$gitdir" "$trusted")" || exit 1
  if ! git -C "$gitdir" merge-base --is-ancestor "$commit" "$trusted_sha"; then
    die "tag ${tag} is on commit ${commit}, which is not reachable from ${trusted} (${trusted_sha}): its release.yml was never on ${trusted}, so its signature says nothing about the G5 gate"
  fi
  local floor
  floor=$(release_floor "$gitdir" "$trusted_sha" "$repo") || exit 1
  if ! git -C "$gitdir" merge-base --is-ancestor "$floor" "$commit"; then
    die "tag ${tag} is on commit ${commit}, which does not descend from the release floor ${floor}: its release.yml predates the G5 gate and could sign from injected input"
  fi
  [ "$floor" = "$RELEASE_FLOOR" ] || release_yml_gated "$gitdir" "$floor" "$commit"   # TheHub #62061
  echo "tag: ${tag} -> ${commit}, on ${trusted}, at or above the release floor ${floor:0:12}"

  command -v cosign >/dev/null 2>&1 || die "cosign is not installed; cannot verify, so this is not a pass"

  # The only step that differs between the modes. Everything above and below
  # it is shared.
  if [ "$keyed" -eq 1 ]; then
    verify_keyed "$bundle" "$manifest" "$gitdir" "$trusted" "$trusted_sha"
  else
    verify_keyless "$bundle" "$manifest" "$repo" "$tag" "$commit"
  fi

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
  *) die "usage: $0 manifest <out-file> | verify [--key] --manifest F --bundle B --repo OWNER/REPO --tag TAG --git DIR --trusted-ref REF [--tree DIR]" ;;
esac
