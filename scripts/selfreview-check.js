'use strict';
// Solo-mode self-review verification. Refs: #44
//
// Extracted from .github/workflows/pr-governance.yml so it can be tested. The
// defect this fixes was invisible to review and would have been caught by one
// assertion: the check passed on the presence of a `## Self-review` markdown
// heading, and the PR template instructs authors to write exactly that heading.
// So the default path through the process satisfied the compensating control
// for POAM-008 before any review had been performed.
//
// This is the whole of AC-5's substitute under solo operation. It gets a test.
//
// Pure by construction: the filesystem arrives as injected functions so the
// tests need no fixtures on disk and no repository layout.

const path = require('path');

// A section counts as filled only when it carries a bullet with substance.
// A heading followed by nothing, or by "none"/"n/a", is the shape of a
// self-review that did not happen.
const MIN_BULLET_CHARS = 25;

function sectionBody(record, heading) {
  const re = new RegExp(
    '^#{2,3}\\s*' + heading + '[^\\n]*\\n([\\s\\S]*?)(?=^#{2,3}\\s|$(?![\\s\\S]))',
    'im');
  const m = record.match(re);
  return m ? m[1] : null;
}

function sectionFilled(record, heading) {
  const body = sectionBody(record, heading);
  if (body === null) return false;

  // A leading "none" fails however much prose follows it. The earlier form
  // required the bullet to be EXACTLY "- none", which the length floor below
  // already rejected — so it constrained nothing, and mutation testing caught
  // that it constrained nothing. "- none — I verified everything in this change"
  // is precisely the claim this section exists to disbelieve.
  if (/^\s*[-*]\s*(none|n\/?a|nothing|nil)\b/im.test(body)) return false;

  return new RegExp('^\\s*[-*]\\s*\\S[\\s\\S]{' + MIN_BULLET_CHARS + ',}', 'm').test(body);
}

// The reference is attacker-influenced text from a PR body, and this runs with
// the repository checked out — so it is normalised and confined to evidence/
// before it ever reaches the filesystem. (PD-6: fetched content is data.)
//
// ── IT MUST BE THIS WORK'S RECORD ────────────────────────────────────────────
// `issueNumber` is required, and the path must sit under `evidence/<issue>/`.
//
// The first version of this fix accepted ANY evidence/**/self-review.md, which
// is the original defect one level up: "any heading" became "any record" rather
// than "a record for this change". It was caught immediately and embarrassingly
// — the pull request introducing this check passed its own check, because its
// body mentioned another issue's record in a sentence explaining how the check
// had been tested. A prose mention of somebody else's review is not review.
function resolveRecordPath(body, issueNumber) {
  if (!issueNumber) return null;
  const pattern = new RegExp(
    'evidence/' + issueNumber + '/[^\\s)`\'"]*self-review\\.md', 'i');
  const ref = body.match(pattern);
  if (!ref) return null;
  const candidate = path.normalize(ref[0]).replace(/\\/g, '/');
  return candidate.startsWith('evidence/' + issueNumber + '/') ? candidate : null;
}

// Which issue does this PR claim to close? Same forms pr-governance.yml accepts
// for the CM-3 traceability check, so a PR cannot link one issue and file its
// review under another.
function linkedIssue(body, title) {
  const m = body.match(/(?:closes|fixes|resolves|refs?)\s*:?\s*#(\d+)/i)
         || (title || '').match(/#(\d+)/);
  return m ? m[1] : null;
}

/**
 * @param {object} opts
 * @param {string} opts.body        the pull request body
 * @param {string} opts.title       the pull request title
 * @param {number} opts.prNumber
 * @param {function(string):boolean} opts.exists
 * @param {function(string):string}  opts.readFile
 * @returns {{failures: string[], warnings: string[], recordPath: ?string, found: boolean}}
 */
function evaluate({ body, title, prNumber, exists, readFile }) {
  const failures = [];
  const warnings = [];

  const issue = linkedIssue(body, title);
  const recordPath = resolveRecordPath(body, issue);

  if (!issue) {
    // The traceability check reports this separately; repeat it here because
    // without an issue number there is no evidence path to demand.
    failures.push(
      'No linked issue, so the self-review record cannot be located. Add ' +
      '"Closes #<n>" and link `evidence/<n>/g3/self-review.md` (CM-3, POAM-008).');
    return { failures, warnings, recordPath: null, found: false };
  }

  if (!recordPath) {
    const strayRef = /evidence\/(\d+)\/[^\s)`'"]*self-review\.md/i.exec(body);
    failures.push(
      'No approving review from another identity, and no self-review record for ' +
      'issue #' + issue + '. In solo mode the self-review ARTIFACT is the review ' +
      'evidence (POAM-008, docs/13-solo-operation.md). Run `/self-review ' +
      prNumber + '` and link `evidence/' + issue + '/g3/self-review.md`. ' +
      (strayRef && strayRef[1] !== issue
        ? 'This PR references `evidence/' + strayRef[1] + '/...`, which belongs to a ' +
          'different issue — another change\'s review is not this change\'s review. '
        : '') +
      'A heading alone is not a record, and neither is a link to someone else\'s (#44).');
    return { failures, warnings, recordPath: null, found: false };
  }

  if (!exists(recordPath)) {
    failures.push(
      'The PR body references `' + recordPath + '` but that file is not in the ' +
      'repository. Commit the self-review record — a link to a file that does not ' +
      'exist is not evidence (PD-3).');
    return { failures, warnings, recordPath, found: false };
  }

  const record = readFile(recordPath);

  const missing = ['Not verified', 'Cold-read notes'].filter(h => !sectionFilled(record, h));
  if (missing.length) {
    failures.push(
      '`' + recordPath + '` has nothing substantive under ' +
      missing.map(h => '"' + h + '"').join(' or ') + '. Per the self-review skill, a ' +
      'self-review with nothing in either is a self-review that did not happen. ' +
      '"Unverified" is a valid and expected outcome — say it.');
  }

  if (!sectionFilled(record, 'Verified independently')) {
    warnings.push(
      '`' + recordPath + '` looks thin under "Verified independently". State the ' +
      'specific claims you checked, not that you reviewed it.');
  }

  return { failures, warnings, recordPath, found: true };
}

module.exports = { evaluate, sectionFilled, resolveRecordPath, sectionBody, linkedIssue };
