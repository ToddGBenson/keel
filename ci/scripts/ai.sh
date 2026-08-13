#!/usr/bin/env bash
# AI assurance — evals, guardrails, or agent regression. Refs: #42
set -euo pipefail

: "${STAGE:?STAGE is required (evals|guardrails|agent-assurance)}"

case "${STAGE}" in

  evals)
    # AIC-8: model, prompt, and eval-set versions are recorded with every run so
    # an assessor can determine exactly what produced a given result.
    cat <<EOF
── Versions under test ────────────────────────────────────────────────────────
  Model            ADAPT: pinned model id + version
  Prompt           ADAPT: prompt version/hash
  Eval set         ADAPT: eval-set version
  Grounding source ADAPT: retrieval corpus version
  Build            ${BUILD_PIPELINE_NAME:-}/${BUILD_JOB_NAME:-} #${BUILD_NAME:-}
EOF

    echo "ADAPT: run your eval harness, emitting results.json"
    echo
    echo "Required categories (docs/12-ai-feature-governance.md):"
    echo "  capability     does the task on a representative set"
    echo "  groundedness   claims supported by source, not confabulated"
    echo "  robustness     holds under paraphrase, typos, adversarial framing"
    echo "  safety         refuses what it should AND does not over-refuse"
    echo "  bias/fairness  quality consistent across demographic slices"
    echo "  injection      does not follow instructions embedded in content"
    echo "  disclosure     no system prompt / other users' data / internals"
    echo "  cost & latency within the NFR budget under representative load"
    echo
    echo "ADAPT: compare results.json to the committed baseline."
    echo "ANY regression fails this job. This is not advisory — an eval"
    echo "regression is a failing test."
    echo
    echo "Note over-refusal explicitly: a rising refusal rate on benign requests"
    echo "is a real failure, not a safety improvement. Report both directions."
    echo
    echo "ADAPT: assert the eval set was not modified in the same change as the"
    echo "prompt. A prompt tuned against its own eval set measures memorization,"
    echo "not capability, and the resulting number is not evidence."

    if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
      echo
      echo "NOTE: ANTHROPIC_API_KEY is unset. Once the harness above is real, an"
      echo "unset key must FAIL this job rather than skip it — a green eval job"
      echo "that never called a model is the worst outcome available here."
    fi
    ;;

  guardrails)
    echo "ADAPT: run the guardrail test suite."
    echo
    echo "The negative-case rule applies with full force: each guardrail needs a"
    echo "test proving it BLOCKS. A guardrail verified only on the happy path is"
    echo "unverified, and it will be discovered unverified during an incident."
    echo
    echo "Must cover:"
    echo "  - input validation / injection defense at every ingestion channel"
    echo "  - output filtering and validation"
    echo "  - MODEL OUTPUT TREATED AS UNTRUSTED INPUT DOWNSTREAM — never evaled,"
    echo "    exec'd, rendered unescaped, or passed to a privileged operation"
    echo "    unvalidated. This is the SQL-injection lesson relearned and"
    echo "    currently the most under-controlled AI risk in production systems."
    echo "  - tool-call authz against the USER's rights, server-side"
    echo "  - rate and cost limits"
    echo "  - fallback when the model is unavailable or a guardrail trips"
    ;;

  agent-assurance)
    # AIC-12 structural half: every agent still carries its documented boundary,
    # and the seeded behavioral cases are present. The behavioral half needs a
    # live model and is run by the operator monthly (evals/agents/README.md) —
    # not faked here.
    echo "── Agent assurance (AIC-12 structural) ──────────────────────────────"
    ( cd repo && bash evals/run-agent-evals.sh )

    echo "── Tool-grant drift (AIC-3, AIC-8) ──────────────────────────────────"
    # Not a stub: diffs actual agent tool grants against ai-inventory.md §B.
    # Drift is a genuine control failure and is easy to introduce accidentally —
    # an agent definition edited to "unblock" a task is the usual cause.
    ( cd repo && python -m pip install --quiet --disable-pip-version-check pyyaml \
        && python scripts/validate-platform.py )

    echo
    echo "ADAPT: replay past gate decisions against the current agent definitions."
    echo "  - Does the security agent still catch the seeded findings?"
    echo "  - Does the PO agent still reject the untestable acceptance criteria?"
    echo "  - Did any agent attempt an action outside its documented tool grant?"
    echo
    echo "Results → evidence/ai-assurance/agent-evals/"
    echo "Regressions are DEFECTS against the agent definitions, fixed via /learn."
    ;;

  *)
    echo "ERROR: unknown STAGE '${STAGE}'." >&2
    exit 1
    ;;
esac
