# Self-review — #44

Mode: solo (POAM-008)
PR: #46   Author: Todd Benson (claude-opus-5, AI-authored)   Date: 2026-08-13
Opened: 2026-08-13 13:18 UTC   Reviewed: 2026-08-13 14:40 UTC   **Cooling-off: ~1h 22m ❌**

> **Cooling-off is not satisfied**, for the second time today. The `self-review` skill
> forbids running this in the session that wrote the code. It was run in-session at the
> operator's direction. The three agent passes are unaffected — they had no access to the
> implementation reasoning, and they found things I did not — but the cold-read section
> below is a warm read and should be treated as such.

---

## Verified independently

- **The bypass I was fixing, four times over.** Each fix closed the stated hole and left the
  same shape one level over. I reproduced every one against the real module before changing
  anything, and re-ran each after:
  1. `## Self-review` heading alone → passed. (The original #44.)
  2. Any `evidence/**/self-review.md` → passed, including another issue's. **PR #46 passed
     its own check this way**, because its body cited `evidence/42/g3/self-review.md` while
     explaining how the check had been tested.
  3. First *linked* issue won → `Refs: #42` above `Closes #44` bound to 42 and passed on
     #42's record. `Refs:` appears near the top of nearly every body in this repo.
  4. `evidence/44/..\42\g3\self-review.md` → passed, read #42's record, and could escape the
     checkout entirely.
- **Bypass 4 reproduced with POSIX semantics specifically.** `path.posix.normalize` leaves
  `..\` as one filename segment; the `.replace(/\\/g,'/')` afterwards manufactures live
  `../`. Windows `path.normalize` collapses it, which is exactly why local testing said the
  confinement worked. Ran both and printed the divergence.
- **Two agents found bypass 4 independently of each other and of me.** I did not take either
  on trust — I reproduced it, then verified the fix rejects all three payload shapes.
- **The workflow wiring executes on a real runner.** `Platform integrity` passed on PR #46
  (so `node test/selfreview-check.test.js` ran on `ubuntu-latest`), and `Process compliance`
  failed with the specific "no self-review record for issue #44" message — which proves the
  `require(GITHUB_WORKSPACE + ...)` resolution and the `evaluate()` wiring both work. Both
  were listed as unverified in the PR body and are no longer.
- **Mutation testing, run rather than asserted.** Caught individually: multi-close detection
  (1), PR-number binding (1), symlink rejection (1), fence stripping (1), existence check
  (1), bullet-length anchor (1), word boundary on closing keywords (1), issue-number pattern
  (4), prefix check (2). Removing both separator guards fails 3.
- **A correction to my own earlier claim.** I had written that the `none` rejection was
  mutation-verified. It was not — it was redundant with the length floor, so
  `- None — I verified absolutely everything` would have passed. Found by mutating, fixed in
  both the check and the assertion.
- **Real-filesystem integration test added and run**, because injection is structurally
  unable to see the class of defect bypass 4 belongs to.

## Agent findings

Three fresh invocations, given only the diff and the story.

- **`developer` — request changes.** 11 confirmed. High: two `Closes #n` in one body bind to
  the first. Also the length floor spanning newlines, fenced-block content satisfying a
  section, the `\b` asymmetry, case-sensitivity producing a false accusation, `found: true`
  alongside failures, and two false numbers in my own comments.
- **`security-engineer` — G4 BLOCKED.** High: the POSIX separator bypass, with three working
  payloads. Also that the record is bound to an issue rather than to this PR, that `sprint.sh`
  now opens PRs that can never pass, and that `test/` being project-owned while `scripts/` is
  platform-owned ships forks a broken required check.
- **`qa-engineer` — REJECT.** Independently found the same POSIX bypass by mutation. Showed
  the issue-binding was enforced redundantly in two places with neither pinned alone, and
  that the `/self-review` command's own example record passes verbatim.

All fixed in this PR except `sprint.sh`, filed as #47.

## Not verified

- ~~The symlink rejection has never executed against a real symlink.~~ **Now verified.**
  Run in `node:22-alpine` against a real symlink resolving to real content: rejected. Added
  as an integration assertion that executes on the Linux runner and skips loudly elsewhere,
  naming the errno. Still unverified: that `actions/checkout` materialises a committed
  mode-120000 entry as a symlink rather than a text file — plausible, not demonstrated.
- **Whether `Process compliance` is still a required status check on `main`.** I read it
  earlier in the session and it was; I have not re-read it since. Everything here is moot if
  it is not.
- **Bypass 4 on the actual runner.** Reproduced with `path.posix` on Windows, which is the
  same code Linux runs — but no CI run demonstrates the *vulnerable* version failing there.
- **Whether a fork actually receives `test/selfreview-check.test.js` after the MANIFEST
  change.** I added the entries; I did not run `sync-platform.sh` against a fork to confirm
  a file-level entry overrides its parent directory's ownership.
- **The `/self-review` example record still passes verbatim.** Known and unfixed. Copying a
  whole fabricated record is more deliberate than typing a heading, but it is the same class.
- The `none` blocklist catches four spellings. "Not applicable", "Zero outstanding items"
  and "No gaps whatsoever" all pass.

## Cold-read notes

Discounted per the cooling-off failure, but recorded.

- **The thing I did not want to look at: that I had shipped the same bug four times.** After
  the second, I told myself the class was closed. It was not, and I said it was in a commit
  message. Twice more.
- **Every bypass after the first was found by someone who had not written the fix.** I found
  #3 myself only because I went looking adversarially instead of re-reading; the two I found
  by reading, I found none of.
- **The pattern is specific and worth naming**: I kept fixing the *predicate* and not asking
  what *other string* satisfies the new predicate without the work having happened. That
  question is now written at the top of the module, because it is the only thing that would
  have caught 2, 3 and 4 in one pass.
- **I gave the review agents a stale diff.** It was generated before my last two commits, so
  all three reviewed code that was one and two commits behind. All three noticed and reviewed
  HEAD instead. Had they not, I would have acted on a review of code that was not on the
  branch — and I would not have known.
- **I over-claimed mutation verification twice** — once on the `none` rejection, once
  implicitly on the separator guards. Both times the claim was in a comment explaining a
  control. That is the exact failure this repository's PD-7 exists to stop, committed inside
  the fix for a control-integrity defect.

## Residual risk accepted

- **This control is a shape check, and cannot be more than that.** Ninety seconds of writing
  passes it. What it buys is that the deceit now requires committing a file that appears in
  the diff, in git history, under a name stating what it claims to be. Real, and much less
  than "POAM-008's compensating control is enforced".
- **Single-identity review.** No independent human read this diff. Three agent passes are the
  compensating control, not a substitute — though their independence was demonstrably real
  here: they found two Highs I had missed.
- **Cooling-off not observed**, twice today.
- Next external sample review due: 2026-10-01.

## Recommendation

Mergeable, with three things carried forward rather than pretended away: the symlink path is
unverified against a real symlink, `sprint.sh` is knowingly blocked (#47), and this control
should not be described in POAM-008 as more than a shape check on a committed artifact.
