---
name: dependency-vetting
description: Verify a third-party package exists, is the intended one, and is safe to depend on before adding it. Use whenever adding or upgrading a dependency, reviewing a PR that changes a manifest or lockfile, or evaluating a suggested library. Covers hallucinated-package (slopsquatting) defense, typosquatting, license and maintenance checks.
---

# Dependency vetting

Consumers: `developer`, `/implement`, `/review`, `pr-governance.yml`,
`process/gates/g3-code-complete.md`.

## Why this exists as a distinct control

Models hallucinate plausible package names. Attackers monitor for the popular hallucinations
and register them — **slopsquatting**. The suggested import looks reasonable, the install
succeeds, and you have executed an attacker's code at build time with full CI privileges.

This is the supply-chain risk specific to AI-assisted development (AIC-7), and the check that
prevents it costs about ninety seconds.

## Before adding any package

### 1. Does it exist, and is it the one you mean?

- **Publisher/owner** — is it the org you expect? `requests` is published by
  `psf`; a `requests-lib` published by a three-week-old account is not the same thing.
- **Source repository** — does the registry page link to a real repo, and does that repo's
  README match the package?
- **Download history** — a genuinely popular library has years of downloads. A package with
  200 downloads and a name you recognize is a red flag, not a discovery.
- **Age** — first published last month, claiming to be a mature utility? No.
- **Name distance** — is it a near-miss of something popular? Common tricks: hyphen vs.
  underscore (`python-dateutil` / `python_dateutil`), added or dropped prefix
  (`js-yaml` / `jsyaml`), plural/singular, transposed characters, `-js` / `-py` suffixes.

> **If the model suggested this package and you have not personally confirmed it exists,
> assume it does not.**

### 2. Should you depend on it at all?

- **Is it needed?** Left-pad problems are real. A 6-line utility is not worth a supply-chain
  edge, a license obligation, and a permanent upgrade duty.
- **Maintenance signal** — recent commits, issues answered, a release in the last year. An
  unmaintained dependency is a scheduled vulnerability (SA-22).
- **Transitive weight** — how many packages does this actually pull in? Check before, not
  after.
- **Alternatives** — including the standard library, and including writing the six lines.

### 3. License

Compatible with your distribution model. Copyleft usually needs a decision rather than a
blanket block — decide deliberately rather than inheriting a default from a scanner config.
Record the decision.

### 4. Security posture

- Known vulnerabilities (SCA runs in CI, but check before you commit)
- Does it require elevated install-time execution — post-install scripts, build hooks?
- Does it phone home?

## Recording it

The PR must carry the justification. `pr-governance.yml` labels manifest changes
`dependency-change` and asks for this explicitly:

```markdown
| Package | Version | Why | License | Existence verified |
|---------|---------|-----|---------|--------------------|
| pydantic | 2.9.2 | Schema validation at the API boundary; replaces 200 lines of hand-rolled validation | MIT | github.com/pydantic/pydantic, 100M+ monthly, publisher `samuelcolvin` — confirmed |
```

"Existence verified" is not a checkbox. Say **what** you checked.

## Locking

- **Commit lockfiles.** Always.
- **Install frozen** — `npm ci`, `pip install --require-hashes`, `go mod verify`,
  `cargo --locked`. Not `npm install`.
- **Integrity hashes verified**, not just versions pinned.

## GitHub Actions specifically

**Pin to a full commit SHA, never a tag.**

```yaml
- uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2   ✓
- uses: actions/checkout@v4                                                   ✗
```

A tag is mutable. A compromised action tag is a supply-chain compromise of every workflow
that uses it — including the ones enforcing your other controls. Dependabot maintains the
SHAs and the version comments for you.

## Upgrades

- **Patch/minor** — Standard change. Grouped, automated, still CI-gated and still reviewed by
  a non-author.
- **Major** — Normal change. Gets a story, an impact assessment, and real review. Never an
  auto-merge path.
- **Security patch** — enters on the finding's SLA (Critical 7d / High 30d), ahead of feature
  work.

## Removal

Removing a dependency is a legitimate, valuable change. Every one you drop is attack surface,
upgrade toil, and license obligation gone permanently.

## Controls

SR-3 (supply chain controls) · SR-4 (provenance) · SR-4(3) (validate as genuine and
unaltered) · SR-5 · SR-11 (component authenticity) · SA-4 · SA-22 (unsupported components) ·
CM-8 (component inventory / SBOM) · RA-5 · **AIC-7** (supply chain integrity of AI
suggestions) · OWASP LLM05.
