# 04 — Design & Development (→ G2, G3)

**Owners:** Architect, Security, AI Risk (G2); Developer (G3)
**Commands:** `/design`, `/implement`, `/review` · **Gates:** `g2-design.md`, `g3-code-complete.md`
**Method lives in skills** — this page is the *why*. When a skill and this doc disagree, the
skill wins and this doc is the bug.

| Do the work with | Skill |
|---|---|
| Threat modeling at G2 | `threat-modeling` |
| AI impact assessment at G2 | `ai-impact-assessment` |
| Implementation | `test-strategy`, `dependency-vetting` |
| Code review at G3 | `secure-code-review` |

---

## Part A — Design (G2)

Required when the story is flagged security- or AI-relevant, or the change is expensive to
reverse. Skipped for routine work — and the skip is *recorded*, not silent.

**ADRs.** Write one only when a decision is **costly to reverse** — data model, service
boundary, persistence/messaging tech, auth model, external dependency, public interface, AI
model choice. Not for reversible choices; an ADR nobody would revisit devalues the ones that
matter. Accepted ADRs are **immutable** — supersede, never edit. Template: `templates/adr.md`.

**Threat model + control allocation.** Per the `threat-modeling` skill: model the delta, run
STRIDE, give every threat a recorded disposition (mitigate / transfer / accept / eliminate).
The one rule worth repeating here because it decides most G2 rejections: **for each control,
name the file that implements it, how it's verified, and the evidence.** "Implemented in the
application" is not an allocation.

**Secure design principles (SA-8)** — the architect states how each holds, or why it doesn't:
least privilege · defense in depth · fail secure (an error *denies*) · complete mediation ·
economy of mechanism · open design · minimized attack surface (SA-15(5)) · secure defaults.
Applied, not recited — say *where* in this design each one lives.

**AI-relevant?** The AI Risk Officer's impact assessment is a blocking G2 co-approval. See
`12-ai-feature-governance.md`.

---

## Part B — Development (G3)

```
G1 story → FAILING TEST (start here, always) → smallest impl that passes → refactor green
         → repeat until every AC has a passing test → self-check vs DoD → PR → G3 review
```

**Test-first is not a style preference.** A test written after the code asserts what the code
*does*; one written before asserts what it *should* do. Only the second catches the bug you
were about to write, and only the second is credible SA-11 evidence.

**Branching.** Trunk-based, short-lived off `main`, merged within ~2 days. Long-lived branches
accumulate merge risk and hide un-reviewed work from the scanners that run on `main`.
`<type>/<issue>-<slug>`; types `feat fix chore docs refactor test sec`. Feature-flag work that
spans more than one merge — an unfinished feature merged dark beats a week-old branch.

**Secure coding** is in the `secure-code-review` skill (the same failure classes reviewers
look for). The non-negotiables: validate at the boundary *and* encode at the sink;
parameterize every query; authorize server-side on the object (IDOR is still the most common
real finding); never log secrets; fail closed; no secrets in source; pin and verify
dependencies (`dependency-vetting`).

### The self-check before opening a PR
`/implement` enforces it; manually:

1. Does each AC have a test that **fails without my change**?
2. Error paths and boundaries tested, not just the happy path?
3. Can I point at the line implementing each allocated control?
4. New dependency — justified, licensed, verified to exist (`dependency-vetting`)?
5. Does it emit what an operator needs at 3 a.m.?
6. **What did I make worse?** Say it in the PR.
7. AI authorship declared?

**PRs** stay under ~400 changed lines — past that reviewers skim and everyone knows it. Body
follows `.github/PULL_REQUEST_TEMPLATE.md`: issue link, DoD, control evidence, AI declaration.

### Code review (G3)
By an identity that is **not** the author (`secure-code-review` skill). Not style — the linter
does that. Review in order: correctness (including the paths the happy case skips) · security
(authz, input, secrets, the threat model's controls) · failure behavior (dependency down,
hostile input, races) · maintainability · test quality (do the tests constrain behavior, or
pass regardless). Approve, request changes, or **ask a question** — the third is underused and
often the most valuable. Approving code you don't understand is a control failure, not
politeness.

**Control mapping:** SA-3, SA-8, SA-10, SA-11(1)(2), SA-15, SA-17, CM-3, CM-5, SI-10, SI-7,
SR-3/4/11.
