# G1 Ready (Definition of Ready) - hub-60981

key: hub-60981
date: 2026-10-23
verdict: fail
recommending role: product-owner+ux
recorded by: developer agent (Claude Opus 5.5) assessing for product-owner; not independent of the implementer (POAM-017)

## Checklist (.sdlc/process.yaml)

- ac-binary: NOT satisfied - gap: the six AC are declarative statements, not Given/When/Then; several are binary (AC-2, AC-3) but none states its Given
- sized: satisfied
- flags: NOT satisfied - gap: security/process relevance is flagged (control-relevant files, G2-lite on key validation); AI and privacy relevance are not stated either way
- no-open-question: NOT satisfied - gap: AC-4 counts a gate only with a verdict: line, but all 15 existing G3 records have none; whether to grandfather them, backfill them, or let G3 read 0 changes the design

Written by scripts/gate-record.py. Approval of G1 belongs to the Delivery Lead (ADR-0005); this record is the recommendation, not the approval.
