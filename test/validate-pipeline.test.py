#!/usr/bin/env python3
"""
Tests for the script-reference check in scripts/validate-pipeline.py. Refs: #111

A Concourse task runs from the BUILD ROOT, where the repository is the `repo/`
input. A script that names `ci/requirements.txt` without first doing `cd repo`
names a file that does not exist there -- which is how `release-preflight` failed
on its first-ever run (2026-10-11) with the file sitting on main the whole time.

Each case writes a small script into a throwaway tree and runs the REAL
`check_script_refs` over it, then the whole validator runs over the real repo:

  * the pre-fix release.sh shape (no `cd repo`) is an error, per file it names;
  * the same script after `cd repo` is clean;
  * a file that is missing from the repo is an error even from inside repo/;
  * `( cd repo && ... )` covers its own line only -- a subshell's cd does not leak;
  * a `repo/`-prefixed path from the build root is fine;
  * comments, heredoc bodies and `$VAR` paths are not references;
  * the real ci/scripts/release.sh is clean, and the real pipeline validates.

Needs PyYAML (ci/requirements.txt).

    python test/validate-pipeline.test.py
"""
import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location(
    "validate_pipeline", ROOT / "scripts" / "validate-pipeline.py")
vp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vp)

failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [ok]   {name}")
    else:
        print(f"  [FAIL] {name} {detail}")
        failures.append(name)


def refs(body, inputs=("repo",)):
    """Errors for `body` as ci/scripts/t.sh in a tree holding the usual files."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for f in ("ci/requirements.txt", "scripts/validate-manifest.py",
                  "scripts/validate-platform.py", "scripts/validate-pipeline.py",
                  "evals/run-agent-evals.sh"):
            (root / f).parent.mkdir(parents=True, exist_ok=True)
            (root / f).write_text("", encoding="utf-8")
        script = root / "ci" / "scripts" / "t.sh"
        script.parent.mkdir(parents=True, exist_ok=True)
        script.write_text(body, encoding="utf-8")
        return vp.check_script_refs(script, root, set(inputs))


PRE_FIX = """#!/usr/bin/env bash
set -euo pipefail
case "${STAGE}" in
  preflight)
    python -m pip install --quiet --disable-pip-version-check \\
      --require-hashes -r ci/requirements.txt
    python scripts/validate-manifest.py
    python scripts/validate-platform.py
    python scripts/validate-pipeline.py
    ;;
esac
"""

errs = refs(PRE_FIX)
check("pre-fix release.sh shape (no cd repo) is an error", len(errs) == 4, f"{errs}")
check("and the error names ci/requirements.txt and the build root",
      any("ci/requirements.txt" in e and "build root" in e for e in errs), f"{errs}")

errs = refs(PRE_FIX.replace("  preflight)\n", "  preflight)\n    cd repo\n"))
check("the same script after `cd repo` is clean", errs == [], f"{errs}")

errs = refs("cd repo\npython -m pip install --require-hashes -r ci/nope.txt\n"
            "bash evals/missing.sh\n")
check("files missing from the repo are errors even from inside repo/",
      len(errs) == 2 and "ci/nope.txt" in errs[0] and "evals/missing.sh" in errs[1],
      f"{errs}")

errs = refs("( cd repo && bash evals/run-agent-evals.sh )\n"
            "python scripts/validate-platform.py\n")
check("a subshell's `cd repo` covers its own line only",
      len(errs) == 1 and "scripts/validate-platform.py" in errs[0], f"{errs}")

errs = refs("( cd repo && python -m pip install \\\n    -r ci/requirements.txt \\\n"
            "    && python scripts/validate-platform.py )\n")
check("a continued subshell line is still inside repo/", errs == [], f"{errs}")

errs = refs("python repo/scripts/validate-pipeline.py\nbash repo/evals/nope.sh\n")
check("a repo/-prefixed path from the build root is checked against the repo",
      len(errs) == 1 and "repo/evals/nope.sh" in errs[0], f"{errs}")

errs = refs("bash other-input/thing.sh\n", inputs=("repo", "other-input"))
check("a path into a non-repo input is not judged", errs == [], f"{errs}")

errs = refs("# python scripts/gone.py\n"
            "cat <<'EOF'\npython scripts/gone.py\nEOF\n"
            "python3 - <<PY\nimport x  # bash nope.sh\nPY\n"
            "python \"${HERE}/x.py\"\npython -m mykronos.upload\n")
check("comments, heredoc bodies, $VAR paths and -m modules are not references",
      errs == [], f"{errs}")

errs = vp.check_script_refs(ROOT / "ci" / "scripts" / "release.sh", ROOT, {"repo"})
check("the real ci/scripts/release.sh is clean", errs == [], f"{errs}")

proc = subprocess.run([sys.executable, str(ROOT / "scripts" / "validate-pipeline.py")],
                      capture_output=True, text=True)
check("the real pipeline validates", proc.returncode == 0, proc.stdout[-800:])

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)
print("\nall passed")
