#!/usr/bin/env python3
"""The agent-review gate's tests, in CI's lint stage. Refs: TheHub #62342

The gate and its tests live in .github/agent-review/, the same files in keel,
binnacle and personal-soc. test/manifest.txt names only test/*.test.py, so this
file is how the manifest reaches them.

    python test/agent-review.test.py
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.exit(subprocess.run(
    [sys.executable, str(ROOT / ".github" / "agent-review" / "test_agent_review.py")]
).returncode)
