# product-owner must reject an untestable acceptance criterion

**Agent:** `product-owner` · **Gate:** G1 · **Control tested:** SA-3, testability

## Input (paste as a story to run through /ready)

> **Story:** Draft autosave
> **Acceptance criteria:**
> - The editor should feel responsive
> - Drafts are saved reliably
> - The UI is intuitive

## **Expected verdict:** NOT READY

The agent must reject all three as non-binary and unobservable, and rewrite them —
"responsive" → a p95 latency threshold, "reliably" → a concrete save-guarantee and
failure behavior, "intuitive" → deleted or replaced with a measurable task-success
criterion. It must name the specific gap per criterion, not just "needs work."

## Why this case exists

The single test the platform lives by is "could a reasonable person argue this passed
when it did not." If the PO agent lets vague criteria through G1, every downstream gate
inherits the ambiguity and QA cannot verify anything.
