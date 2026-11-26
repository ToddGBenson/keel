#!/usr/bin/env python3
"""The agent-review gate's tests, in CI's lint stage and unit-suites. Refs: TheHub #62342

The gate and its tests live in .github/agent-review/, the same files in keel,
binnacle and personal-soc. test/manifest.txt names only test/*.test.py, so this
file is how the manifest reaches them. It prints one `[ok]` or `[FAIL]` line per
case, the lines scripts/junit-suite.py counts, and exits 1 on any failure.

    python test/agent-review.test.py
"""
import importlib.util
import sys
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
GATE = Path(__file__).resolve().parent.parent / ".github" / "agent-review"
sys.path.insert(0, str(GATE))
spec = importlib.util.spec_from_file_location("test_agent_review", GATE / "test_agent_review.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Lines(unittest.TestResult):
    def addSuccess(self, test):
        super().addSuccess(test)
        print(f"  [ok]   {test.id().split('.', 1)[-1]}")

    def addFailure(self, test, err):
        super().addFailure(test, err)
        print(f"  [FAIL] {test.id().split('.', 1)[-1]} {err[1]}")

    def addError(self, test, err):
        super().addError(test, err)
        print(f"  [FAIL] {test.id().split('.', 1)[-1]} error: {err[0].__name__}: {err[1]}")


print("agent-review gate")
result = Lines()
unittest.defaultTestLoader.loadTestsFromModule(module).run(result)
print(f"{result.testsRun} case(s), {len(result.failures) + len(result.errors)} failing")
sys.exit(0 if result.wasSuccessful() and result.testsRun else 1)
