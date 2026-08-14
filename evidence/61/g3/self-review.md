# Self-review — #61

Mode: solo (POAM-008)
PR: #62   Author: Todd Benson (claude-opus-5, AI-authored)   Date: 2026-08-14

Correcting the register after the repository was made public. Two closures, one refusal to
close, one new entry.

## Verified independently

- **Every closure rests on a measurement taken after the change, not on the change itself.**
  `secret_scanning` and `secret_scanning_push_protection` both read `enabled` from the API.
  `production` returns `required_reviewers` with reviewer `ToddGBenson`. A dispatched `CI` run
  executed on `GitHub Actions` hosted runners with `ubuntu-latest` labels and passed all three
  jobs.
- **The `required_reviewers` restoration was checked, not assumed.** POAM-006's plan said to
  re-add it by hand. I read the environment before touching anything and the rule was already
  back, with a reviewer attached. The plan's work was never done because it was never needed.
- **POAM-006's closure is tied to something that actually uses it.** `release.yml`'s
  `authorize-and-deploy` job declares `environment: production`, so the reviewer gate has a
  consumer. A reviewer rule on an environment nothing references would be decoration.
- **The refusal to close POAM-010 is evidence-based.** `fly builds -j keel/release-preflight`
  and `-j keel/authorize-release` both return **nothing** — no builds at all. The release path
  ADR-0004 designates has never executed.
- **Pre-publication scan.** The nine private-era commits and the whole tracked tree were
  searched for private-key headers, `ghp_`/`gho_`/`github_pat_`, `hvs.`, `AKIA`, and `xox*`
  tokens. No hits; every `webhook_token` is a `((var))` placeholder.

## Agent findings

**None — no three-pass agent review.** Consistent with #48, #50, #52, #56 and #58.

**If one thing gets an independent read, make it the POAM-010 refusal.** Its stated dependency
is satisfied, so closing it would survive a casual audit and would be wrong.

## Not verified

- **Nothing confirms the `production` reviewer gate would actually stop a release**, because no
  release has been attempted. POAM-006 is closed on the rule existing and being referenced —
  which is what its weakness was about — not on watching a deployment block. A reviewer gate
  that is configured and never exercised is a weaker claim than one that has held.
- **`release-preflight` and `authorize-release` still have never run.** Carried forward from
  #56 and #58, and it is now load-bearing: it is the reason POAM-010 stays open.
- **POAM-016 is filed, not investigated.** I know the two release paths disagree; I have not
  worked out which one should survive.
- **The pre-publication scan was pattern-based**, so it finds credentials shaped like known
  providers. A bespoke secret — an internal URL with an embedded key, a base64 blob — would not
  match. `gitleaks` is not installed locally; the Concourse `secrets` lane covers `main` and
  passed on `4a3e4b6`, which is the same content.

## Cold-read notes

- **What I did not want to look at:** POAM-010 was the entry I most wanted to close. Three
  reopened entries and two closing looks tidy; one left open looks like unfinished work. The
  argument for closing it is genuinely good — its own stated dependency is satisfied — and that
  is exactly what made it worth resisting. The register is not a scoreboard.
- **The POAM-006 lesson is about plans, not permissions.** Its remediation described manual work
  that turned out to be unnecessary. Nobody would have noticed if I had closed it claiming that
  work was done. Remediation plans are estimates written when a finding is fresh, and they go
  stale like anything else.
- **I have now recorded a correction to my own correction.** POAM-014's note says making the
  repository public would close POAM-005/006/010 "with it". Two of three closed; POAM-010 did
  not. The original claim was directionally right and specifically wrong, which is the most
  durable kind of wrong.

## Residual risk accepted

- Single-identity review, no agent passes, on a change to the compliance register itself.
- Two entries closed on configuration state rather than on exercised behaviour.
- The self-hosted runner remains in place though it is now redundant; removal has an ordering
  hazard recorded in POAM-014 and was deliberately not attempted here.
- Next external sample review due: 2026-10-01.
