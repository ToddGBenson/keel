'use strict';
// Tests for the solo-mode self-review check. Refs: #44
//
// Almost every assertion is a NEGATIVE case — the branch proving the control
// denies. That is the point: this check is the entire substitute for a second
// reviewer's approval under POAM-008, and it shipped passing on a markdown
// heading that the PR template tells authors to write.
//
// Two regressions are pinned here, both found in production rather than review:
//   1. a bare "## Self-review" heading satisfied the check (the original #44)
//   2. ANY evidence/**/self-review.md satisfied it, including another issue's —
//      which is how the PR introducing this very check passed its own check
//
// Mutation-verified: removing the path confinement, the existence check, the
// section-content test, the none-rejection, the length floor, or the
// issue-number match each fails at least one assertion below.
//
//   node test/selfreview-check.test.js

const assert = require('assert');
const { evaluate, sectionFilled, resolveRecordPath, linkedIssue } =
  require('../scripts/selfreview-check.js');

let passed = 0;
let failed = 0;

function check(name, fn) {
  try {
    fn();
    console.log(`  [ok]   ${name}`);
    passed++;
  } catch (err) {
    console.log(`  [FAIL] ${name}\n         ${err.message}`);
    failed++;
  }
}

const GOOD_RECORD = [
  '# Self-review — #42',
  '',
  '## Verified independently',
  '- Ran fly validate-pipeline and read the output rather than the badge',
  '',
  '## Not verified',
  '- The Mykronos ingestion path has never executed end to end. Unverified.',
  '',
  '## Cold-read notes',
  '- I verified what I built and trusted what I copied; every defect was copied.',
  '',
].join('\n');

// Injected filesystem that explodes if reached — so any assertion using it also
// proves the check rejected the input BEFORE touching the disk.
const noFs = {
  exists: () => { throw new Error('exists() must not be called on this path'); },
  readFile: () => { throw new Error('readFile() must not be called on this path'); },
};

const withRecord = (record) => ({ exists: () => true, readFile: () => record });
const body = (...lines) => lines.join('\n');

// ── REGRESSION 1: a heading is not a record ─────────────────────────────────
check('a bare "## Self-review" heading is NOT a record', () => {
  const r = evaluate({
    body: body('Closes #42', '', '## Self-review', '', 'No record exists yet.'),
    title: 'fix: thing', prNumber: 43, ...noFs,
  });
  assert.strictEqual(r.found, false);
  assert.strictEqual(r.failures.length, 1, 'must fail');
  assert.match(r.failures[0], /heading alone is not a record/i);
});

check('a body honestly stating the record is absent still fails', () => {
  // The exact wording that passed on PR #43.
  const r = evaluate({
    body: body('Closes #42', '', '## Self-review', '',
               '*(deliberately absent)* — no self-review record exists yet.'),
    title: 'fix: thing', prNumber: 43, ...noFs,
  });
  assert.strictEqual(r.failures.length, 1);
});

check('no mention of a self-review at all fails', () => {
  const r = evaluate({
    body: body('Closes #42', '', '## What I made worse', '', 'Nothing.'),
    title: 'fix: thing', prNumber: 1, ...noFs,
  });
  assert.strictEqual(r.failures.length, 1);
});

// ── REGRESSION 2: another issue's record is not this issue's review ─────────
check("another issue's record does NOT satisfy this PR", () => {
  // Exactly how PR #46 passed its own check: the body mentioned #42's record in
  // a sentence explaining how the check had been tested.
  const r = evaluate({
    body: body('Closes #44', '',
               'Verified against the real evidence/42/g3/self-review.md as a control.'),
    title: 'fix(governance): require a record', prNumber: 46, ...noFs,
  });
  assert.strictEqual(r.found, false, "must not accept another issue's record");
  assert.match(r.failures[0], /belongs to a different issue/i);
});

check('a PR with no linked issue fails rather than searching', () => {
  const r = evaluate({
    body: 'no issue here', title: 'chore: thing', prNumber: 9, ...noFs,
  });
  assert.strictEqual(r.found, false);
  assert.match(r.failures[0], /No linked issue/i);
});

check('linkedIssue accepts the documented forms', () => {
  assert.strictEqual(linkedIssue('Closes #42', ''), '42');
  assert.strictEqual(linkedIssue('Refs: #7', ''), '7');
  assert.strictEqual(linkedIssue('nothing', 'fix(x): thing #13'), '13');
  assert.strictEqual(linkedIssue('nothing', 'no number'), null);
});

// ── The link must point at something real ──────────────────────────────────
check('a linked record that does not exist fails', () => {
  const r = evaluate({
    body: body('Closes #42', '', 'See evidence/42/g3/self-review.md'),
    title: 'fix: thing', prNumber: 43,
    exists: () => false,
    readFile: () => { throw new Error('should not read a missing file'); },
  });
  assert.strictEqual(r.found, false);
  assert.match(r.failures[0], /not in the repository/i);
});

// ── Path confinement (PD-6) ────────────────────────────────────────────────
check('traversal outside evidence/ is rejected without touching the filesystem', () => {
  const r = evaluate({
    body: body('Closes #42', '', 'See evidence/42/../../../tmp/self-review.md'),
    title: 'fix: thing', prNumber: 43, ...noFs,
  });
  assert.strictEqual(r.recordPath, null);
  assert.strictEqual(r.failures.length, 1);
});

check('resolveRecordPath normalises, confines, and requires the issue to match', () => {
  assert.strictEqual(resolveRecordPath('evidence/42/g3/self-review.md', '42'),
                     'evidence/42/g3/self-review.md');
  assert.strictEqual(resolveRecordPath('evidence/42/../../etc/self-review.md', '42'), null);
  assert.strictEqual(resolveRecordPath('nothing here', '42'), null);
  assert.strictEqual(resolveRecordPath('evidence/42/g3/self-review.md', '44'), null);
  assert.strictEqual(resolveRecordPath('evidence/42/g3/self-review.md', null), null);
});

// ── Content, not just existence ────────────────────────────────────────────
const linked = {
  body: body('Closes #42', '', 'Record: `evidence/42/g3/self-review.md`'),
  title: 'fix: thing',
  prNumber: 43,
};

check('a record with an empty "Not verified" fails', () => {
  const record = GOOD_RECORD.replace(
    '- The Mykronos ingestion path has never executed end to end. Unverified.', '');
  const r = evaluate({ ...linked, ...withRecord(record) });
  assert.strictEqual(r.failures.length, 1);
  assert.match(r.failures[0], /Not verified/);
});

check('"Not verified: none" fails — that is the shape of not having looked', () => {
  const record = GOOD_RECORD.replace(
    '- The Mykronos ingestion path has never executed end to end. Unverified.', '- none');
  const r = evaluate({ ...linked, ...withRecord(record) });
  assert.strictEqual(r.failures.length, 1);
});

check('a confidently padded "none" fails too — length is not substance', () => {
  // The length floor alone passes this. Only the explicit none-rejection catches
  // it, which is why this assertion exists: mutation testing showed the earlier
  // none-rejection constrained nothing.
  const record = GOOD_RECORD.replace(
    '- The Mykronos ingestion path has never executed end to end. Unverified.',
    '- None — I verified absolutely everything in this change, comprehensively.');
  const r = evaluate({ ...linked, ...withRecord(record) });
  assert.strictEqual(r.failures.length, 1, 'a padded "none" must still fail');
  assert.match(r.failures[0], /Not verified/);
});

check('a missing "Cold-read notes" section fails', () => {
  const record = GOOD_RECORD.split('## Cold-read notes')[0];
  const r = evaluate({ ...linked, ...withRecord(record) });
  assert.strictEqual(r.failures.length, 1);
  assert.match(r.failures[0], /Cold-read notes/);
});

check('thin "Verified independently" warns but does not block', () => {
  const record = GOOD_RECORD.replace(
    '- Ran fly validate-pipeline and read the output rather than the badge',
    '- looks fine');
  const r = evaluate({ ...linked, ...withRecord(record) });
  assert.strictEqual(r.failures.length, 0, 'must not block');
  assert.strictEqual(r.warnings.length, 1, 'must warn');
});

check('sectionFilled ignores a heading with only whitespace', () => {
  assert.strictEqual(sectionFilled('## Not verified\n\n\n## Next\n', 'Not verified'), false);
});

// ── The one positive case ──────────────────────────────────────────────────
check('a complete record for the linked issue passes clean', () => {
  const r = evaluate({ ...linked, ...withRecord(GOOD_RECORD) });
  assert.strictEqual(r.found, true);
  assert.deepStrictEqual(r.failures, []);
  assert.deepStrictEqual(r.warnings, []);
});

console.log(`\n  ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
