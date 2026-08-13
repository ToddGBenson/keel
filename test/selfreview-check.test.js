'use strict';
// Tests for the solo-mode self-review check. Refs: #44
//
// Every assertion below is a NEGATIVE case — the branch proving the control
// denies. That is the point: this check is the entire substitute for a second
// reviewer's approval under POAM-008, and it shipped for months passing on a
// markdown heading that the PR template tells authors to write.
//
// Mutation-verified. Deleting the `exists()` call, the section-content test, or
// the evidence/ path confinement each fails at least one assertion below.
//
//   node test/selfreview-check.test.js

const assert = require('assert');
const { evaluate, sectionFilled, resolveRecordPath } =
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

const GOOD_RECORD = `# Self-review — #42

## Verified independently
- Ran fly validate-pipeline and read the output rather than the badge

## Not verified
- The Mykronos ingestion path has never executed end to end. Unverified.

## Cold-read notes
- I verified what I built and trusted what I copied; every defect was copied.
`;

const noFs = {
  exists: () => { throw new Error('exists() must not be called on this path'); },
  readFile: () => { throw new Error('readFile() must not be called on this path'); },
};

// ── THE REGRESSION THAT MOTIVATED THIS FILE ─────────────────────────────────
check('a bare "## Self-review" heading is NOT a record', () => {
  const r = evaluate({
    body: '## Self-review\n\nNo record exists yet.',
    prNumber: 43, ...noFs,
  });
  assert.strictEqual(r.found, false);
  assert.strictEqual(r.failures.length, 1, 'must fail');
  assert.match(r.failures[0], /heading alone is not a record/i);
});

check('a body honestly stating the record is absent still fails', () => {
  // The exact wording that passed before #44 was fixed.
  const r = evaluate({
    body: '## Self-review\n\n*(deliberately absent)* — no self-review record exists yet.',
    prNumber: 43, ...noFs,
  });
  assert.strictEqual(r.failures.length, 1);
});

check('no mention of a self-review at all fails', () => {
  const r = evaluate({ body: '## What I made worse\n\nNothing.', prNumber: 1, ...noFs });
  assert.strictEqual(r.failures.length, 1);
});

// ── The link must point at something real ────────────────────────────────────
check('a linked record that does not exist fails', () => {
  const r = evaluate({
    body: 'See evidence/42/g3/self-review.md',
    prNumber: 43,
    exists: () => false,
    readFile: () => { throw new Error('should not read a missing file'); },
  });
  assert.strictEqual(r.found, false);
  assert.match(r.failures[0], /not in the repository/i);
});

// ── Path confinement (PD-6) ──────────────────────────────────────────────────
check('traversal outside evidence/ is rejected without touching the filesystem', () => {
  const r = evaluate({
    body: 'See evidence/../../../tmp/self-review.md',
    prNumber: 43, ...noFs,   // throws if exists() is reached
  });
  assert.strictEqual(r.recordPath, null);
  assert.strictEqual(r.failures.length, 1);
});

check('resolveRecordPath normalises and confines', () => {
  assert.strictEqual(resolveRecordPath('evidence/42/g3/self-review.md'),
                     'evidence/42/g3/self-review.md');
  assert.strictEqual(resolveRecordPath('evidence/../etc/self-review.md'), null);
  assert.strictEqual(resolveRecordPath('nothing here'), null);
});

// ── Content, not just existence ──────────────────────────────────────────────
check('a record with an empty "Not verified" fails', () => {
  const record = GOOD_RECORD.replace(
    '- The Mykronos ingestion path has never executed end to end. Unverified.', '');
  const r = evaluate({
    body: 'evidence/42/g3/self-review.md', prNumber: 43,
    exists: () => true, readFile: () => record,
  });
  assert.strictEqual(r.failures.length, 1);
  assert.match(r.failures[0], /Not verified/);
});

check('"Not verified: none" fails — that is the shape of not having looked', () => {
  const record = GOOD_RECORD.replace(
    '- The Mykronos ingestion path has never executed end to end. Unverified.',
    '- none');
  const r = evaluate({
    body: 'evidence/42/g3/self-review.md', prNumber: 43,
    exists: () => true, readFile: () => record,
  });
  assert.strictEqual(r.failures.length, 1);
});

check('a confidently padded "none" fails too — length is not substance', () => {
  // The length floor alone passes this. Only the explicit none-rejection
  // catches it, which is the point: this assertion exists because mutation
  // testing showed the earlier none-rejection constrained nothing.
  const record = GOOD_RECORD.replace(
    '- The Mykronos ingestion path has never executed end to end. Unverified.',
    '- None — I verified absolutely everything in this change, comprehensively.');
  const r = evaluate({
    body: 'evidence/42/g3/self-review.md', prNumber: 43,
    exists: () => true, readFile: () => record,
  });
  assert.strictEqual(r.failures.length, 1, 'a padded "none" must still fail');
  assert.match(r.failures[0], /Not verified/);
});

check('a missing "Cold-read notes" section fails', () => {
  const record = GOOD_RECORD.split('## Cold-read notes')[0];
  const r = evaluate({
    body: 'evidence/42/g3/self-review.md', prNumber: 43,
    exists: () => true, readFile: () => record,
  });
  assert.strictEqual(r.failures.length, 1);
  assert.match(r.failures[0], /Cold-read notes/);
});

check('thin "Verified independently" warns but does not block', () => {
  const record = GOOD_RECORD.replace(
    '- Ran fly validate-pipeline and read the output rather than the badge',
    '- looks fine');
  const r = evaluate({
    body: 'evidence/42/g3/self-review.md', prNumber: 43,
    exists: () => true, readFile: () => record,
  });
  assert.strictEqual(r.failures.length, 0, 'must not block');
  assert.strictEqual(r.warnings.length, 1, 'must warn');
});

// ── The one positive case ────────────────────────────────────────────────────
check('a complete record passes with no failures or warnings', () => {
  const r = evaluate({
    body: 'Record: `evidence/42/g3/self-review.md`', prNumber: 43,
    exists: () => true, readFile: () => GOOD_RECORD,
  });
  assert.strictEqual(r.found, true);
  assert.deepStrictEqual(r.failures, []);
  assert.deepStrictEqual(r.warnings, []);
});

check('sectionFilled ignores a heading with only whitespace', () => {
  assert.strictEqual(sectionFilled('## Not verified\n\n\n## Next\n', 'Not verified'), false);
});

console.log(`\n  ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
