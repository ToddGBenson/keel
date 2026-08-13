#!/usr/bin/env bash
# Continuous monitoring & evidence collection. Refs: #42
#
# Scheduled rather than event-driven, because the risk changes while your code
# does not. A clean scan at build time says nothing about a CVE published
# yesterday.
set -euo pipefail

: "${PERIOD:?PERIOD is required (daily|weekly|monthly|metrics)}"

# ── CADENCE NOTE ──────────────────────────────────────────────────────────────
# Concourse's bundled `time` resource has interval, start/stop and day-of-week.
# It has no day-of-month, so there is no way to express "monthly" as a trigger
# without taking on a third-party resource type — which this pipeline
# deliberately does not do.
#
# The monthly job therefore fires weekly and returns early on the other three
# Mondays. That early return is LOUD: a build that was not due says so in its
# output, so "we did not look this week" can never be mistaken for "we looked and
# found nothing". A silent no-op here would be the exact defect class this
# repository keeps rediscovering (L0007, L0008).
if [ "${PERIOD}" = "monthly" ]; then
  DOM="$(date -u +%d)"
  if [ "${DOM#0}" -gt 7 ]; then
    cat <<EOF

================================================================================
MONTHLY BUNDLE NOT DUE — today is day ${DOM} of the month.

This job fires weekly and executes on the first Monday only. Nothing was
assessed in this run. This is a scheduling no-op, NOT a clean monthly result,
and it must not be cited as evidence for CA-7 for this month.

Next execution: the first Monday of the coming month.
================================================================================

EOF
    exit 0
  fi
  echo "First Monday of the month — running the monthly bundle."
fi

case "${PERIOD}" in

  daily)
    echo "── Daily — deployed artifact rescan (RA-5, SI-2) ────────────────────"
    echo "ADAPT: pull the SBOM for what is actually running in production and"
    echo "query it against current advisory feeds."
    echo
    echo "This is different from scanning the repo. The repo tells you about the"
    echo "code; this tells you about what your users are exposed to right now."
    echo
    echo "ADAPT: open an issue per new Critical/High with the severity SLA as the"
    echo "due date (Critical 7d, High 30d), and create the POA&M entry."
    echo
    echo "ADAPT: query open findings past their SLA date."
    echo "Escalate past-due Critical/High to a human immediately — do not wait"
    echo "for the weekly review. An aging chart that only goes up is the clearest"
    echo "early signal of a team that has stopped being able to absorb its own risk."
    ;;

  weekly)
    echo "── Weekly — drift, secrets, exceptions (CM-2, CM-6, IA-5) ───────────"
    echo "ADAPT: diff running configuration against the IaC baseline."
    echo "Any drift → investigate."
    echo
    echo "ADAPT: gitleaks over the complete history, not just the recent diff."
    echo
    echo "ADAPT: report suppressions and security exceptions within 14 days of"
    echo "expiry, plus certificates and secrets within 30 days (IA-5, SC-12)."
    echo
    echo "Automatic renewal is prohibited. An expiring exception is a decision"
    echo "that has to be made again, deliberately."
    echo
    echo "ADAPT: POA&M health — report three things, in this order:"
    echo "  1. entries past due"
    echo "  2. entries extended MORE THAN ONCE (a resourcing or will problem, not"
    echo "     a schedule problem — name it as one)"
    echo "  3. entries closed without evidence of remediation"
    ;;

  monthly)
    echo "── Monthly — SBOM refresh, agent assurance, evidence integrity ──────"
    echo "ADAPT: regenerate the SBOM for deployed artifacts and re-query (CM-8)."
    echo
    echo "ADAPT: flag components past end-of-life or without a maintenance"
    echo "signal (SA-22). These enter intake as scheduled chores — scheduled,"
    echo "not deferred."
    echo

    echo "── Agent tool-grant audit (AIC-3, AIC-8) ────────────────────────────"
    ( cd repo && python -m pip install --quiet --disable-pip-version-check pyyaml \
        && python scripts/validate-platform.py )

    echo "── Guard hook self-test (CA-2) ──────────────────────────────────────"
    ( cd repo && bash .claude/hooks/selftest.sh )

    echo "── Agent assurance (AIC-12 structural) ──────────────────────────────"
    ( cd repo && bash evals/run-agent-evals.sh )

    echo
    echo "ADAPT: role / artifact mismatch audit (POAM-001 compensating control)."
    echo "Sample merged PRs; cross-check the declared producing agent against the"
    echo "paths that PR changed, using ai-inventory.md §B expected scope."
    echo
    echo "  e.g. a PR declaring 'product-owner' that modified src/** is a role"
    echo "       violation — the boundary is prompt-enforced only, so this audit"
    echo "       is the DETECTION half of the control. Flag, do not assume"
    echo "       malice: the usual cause is a command invoking the wrong agent."
    echo
    echo "If it never fires, confirm it still works rather than concluding the"
    echo "boundary is holding."
    echo
    echo "ADAPT: AI provenance audit (AIC-6). Sample merged PRs from the last"
    echo "month; confirm AI authorship declarations are present and non-trivial."
    echo
    echo "Also compute the divergence metric: do AI-authored changes fail review"
    echo "or escape to production at a different rate than human-authored ones?"
    echo "This is diagnostic, not punitive — it calibrates review depth on evidence."
    echo
    echo "ADAPT: evidence integrity check (AU-9). Verify gate evidence bundles"
    echo "exist for everything released this month, are retrievable, within"
    echo "retention, and were not hand-edited."
    echo
    echo "Then READ a sample. Evidence that exists but does not support the claim"
    echo "is the most common finding in a mature program, and it survives for"
    echo "years precisely because nobody opens the file."
    ;;

  metrics)
    echo "── Metrics snapshot for the retro ───────────────────────────────────"
    echo "ADAPT: snapshot to evidence/retros/<period>/metrics.json"
    echo
    echo "  Flow (DORA):  deployment frequency, lead time, change failure rate,"
    echo "                time to restore, queue time by state"
    echo "  Quality:      escaped defects, GATE REJECTION RATE BY GATE, flaky"
    echo "                tests, PR review latency"
    echo "  Security:     new findings by severity, MTTR, past SLA"
    echo "  AI assurance: eval pass rate, drift events, agent gate rejections"
    echo "  Process:      emergency changes used, exceptions raised, gates skipped"
    echo
    echo "NEVER collect velocity, story points, or per-person commit counts. They"
    echo "are trivially gamed, and measuring them corrupts the estimates the whole"
    echo "process depends on within one sprint."
    ;;

  *)
    echo "ERROR: unknown PERIOD '${PERIOD}'." >&2
    exit 1
    ;;
esac
