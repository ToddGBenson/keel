# 08 — Operate, Monitor & Respond

**Owner:** whole team · **Primary controls:** SI-2, SI-4, RA-5, RA-7, IR-4, IR-5, IR-6,
IR-8, AU-6, CA-7, CP-9, CP-10

Delivery does not end at deploy. Most of a system's life is spent in operation, and most of
its risk accrues there.

## Continuous monitoring (CA-7)

| Signal | Source | Threshold → action |
|---|---|---|
| Error rate | APM | >2× baseline for 5 min → page |
| Latency p95/p99 | APM | breach of NFR for 10 min → page |
| Saturation (CPU/mem/conn/queue) | infra metrics | >80% sustained → alert |
| Failed authentication rate | auth logs | anomalous spike → security alert (AU-6, SI-4) |
| Authorization denials | app audit log | anomalous spike → possible probing |
| New dependency CVE | daily rescan of deployed SBOM | Critical → immediate triage (SI-2) |
| Configuration drift | weekly baseline diff | any drift → investigate (CM-2, CM-6) |
| Certificate/secret expiry | inventory | 30 days out → task (IA-5, SC-12) |
| AI eval drift | scheduled eval run | regression vs. baseline → AI Risk triage |
| AI guardrail trigger rate | app telemetry | anomalous spike → AI incident triage |
| Unsigned or unverified artifact | deploy verification | any → hard block (SI-7) |

**Alert discipline.** Every alert names the condition, the impact, and the runbook. An
alert with no action is deleted, not muted — muted alerts train people to ignore the
channel, and the one that mattered arrives in that channel. Alert fatigue is a security
control failure, and it is reviewed at every retro.

## Vulnerability management (RA-5, SI-2)

```
Discover ──▶ Triage ──▶ Prioritize ──▶ Remediate ──▶ Verify ──▶ Record
 scans        real?      severity ×     patch /       rescan +   POA&M
 disclosures  reachable? exposure       mitigate      test       closed
 pentest      exploited?  (not CVSS
 research                  alone)
```

**Triage on reachability and exposure, not CVSS alone.** A Critical CVE in a code path that
is never invoked, behind authentication, on an internal service is a lower real risk than a
Medium in an unauthenticated public endpoint. Record the reasoning — a decision you cannot
reconstruct in six months is a decision an assessor will treat as arbitrary.

SLAs are in `05-verification.md` § Severity. Anything past SLA appears in the weekly review
and the quarterly assessment. An aging chart that only goes up is the clearest early signal
of a team that has stopped being able to absorb its own risk.

**Risk acceptance** is time-boxed, human-approved, POA&M-tracked, with a compensating
control named and a review date. Indefinite acceptance is not acceptance; it is a decision
to carry the risk permanently without saying so, and it should be written that way if that
is what is meant.

## Incident response (IR-4, IR-8)

```
DETECT ──▶ TRIAGE ──▶ CONTAIN ──▶ ERADICATE ──▶ RECOVER ──▶ LEARN
           severity   stop the    remove the    restore     blameless
           + IC named  bleeding   cause         + verify    postmortem
```

**Roles during an incident:** Incident Commander (decides; does not fix), Operations Lead
(fixes), Communications Lead (informs), Scribe (records the timeline as it happens — not
reconstructed afterward, because reconstruction is where the truth quietly changes).

**Severity:** SEV1 total outage or confirmed data breach · SEV2 major degradation or
suspected compromise · SEV3 minor degradation with a workaround · SEV4 negligible impact.

**Security incidents** additionally require: evidence preservation before remediation
(remediating first destroys the forensic record — snapshot, then fix), regulatory
notification assessment against the clock that applies (IR-6), and the disclosure decision
made by a human with authority, not by the responders.

**AI incidents** — harmful, biased, wildly incorrect, or leaked output; guardrail bypass;
prompt-injection success; model behavior change after a provider update — follow the same
path with the AI Risk Officer as a required participant. See `12-ai-feature-governance.md`.

## Blameless postmortem (IR-4, feeds the retro loop)

Required for SEV1 and SEV2, and for any near-miss worth the hour. Within five business
days, at `evidence/incidents/<id>/postmortem.md`.

**Blameless means the analysis stops at conditions, not at people.** "The engineer deployed
without checking" is not a root cause; it is a restatement of the event. The causes are:
what made that action easy, what made the wrong outcome invisible, and what allowed a
single mistake to reach production. Those have fixes. Blame does not.

Contents: timeline (detection → resolution, with times), impact (who, how many, how long),
contributing conditions (plural — single-cause incidents are rare and the search usually
stopped early), what went well (worth protecting deliberately), what was luck (the most
important section — luck is not a control and will not recur), and action items.

**Every action item has an owner, a due date, and an issue.** Postmortem actions enter the
backlog through normal intake with elevated priority. An action list with no issues behind
it is a document that will be read once.

## Backup, recovery, continuity (CP-9, CP-10)

Backups are automated, encrypted, access-controlled, and **restore-tested on a schedule**.
An untested backup is a belief. Recovery objectives (RTO/RPO) are stated per service and
verified by exercise, not by architecture diagram.

## Data lifecycle

Retention per `10-definitions.md`. Secure disposal at end of life (MP-6). Personal data is
minimized at collection, not cleaned up later — the cheapest way to protect data is not to
hold it. Retention beyond the stated period is a compliance finding, including in logs and
in backups, which is where it usually hides.

## Feeding the improvement loop

Operations is the richest source of process improvement, because it is where the process's
assumptions meet reality. Route into `/retro` and `/learn`: incident causes, alert quality,
recurring toil, remediation SLA misses, drift patterns, and every gate that passed
something operations later had to catch.

That last one is the sharpest question this process asks of itself: **what reached
production that a gate should have stopped, and which gate was it?**

## The observability loop closes on the backlog, not on a dashboard

`/retro` and `/learn` are **human-triggered**, which means the loop only closes when somebody
remembers to close it. Production signal does not wait for a ceremony, and the signals that
matter least are the ones that arrive loudest.

**`delivery-lead` owns this loop** and runs it on a fixed cadence, not on inspiration. The
output is a backlog item or an explicit decision not to act — never a note in a dashboard nobody
opens.

| Signal | Where it comes from | What it becomes |
|---|---|---|
| SLO burn / error budget spent | monitoring | A story, prioritised against features, not after them |
| An alert that fired and needed no action | alert review | A change to the alert, or its deletion |
| An alert that should have fired and did not | incident timeline | A detection gap — a story, and a POA&M entry if it is a control |
| Toil performed more than twice | operator log | An automation story, or an explicit decision to keep doing it by hand |
| A gate that passed something operations caught | postmortem | A gate criterion change via `/learn`, and a lesson if it generalises |
| Latency, cost or error-rate drift | telemetry trend | An NFR the architecture never stated — back to `architect` |
| An AI feature's output quality moving | eval baselines | A re-run of the eval suite; `ai-risk-officer` decides if the tier changed |

**The rule that makes this a loop rather than a report:** every item above leaves the review
with an issue number or a recorded decision not to raise one. A signal reviewed and dropped
silently is indistinguishable from a signal nobody looked at, and six weeks later nobody can
tell you which it was.

**What to resist.** The failure mode here is a backlog full of observability noise that crowds
out product work and trains everyone to ignore the label. Prefer deleting a bad alert to writing
a story about it. Prefer one story about a class of toil to seven about instances. And when the
honest answer is *we are choosing to live with this*, record that — it is a decision, and it
should be re-read at the next quarterly assessment rather than rediscovered as a surprise.
