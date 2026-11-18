# Self-review — TheHub #62001 (the compliance and process docs state main's protection as it is)

Mode: solo (POAM-008); agent self-review, pending the independent review before merge
PR: #200   Pair: binnacle #94   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-18
verdict: pass

The docs claimed branch protection that is not in force: `enforce_admins: true`, signed commits,
required approvals, "all checks required". They also cited branch protection as the thing that
backs no-self-approval and no-merge. This change makes every current-state claim match what the
API returns today, dates it, and names the story for each planned control. Text-only: no hook, CI,
settings or protection change.

## The live state, read 2026-11-18T07:10Z and again at 10:20Z (keel and binnacle alike)

`GET repos/ToddGBenson/<repo>/branches/main/protection` and `GET .../rulesets`:

- **Reviews:** `required_approving_review_count` 0 (`dismiss_stale_reviews` true, no code-owner
  reviews, no last-push approval).
- **Bypass and signing:** `enforce_admins` false; `required_signatures` false.
- **Required checks:** `Concourse / <repo>` and `library-allowlist`, both pinned to App 4551328,
  `strict: true`.
- **Still on:** linear history; no force-push; no deletion; conversation resolution.
- **Rulesets:** none (`[]`).
- **Commit signatures:** the last 20 commits on `main` in each repo are `verified=true`, because
  GitHub signs the squash merges it creates (committer GitHub). That attests the merge, not the
  author.

## The change (three commits)

1. **Template and checker** (review of #193):
   - The PR template's closing-keyword line now says GitHub also closes on Fix, Fixed, Close, Closed,
     Resolve and Resolved, while the record lookup reads only three.
   - It says where the checker's rules run: a fork that restores `pr-governance.yml`. Nothing in
     keel runs it.
   - `scripts/selfreview-check.js` says the building agent runs `/self-review` and writes the record,
     not "Run `/self-review N`". `test/selfreview-check.test.js` passes 33 / 0.
2. **Compliance maps and the POAM:**
   - CIS 1.1.2, 1.1.7, 1.1.9, 1.1.11, 1.1.12 and 1.1.13 are corrected; 1.1.9 and 1.1.12 are now not
     met.
   - NIST SA-10 and CM-5, SSDF PS.1 and the evidence model no longer claim signed commits or no
     admin bypass.
   - The AC-5 assessment test now attempts what matters: approving and merging a PR the agent did
     not open.
   - POAM-008's "still enforced" text gets a dated live-state note. The POAM-014 row records the live
     checks and TheHub #62015. The POAM-009 row says `required_signatures` was turned off after its
     closure.
3. **Process docs:**
   - docs/13 gets a "main today" column, and its "`enforce_admins` stays true" and "machine can
     require" claims say what holds.
   - Also corrected: docs/11 AIC-10, SECURITY.md, docs/01, docs/06, SETUP.md (a pointer), README,
     CONTRIBUTING, docs/00, docs/16, docs/18, OPERATING.md and docs/07.
   - ci/README.md gets a dated 2026-11-18 reading on top of its dated ones.

Dated historical sections, evidence records and lessons are records of their time and are left as
written. ADRs are decision records and are left too.

## Verified independently

- Every changed claim was checked against the two API reads above. The signature claim was checked
  against `GET commits?sha=main` (`commit.verification`).
- The tests that read these files pass: poam, poam-wiring, control-liveness, control-liveness-keel,
  validate-platform, test-manifest and selfreview-check. `scripts/control-liveness.py --check` shows
  no regression (17 claims cite a gate that has never fired, as at baseline). Pinned gitleaks: no
  leaks.

## Not verified

- No assessor has read the corrected maps. Their status emojis (✅, 🟡, ❌) are this record's
  judgement.
- The wording in docs not touched here (other docs/, process/, the skills) was swept for these
  controls by grep, not read line by line.

## Flags for the operator (not changed here)

- **POAM-010 and POAM-014 fall due 2026-11-21.** Neither was re-dated.
- **POAM-014's closure condition** names `independent-review`; the live required checks are
  `Concourse / keel` and `library-allowlist`.
- **POAM-009 is marked Closed**, but `required_signatures` is off today. Whether to reopen it is the
  operator's decision.
- **Planned controls named in the docs:** TheHub #61006 (rulesets), #61039 (agent identity), #62015
  (a green check that ran no suites).

## Residual risk accepted

The gaps the docs now state plainly, until #61006 and #61039 land.
