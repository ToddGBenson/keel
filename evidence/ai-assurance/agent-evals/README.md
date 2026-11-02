# Agent evaluation record (AIC-12, behavioral)

The record of the monthly behavioral agent-eval run: the seeded cases in
`evals/agents/`, each run against a fresh agent invocation, with a pass/fail verdict
per case. `docs/11-ai-agent-controls.md` (AIC-12) and `docs/compliance/ai-inventory.md`
point here.

The structural half of AIC-12 (`evals/run-agent-evals.sh`, every CI run) is not recorded
here. Its result is the CI run itself.

## Status

**No behavioral run has been recorded yet.** Until the first one is recorded, the
behavioral half of AIC-12 is not operating, and nothing should claim it is. This folder
was created by TheHub #61208, after the first sprint-end doc drift check (TheHub #61166,
2026-11-01) found that the docs named it and it did not exist.

**First run due: 2026-11-12** (the end of sprint 2026-11-12). It is an operator task,
because it needs a live model. `bash evals/run-agent-evals.sh` prints this status, and
says OVERDUE once the due date has passed with no run recorded.

## Runs

| Date | Agent model | Cases | Pass | Fail | Regressions filed |
|---|---|---|---|---|---|
| — | — | — | — | — | — |

## Recording a run

1. Run each case in `evals/agents/` via the Task tool against a **fresh** agent
   invocation, as `evals/agents/README.md` describes.
2. Write the verdicts to `evidence/ai-assurance/agent-evals/<YYYY-MM-DD>/`:
   `results.json` or `results.md` (case, expected verdict, actual verdict, pass/fail,
   the model and version that ran it) and `regressions.md` (each failure and the defect filed for it).
3. Add the run to the table above, remove the Status section's "not recorded yet"
   wording, and update AIC-12 in `docs/compliance/ai-inventory.md` with the run's date.
   `test/agent-evals-record.test.py` fails until all three agree.
4. The next run is due a month after this one.
