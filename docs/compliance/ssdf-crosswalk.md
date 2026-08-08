# SP 800-218 SSDF — Crosswalk

**Purpose.** 800-53 is the control catalog this process is anchored to; the SSDF is the
SDLC-shaped framing that maps most naturally onto gates. This crosswalk lets a reader who
thinks in SSDF practices find the same machinery, and it is the view most useful when
explaining the process to a software team rather than to an assessor.

Four practice groups: **PO** Prepare the Organization · **PS** Protect the Software ·
**PW** Produce Well-Secured Software · **RV** Respond to Vulnerabilities.

---

## PO — Prepare the Organization

| SSDF | Practice | Here | 800-53 |
|---|---|---|---|
| PO.1 | Define security requirements | Relevance triage at G0/G1; NFR security criteria with numbers | SA-3, SA-8, PL-8 |
| PO.2 | Implement roles and responsibilities | `docs/01-roles.md`; nine agents with mandates and boundaries; SoD matrix | AC-5, AT-2, AT-3 |
| PO.3 | Implement supporting toolchains | `.github/workflows/`; tools pinned and version-controlled | SA-15, CM-6 |
| PO.4 | Define criteria for security checks | Gate checklists in `process/gates/`; severity SLAs | SA-11, CA-2 |
| PO.5 | Implement and maintain secure environments | Environment separation table; synthetic data; ephemeral runners | CM-4(1), SC-7, MP-6 |

## PS — Protect the Software

| SSDF | Practice | Here | 800-53 |
|---|---|---|---|
| PS.1 | Protect all forms of code from unauthorized access and tampering | Branch protection, signed commits, no admin bypass, CODEOWNERS | CM-5, SI-7, AC-3 |
| PS.2 | Provide a mechanism to verify software release integrity | Cosign keyless signing; **verification enforced at deploy** | CM-14, SI-7, SR-11 |
| PS.3 | Archive and protect each software release | Immutable artifacts by digest; SBOM and attestation retained | CM-8, SR-4, AU-11 |

## PW — Produce Well-Secured Software

| SSDF | Practice | Here | 800-53 |
|---|---|---|---|
| PW.1 | Design software to meet security requirements and mitigate risks | G2: STRIDE threat model, control allocation, SA-8 principles | SA-8, SA-11(2), SA-17 |
| PW.2 | Review the software design | G2 co-approval — architect and security are separate identities | SA-11(2), AC-5 |
| PW.4 | Reuse well-secured software | Dependency justification, license check, SCA, **AIC-7 existence verification** | SA-4, SR-3, SR-4, SR-11 |
| PW.5 | Create source code adhering to secure coding practices | `docs/04-development.md` § Secure coding; SAST gating on new findings | SA-15, SI-10 |
| PW.6 | Configure the compilation, interpreter, and build processes | Reproducible builds where supported; least-privilege ephemeral runners | CM-6, AC-6 |
| PW.7 | Review and/or analyze human-readable code | G3 review by a non-author identity; CodeQL every PR | SA-11(1), AC-5 |
| PW.8 | Test executable code | G4: unit, integration, E2E, DAST, negative-case control tests | SA-11, SA-11(8) |
| PW.9 | Configure software to have secure settings by default | SA-8 secure-defaults principle at G2; IaC scanning | CM-6, CM-7 |

## RV — Respond to Vulnerabilities

| SSDF | Practice | Here | 800-53 |
|---|---|---|---|
| RV.1 | Identify and confirm vulnerabilities on an ongoing basis | Daily rescan of **deployed** artifacts; pentest; red-team; disclosure intake | RA-5, CA-8, SI-4 |
| RV.2 | Assess, prioritize, and remediate vulnerabilities | Triage on reachability and exposure, not CVSS alone; severity SLAs; POA&M | RA-7, SI-2, CA-5 |
| RV.3 | Analyze vulnerabilities to identify root causes | Blameless postmortems; gate-failure analysis; `/retro` → `/learn` → a diff | IR-4, CA-7, SA-15 |

---

## Where the two framings differ usefully

**SSDF is better at** describing what a development team does day to day. PW.7 ("review
human-readable code") is a sentence a developer acts on; SA-11(1) is a catalog entry.

**800-53 is better at** the surrounding accountability structure — AC-5 separation of duties,
AU audit trails, CA assessment and POA&M discipline, CM change control. The SSDF assumes
these exist; it does not specify them.

This process needs both, which is why it is anchored to 800-53 and crosswalked here rather
than the reverse. If you are explaining the process to engineers, lead with this page. If you
are explaining it to an assessor, lead with `nist-800-53-control-map.md`.

**SSDF and AI.** SP 800-218A extends the SSDF to generative AI development. Where you build
AI *systems* (not merely use them), map `docs/12-ai-feature-governance.md` onto 800-218A's
extended practices; the eval, red-team, and data-governance requirements here align to it
directly.
