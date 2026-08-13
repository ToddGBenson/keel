'use strict';
// Solo-mode self-review verification. Refs: #44
//
// This is the whole of AC-5's substitute under POAM-008: with
// required_approving_review_count at 0, nothing else forces a second look.
//
// ── WHAT IT CAN AND CANNOT DO ────────────────────────────────────────────────
// It is a SHAPE CHECK. Anyone willing to spend ninety seconds writing three
// headings and three sentences passes it, and no amount of regex changes that.
// What it buys is that the deceit now requires committing a file that appears in
// the diff, in git history, under a name stating what it claims to be. That is a
// real improvement over a markdown heading. It is not "POAM-008's compensating
// control is enforced", and it must not be described that way.
//
// ── FOUR BYPASSES, ALL THE SAME SHAPE ────────────────────────────────────────
// Each fix closed the stated hole and left the shape one level over:
//   1. a `## Self-review` HEADING satisfied it — the PR template tells authors
//      to write that heading, so the default path defeated the control
//   2. ANY evidence/**/self-review.md satisfied it, including another issue's —
//      the PR introducing the fix passed its own check that way
//   3. the first LINKED issue won, and `Refs: #42` sits above `Closes #44` in
//      almost every body here
//   4. `evidence/44/..\42\g3\self-review.md` — on Linux `path.normalize` leaves
//      `..\` alone as an ordinary filename, and converting separators AFTER
//      normalising manufactured live `../` that the confinement check accepted
//
// The lesson, written down because it keeps recurring: fixing the instance is
// not fixing the class. Ask what OTHER string satisfies the new predicate
// without the work having happened.
//
// Pure by construction — the filesystem arrives as injected functions, so the
// tests need no repository layout. That injection is also how three of the four
// bypasses hid, so there is now an integration test using the real `fs` too.

const path = require('path');

// Length is measured across ONE BULLET LINE, not the section. `[\s\S]{25,}`
// spanned newlines, so twenty-one `- x` bullets — or a section with no bullet at
// all followed by prose — satisfied "a bullet with substance".
const MIN_BULLET_CHARS = 25;

// Fenced blocks are stripped before any heading or bullet is looked for. A
// record that quotes the /self-review command's own example template inside a
// fence otherwise supplies a passing `## Not verified` with a substantial
// bullet — the documented default path satisfying the control again — and a
// fenced `## heading` truncates the preceding section, producing a FALSE
// failure, which is how checkers get muted (L0007).
function stripFences(text) {
  return text.replace(/^[ \t]*(```|~~~)[\s\S]*?^[ \t]*\1[ \t]*$/gm, '');
}

function sectionBody(record, heading) {
  const re = new RegExp(
    '^#{2,3}[ \\t]*' + heading + '[^\\n]*\\n([\\s\\S]*?)(?=^#{1,6}[ \\t]|$(?![\\s\\S]))',
    'im');
  const m = stripFences(record).match(re);
  return m ? m[1] : null;
}

function sectionFilled(record, heading) {
  const body = sectionBody(record, heading);
  if (body === null) return false;

  // A leading "none" fails however much prose follows. This is a blocklist and
  // therefore leaky — "Not applicable", "Zero outstanding items" and "No gaps
  // whatsoever" all pass. It catches the four laziest spellings, nothing more,
  // and the claim in this comment is deliberately that small.
  if (/^[ \t]*[-*][ \t]*(none|n\/?a|nothing|nil)\b/im.test(body)) return false;

  // \S then MIN_BULLET_CHARS more, all on the same line.
  return new RegExp(
    '^[ \\t]*[-*][ \\t]*\\S[^\\n]{' + MIN_BULLET_CHARS + ',}', 'm').test(body);
}

// ── PATH RESOLUTION ──────────────────────────────────────────────────────────
// The reference is attacker-influenced text from a PR body and this runs with
// the repository checked out, so the string is confined before any syscall.
//
// Order matters and is the whole of bypass 4: separators are normalised FIRST,
// then `path.posix.normalize` collapses `..`, then any surviving `..` segment is
// rejected outright. `path.posix` explicitly — bare `path` is win32 on a Windows
// developer machine and posix on the runner, so the check behaved differently in
// the place it was tested from the place it runs.
function resolveRecordPath(body, issueNumber) {
  if (!issueNumber) return null;

  const pattern = new RegExp(
    'evidence[\\\\/]' + issueNumber + '[\\\\/][^\\s)`\'"]*self-review\\.md', 'i');
  const ref = body.match(pattern);
  if (!ref) return null;

  const candidate = path.posix.normalize(ref[0].replace(/\\/g, '/'));

  // Belt as well as braces, and measurably so: mutation testing shows that
  // reverting the separator order OR deleting this line individually leaves the
  // suite green, because each guard catches what the other would have missed.
  // Removing BOTH fails three assertions. Keep both — and do not describe either
  // as independently mutation-verified, because it is not.
  if (candidate.split('/').includes('..')) return null;

  const prefix = 'evidence/' + issueNumber + '/';
  // Case-insensitive comparison, case-preserving return: the reference regex is
  // /i, so a capitalised `Evidence/...` previously matched and was then rejected
  // by a case-sensitive prefix test, producing "you did not write a record"
  // about a record the author had written.
  return candidate.toLowerCase().startsWith(prefix.toLowerCase()) ? candidate : null;
}

// ── ISSUE RESOLUTION ─────────────────────────────────────────────────────────
// Every issue this PR claims to CLOSE. Not merely mention.
//
// All closing matches are collected, not the first: `Closes #42` quoted in
// narrative above `Closes #44` bound the check to 42, and 42's real record then
// satisfied a PR closing 44. Two genuinely-closed issues is also a normal thing
// to write, so picking one silently is wrong even without an adversary.
//
// \b on both, or `prefixes #42` and `discloses #42` redirect the whole check.
function closingIssues(body) {
  const out = [];
  const re = /\b(?:closes|fixes|resolves)\b\s*:?\s*#(\d+)/gi;
    let m;
  while ((m = re.exec(body)) !== null) out.push(m[1]);
  return [...new Set(out)];
}

function linkedIssue(body, title) {
  const closing = closingIssues(body);
  if (closing.length) return closing[0];
  const refs = body.match(/\brefs?\b\s*:?\s*#(\d+)/i);
  if (refs) return refs[1];
  const fromTitle = (title || '').match(/#(\d+)/);
  return fromTitle ? fromTitle[1] : null;
}

/**
 * @param {object} opts
 * @param {string} opts.body
 * @param {string} opts.title
 * @param {number} opts.prNumber
 * @param {function(string):boolean} opts.exists
 * @param {function(string):string}  opts.readFile
 * @param {function(string):boolean} opts.isSymlink  REQUIRED — see below
 */
function evaluate({ body, title, prNumber, exists, readFile, isSymlink }) {
  const failures = [];
  const warnings = [];
  const none = { failures, warnings, recordPath: null, found: false };

  // Required rather than defaulted. A default of "not a symlink" would be a
  // silent hole the day someone forgets to wire it, which is this file's entire
  // history.
  if (typeof isSymlink !== 'function') {
    throw new TypeError('evaluate() requires an isSymlink(path) function');
  }

  const closing = closingIssues(body);
  if (closing.length > 1) {
    failures.push(
      'This PR closes ' + closing.length + ' issues (#' + closing.join(', #') +
      '), so the check cannot tell which self-review record to require. Close ' +
      'one issue per PR, or link a record for each.');
    return none;
  }

  const issue = linkedIssue(body, title);
  if (!issue) {
    failures.push(
      'No linked issue, so the self-review record cannot be located. Add ' +
      '"Closes #<n>" and link `evidence/<n>/g3/self-review.md` (CM-3, POAM-008).');
    return none;
  }

  const recordPath = resolveRecordPath(body, issue);
  if (!recordPath) {
    const stray = /evidence[\\/](\d+)[\\/][^\s)`'"]*self-review\.md/i.exec(body);
    failures.push(
      'No approving review from another identity, and no self-review record for ' +
      'issue #' + issue + '. In solo mode the self-review ARTIFACT is the review ' +
      'evidence (POAM-008, docs/13-solo-operation.md). Run `/self-review ' +
      prNumber + '` and link `evidence/' + issue + '/g3/self-review.md`. ' +
      (stray && stray[1] !== issue
        ? 'This PR references `evidence/' + stray[1] + '/...`, which belongs to a ' +
          'different issue — another change\'s review is not this change\'s review. '
        : '') +
      'A heading alone is not a record, and neither is a link to someone else\'s (#44).');
    return none;
  }

  // Symlinks are followed by exists/readFile and would reproduce bypass 2
  // through the filesystem instead of the body: `evidence/44/g3/self-review.md`
  // committed as a link to `../../42/g3/self-review.md`.
  if (isSymlink(recordPath)) {
    failures.push(
      '`' + recordPath + '` is a symbolic link. The record must be a real file in ' +
      'this repository — a link can point at another issue\'s review, or outside ' +
      'the checkout entirely.');
    return { failures, warnings, recordPath, found: false };
  }

  if (!exists(recordPath)) {
    failures.push(
      'The PR body references `' + recordPath + '` but that file is not in the ' +
      'repository. Commit the self-review record — a link to a file that does not ' +
      'exist is not evidence (PD-3).');
    return { failures, warnings, recordPath, found: false };
  }

  const record = readFile(recordPath);

  // The record must name THIS pull request. Without it, a second PR on the same
  // issue passes on the first PR's record — and fix-up PRs on one issue are
  // normal here, so that is the default path, not an attack. The /self-review
  // artifact template already emits a `PR: #<n>` line.
  const namesThisPr = new RegExp('\\bPR:?\\s*#' + prNumber + '\\b').test(record);
  if (!namesThisPr) {
    failures.push(
      '`' + recordPath + '` does not reference PR #' + prNumber + '. The record ' +
      'must state which pull request it reviewed — otherwise an earlier PR\'s ' +
      'record satisfies this one. Add a `PR: #' + prNumber + '` line.');
  }

  const missing = ['Not verified', 'Cold-read notes'].filter(h => !sectionFilled(record, h));
  if (missing.length) {
    failures.push(
      '`' + recordPath + '` has nothing substantive under ' +
      missing.map(h => '"' + h + '"').join(' or ') + '. Per the self-review skill, a ' +
      'self-review with nothing in either is a self-review that did not happen. ' +
      '"Unverified" is a valid and expected outcome — say it. Sections are matched ' +
      'as `## <name>` with a bullet of at least ' + MIN_BULLET_CHARS + ' characters.');
  }

  if (!sectionFilled(record, 'Verified independently')) {
    warnings.push(
      '`' + recordPath + '` looks thin under "Verified independently". State the ' +
      'specific claims you checked, not that you reviewed it.');
  }

  // `found` means "a usable record was read", and it is false whenever a failure
  // was raised about the record itself — the workflow renders it in the summary,
  // and a summary reading greener than the result is the pattern this file
  // exists to fix.
  return { failures, warnings, recordPath, found: failures.length === 0 };
}

module.exports = {
  evaluate, sectionFilled, sectionBody, stripFences,
  resolveRecordPath, linkedIssue, closingIssues, MIN_BULLET_CHARS,
};
