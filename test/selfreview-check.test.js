'use strict';
// Tests for the solo-mode self-review check. Refs: #44
//
// This check is the entire substitute for a second reviewer's approval under
// POAM-008. It has now been bypassed four times, each time in the same shape as
// the last, and each bypass below is pinned by name so it cannot come back:
//
//   1. a `## Self-review` heading satisfied it
//   2. any evidence/**/self-review.md satisfied it, including another issue's
//   3. the first LINKED issue won, so `Refs: #42` above `Closes #44` bound to 42
//   4. `evidence/44/..\42\...` — backslashes survive path.normalize on POSIX
//
// Bypass 4 was invisible to this suite for a reason worth remembering: every
// assertion ran against an INJECTED filesystem, and the defect lived in the gap
// between the string returned and what a real filesystem does with it. Hence the
// integration section at the bottom, which uses the real `fs` on a real tree.
//
// ── WHAT IS AND IS NOT MUTATION-VERIFIED ─────────────────────────────────────
// Caught individually: multi-close detection, PR-number binding, symlink
// rejection, fence stripping, the existence check, the bullet-length anchor, the
// word boundary on closing keywords, the issue-number pattern, the prefix check.
//
// NOT caught individually: the two separator guards in resolveRecordPath —
// normalising `\` before path.posix.normalize, and rejecting any surviving `..`
// segment. Either alone stops every payload below, so mutating one leaves the
// suite green. Removing both fails three assertions. That is defence in depth
// rather than a coverage gap, but it is stated plainly here because claiming
// per-guard verification would be the kind of unearned assurance this whole file
// exists to stop.
//
//   node test/selfreview-check.test.js

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const nodePath = require('path');
const {
  evaluate, sectionFilled, sectionBody, resolveRecordPath,
  linkedIssue, closingIssues, MIN_BULLET_CHARS,
} = require('../scripts/selfreview-check.js');

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

const BS = String.fromCharCode(92);      // a literal backslash, unambiguously
const body = (...lines) => lines.join('\n');

const GOOD_RECORD = [
  '# Self-review — #42',
  '',
  'PR: #43   Mode: solo (POAM-008)',
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

// Explodes if reached, so any assertion using it also proves the input was
// rejected BEFORE any syscall.
const noFs = {
  exists: () => { throw new Error('exists() must not be called on this path'); },
  readFile: () => { throw new Error('readFile() must not be called on this path'); },
  isSymlink: () => false,
};
const withRecord = (record) => ({
  exists: () => true, readFile: () => record, isSymlink: () => false,
});
const linked = {
  body: body('Closes #42', '', 'Record: `evidence/42/g3/self-review.md`'),
  title: 'fix: thing',
  prNumber: 43,
};

// ── BYPASS 1: a heading is not a record ─────────────────────────────────────
check('a bare "## Self-review" heading is NOT a record', () => {
  const r = evaluate({
    body: body('Closes #42', '', '## Self-review', '', 'No record exists yet.'),
    title: 'fix: thing', prNumber: 43, ...noFs,
  });
  assert.strictEqual(r.found, false);
  assert.match(r.failures[0], /heading alone is not a record/i);
});

check('a body honestly stating the record is absent still fails', () => {
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

// ── BYPASS 2: another issue's record ────────────────────────────────────────
check("another issue's record does NOT satisfy this PR", () => {
  const r = evaluate({
    body: body('Closes #44', '',
               'Verified against the real evidence/42/g3/self-review.md as a control.'),
    title: 'fix(governance): require a record', prNumber: 46, ...noFs,
  });
  assert.strictEqual(r.found, false);
  assert.match(r.failures[0], /belongs to a different issue/i);
});

// Both enforcement points are pinned INDEPENDENTLY. Mutation testing showed the
// suite only noticed when the pattern and the prefix check were removed
// together, which is not verification of either.
check('the reference pattern alone confines to the issue', () => {
  assert.strictEqual(resolveRecordPath('evidence/42/g3/self-review.md', '44'), null);
});
check('the prefix check alone confines to the issue', () => {
  // Reaches the prefix test only because the pattern permits it via traversal.
  assert.strictEqual(
    resolveRecordPath('evidence/44/../42/g3/self-review.md', '44'), null);
});

// ── BYPASS 3: which issue is "the" issue ───────────────────────────────────
check('a closing keyword beats an earlier "Refs:"', () => {
  assert.strictEqual(linkedIssue('Refs: #42\n\nCloses #44', 'fix: x'), '44');
  assert.strictEqual(linkedIssue('Refs: #42\n\nFixes #44', 'fix: x'), '44');
});

check('two closing keywords fail loudly rather than picking one', () => {
  const r = evaluate({
    body: body('> Closes #42', '', 'Closes #44', '',
               'evidence/42/g3/self-review.md'),
    title: 'fix: x', prNumber: 46, ...noFs,
  });
  assert.strictEqual(r.found, false, 'must not silently bind to the first');
  assert.match(r.failures[0], /closes 2 issues/i);
});

check('a word ending in a closing keyword does not count', () => {
  assert.deepStrictEqual(closingIssues('This prefixes #42 onto the log line.'), []);
  assert.deepStrictEqual(closingIssues('It discloses #42 to the caller.'), []);
  assert.deepStrictEqual(closingIssues('Closes #42'), ['42']);
});

check('the issue number is matched whole, not as a prefix', () => {
  assert.strictEqual(resolveRecordPath('evidence/44/g3/self-review.md', '4'), null);
  assert.strictEqual(resolveRecordPath('evidence/4/g3/self-review.md', '44'), null);
});

// ── BYPASS 4: separators, on the platform this runs on ─────────────────────
// These would have PASSED on Linux while passing on Windows for the wrong
// reason. resolveRecordPath uses path.posix explicitly so the result is the
// runner's result wherever the test is run.
check('backslash traversal is rejected (bypass 4)', () => {
  const ref = 'evidence/44/..' + BS + '42' + BS + 'g3' + BS + 'self-review.md';
  assert.strictEqual(resolveRecordPath(ref, '44'), null);
});

check('mixed separators are rejected', () => {
  const ref = 'evidence/44/g3' + BS + '..' + BS + '..' + BS + '42/g3/self-review.md';
  assert.strictEqual(resolveRecordPath(ref, '44'), null);
});

check('backslash escape out of the checkout is rejected', () => {
  const ref = 'evidence/44/..' + BS + '..' + BS + '..' + BS + 'etc/self-review.md';
  assert.strictEqual(resolveRecordPath(ref, '44'), null);
});

check('forward-slash traversal is rejected without touching the filesystem', () => {
  const r = evaluate({
    body: body('Closes #42', '', 'See evidence/42/../../../tmp/self-review.md'),
    title: 'fix: thing', prNumber: 43, ...noFs,
  });
  assert.strictEqual(r.recordPath, null);
});

check('an honest capitalised reference is ACCEPTED, not accused', () => {
  // /i on the pattern with a case-sensitive prefix test rejected this and then
  // told the author they had not written a record. L0007.
  assert.strictEqual(resolveRecordPath('Evidence/44/g3/Self-Review.md', '44'),
                     'Evidence/44/g3/Self-Review.md');
});

// ── The record must be real, and must be this PR's ─────────────────────────
check('a linked record that does not exist fails', () => {
  const r = evaluate({
    body: body('Closes #42', '', 'See evidence/42/g3/self-review.md'),
    title: 'fix: thing', prNumber: 43,
    exists: () => false, isSymlink: () => false,
    readFile: () => { throw new Error('should not read a missing file'); },
  });
  assert.match(r.failures[0], /not in the repository/i);
});

check('a symlinked record is rejected', () => {
  const r = evaluate({
    ...linked,
    exists: () => true, isSymlink: () => true,
    readFile: () => { throw new Error('must not read through a symlink'); },
  });
  assert.strictEqual(r.found, false);
  assert.match(r.failures[0], /symbolic link/i);
});

check("an earlier PR's record on the same issue does not satisfy this one", () => {
  const r = evaluate({ ...linked, prNumber: 99, ...withRecord(GOOD_RECORD) });
  assert.strictEqual(r.found, false);
  assert.match(r.failures[0], /does not reference PR #99/i);
});

check('evaluate refuses to run without a symlink check wired in', () => {
  assert.throws(() => evaluate({ ...linked, exists: () => true, readFile: () => '' }),
                /requires an isSymlink/);
});

// ── Content, not shape alone ───────────────────────────────────────────────
check('a record with an empty "Not verified" fails', () => {
  const record = GOOD_RECORD.replace(
    '- The Mykronos ingestion path has never executed end to end. Unverified.', '');
  const r = evaluate({ ...linked, ...withRecord(record) });
  assert.match(r.failures[0], /Not verified/);
});

check('"Not verified: none" fails', () => {
  const record = GOOD_RECORD.replace(
    '- The Mykronos ingestion path has never executed end to end. Unverified.', '- none');
  const r = evaluate({ ...linked, ...withRecord(record) });
  assert.strictEqual(r.failures.length, 1);
});

check('a confidently padded "none" fails too — length is not substance', () => {
  const record = GOOD_RECORD.replace(
    '- The Mykronos ingestion path has never executed end to end. Unverified.',
    '- None — I verified absolutely everything in this change, comprehensively.');
  const r = evaluate({ ...linked, ...withRecord(record) });
  assert.match(r.failures[0], /Not verified/);
});

check('many tiny bullets do NOT satisfy a section', () => {
  // The floor used to span newlines, so 21 `- x` bullets passed.
  const tiny = new Array(21).fill('- x').join('\n');
  assert.strictEqual(sectionFilled('## Not verified\n' + tiny + '\n', 'Not verified'),
                     false);
});

check('a section with prose but no bullet does not count', () => {
  assert.strictEqual(
    sectionFilled('## Not verified\n\nthis is a fairly long line of prose indeed\n',
                  'Not verified'), false);
});

check('the length floor is measured on one line', () => {
  const short = '- ' + 'a'.repeat(MIN_BULLET_CHARS - 1);
  const long = '- ' + 'a'.repeat(MIN_BULLET_CHARS + 1);
  assert.strictEqual(sectionFilled('## Not verified\n' + short + '\n', 'Not verified'), false);
  assert.strictEqual(sectionFilled('## Not verified\n' + long + '\n', 'Not verified'), true);
});

check('content inside a fenced block does not satisfy a section', () => {
  const record = [
    '# r', '', 'PR: #43', '',
    '## Verified independently', '- something genuinely checked and written out here',
    '', '## Not verified', '',
    '```', '- pasted from the template, long enough to clear the floor easily', '```',
    '', '## Cold-read notes', '- a real cold-read note that is long enough to count',
  ].join('\n');
  const r = evaluate({ ...linked, ...withRecord(record) });
  assert.match(r.failures[0], /Not verified/);
});

check('a fenced heading does not truncate the section above it', () => {
  const record = [
    '## Not verified', '- a genuine unverified item written out at length',
    '', '```', '## Cold-read notes', '```', '',
  ].join('\n');
  assert.strictEqual(sectionFilled(record, 'Not verified'), true);
});

check('a missing "Cold-read notes" section fails', () => {
  const record = GOOD_RECORD.split('## Cold-read notes')[0];
  const r = evaluate({ ...linked, ...withRecord(record) });
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

check('a sub-heading terminates the section', () => {
  assert.strictEqual(sectionBody('## Not verified\n#### sub\n- x\n', 'Not verified'),
                     '');
});

// ── The one positive case ──────────────────────────────────────────────────
check('a complete record for the linked issue and PR passes clean', () => {
  const r = evaluate({ ...linked, ...withRecord(GOOD_RECORD) });
  assert.strictEqual(r.found, true);
  assert.deepStrictEqual(r.failures, []);
  assert.deepStrictEqual(r.warnings, []);
});

// ── INTEGRATION: the real filesystem ───────────────────────────────────────
// Bypass 4 lived in the gap between "the string resolveRecordPath returns" and
// "what a filesystem does with that string". Injection cannot see that gap.
check('INTEGRATION: traversal payloads resolve to nothing on a real tree', () => {
  const root = fs.mkdtempSync(nodePath.join(os.tmpdir(), 'srcheck-'));
  try {
    fs.mkdirSync(nodePath.join(root, 'evidence', '42', 'g3'), { recursive: true });
    fs.mkdirSync(nodePath.join(root, 'evidence', '44', 'g3'), { recursive: true });
    fs.writeFileSync(nodePath.join(root, 'evidence', '42', 'g3', 'self-review.md'),
                     GOOD_RECORD);
    // evidence/44/ is deliberately EMPTY — there is no record for issue 44.

    const realFs = {
      exists: (p) => fs.existsSync(nodePath.join(root, p)),
      readFile: (p) => fs.readFileSync(nodePath.join(root, p), 'utf8'),
      isSymlink: (p) => {
        const full = nodePath.join(root, p);
        return fs.existsSync(full) && fs.lstatSync(full).isSymbolicLink();
      },
    };

    const payloads = [
      'evidence/44/..' + BS + '42' + BS + 'g3' + BS + 'self-review.md',
      'evidence/44/g3' + BS + '..' + BS + '..' + BS + '42/g3/self-review.md',
      'evidence/44/../42/g3/self-review.md',
    ];

    for (const p of payloads) {
      const r = evaluate({
        body: 'Closes #44\n\nRecord: ' + p,
        title: 'fix: x', prNumber: 46, ...realFs,
      });
      assert.strictEqual(r.found, false, 'payload passed: ' + p);
      assert.ok(r.failures.length > 0, 'no failure raised for: ' + p);
    }

    // A REAL symlink, not an injected `isSymlink: () => true`. git stores
    // symlinks and actions/checkout materialises them, so this is committable:
    // evidence/44's record as a link to evidence/42's real one.
    //
    // Skipped LOUDLY on hosts that cannot create symlinks (Windows without
    // Developer Mode returns EPERM) — the assertion is not silently dropped,
    // because this is the one case injection cannot represent. Verified passing
    // on linux in node:22-alpine.
    const linkPath = nodePath.join(root, 'evidence', '44', 'g3', 'self-review.md');
    let linked = false;
    try {
      fs.symlinkSync('../../42/g3/self-review.md', linkPath);
      linked = fs.lstatSync(linkPath).isSymbolicLink();
    } catch (err) {
      console.log(`         (symlink case SKIPPED on this host: ${err.code} — ` +
                  `runs on the Linux runner, where it is not optional)`);
    }
    if (linked) {
      assert.ok(fs.readFileSync(linkPath, 'utf8').includes('Not verified'),
                'the link must actually resolve, or the case proves nothing');
      const sym = evaluate({
        body: 'Closes #44\n\nRecord: evidence/44/g3/self-review.md',
        title: 'fix: x', prNumber: 46, ...realFs,
      });
      assert.strictEqual(sym.found, false, 'a symlinked record must be rejected');
      assert.match(sym.failures[0], /symbolic link/i);
      fs.unlinkSync(linkPath);
    }

    // And the honest path on the same real tree still works.
    fs.writeFileSync(nodePath.join(root, 'evidence', '44', 'g3', 'self-review.md'),
                     GOOD_RECORD.replace('PR: #43', 'PR: #46'));
    const ok = evaluate({
      body: 'Closes #44\n\nRecord: evidence/44/g3/self-review.md',
      title: 'fix: x', prNumber: 46, ...realFs,
    });
    assert.strictEqual(ok.found, true, 'honest record must pass: ' +
                       JSON.stringify(ok.failures));
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

console.log(`\n  ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
