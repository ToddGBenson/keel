---
name: story-splitting
description: Split an epic or oversized story into thin vertical slices that each ship independently. Use when refining an epic, when a story is too large to estimate or exceeds ~3 days, when work has been sliced by technical layer, or when asked how to break down a feature. Covers the split axes and when not to split.
---

# Story splitting

Consumers: `product-owner`, `/refine`, `architect` (feasibility), `process/gates/g1-ready.md`.

## The rule

**Split along user-visible value. Never along technical layers.**

Layer slicing feels efficient — it matches how the work is done — and it produces a backlog
where nothing is shippable until everything is finished. That defeats the entire point of
incremental delivery: you lose the ability to stop early, reprioritise, or learn from
something real.

```
✗ LAYER SLICING — nothing ships until all three land
  #1 Create the drafts table
  #2 Build the drafts API endpoint
  #3 Wire up the autosave UI

✓ VERTICAL SLICING — each ships and is independently valuable
  #1 Editor state survives an accidental tab close within the same session
  #2 Editor state survives session expiry and is offered on next sign-in
  #3 User can browse and restore any of their last 5 recovered drafts
```

Each vertical slice touches the database, the API, and the UI. That is correct. A slice that
touches only one layer is a task, not a story.

## The test

> **If we shipped only this one and stopped, would a user be able to do something they
> could not do before?**

If no, it is not a slice. It may still be legitimate work — a chore, a spike, an enabler —
but it is not a story and it should not be sized or prioritised as one.

## The split axes

Try them in roughly this order; the first two cover most cases.

**1. Workflow step.** Take the user's journey and ship it a step at a time.
> Checkout → *ship: cart persists* → *ship: address entry* → *ship: payment* → *ship: confirmation email*

**2. Happy path vs. error path.** The happy path is usually a third of the work and most of
the value. Ship it, then harden.
> *Ship: upload succeeds* → *ship: upload fails gracefully with retry* → *ship: partial upload resume*

**3. CRUD operation.** Create, then read, then update, then delete. Rarely all equally
valuable — often delete can wait a quarter.

**4. Data variation.** One format, then more.
> *Ship: CSV import* → *ship: Excel import* → *ship: malformed-file handling*

**5. User role.** One audience first.
> *Ship: individual users* → *ship: team admins* → *ship: org owners*

**6. Platform / interface.** Web, then mobile, then API.

**7. Performance as its own story.** Make it work; then make it fast, with a number.
> *Ship: search returns correct results* → *ship: search p95 < 200 ms at 10k documents*

This one is frequently missed. "Fast" bolted onto a functional story makes both harder to
verify and hides which part is late.

**8. Business rule complexity.** The simple rule first, the exceptions after.
> *Ship: flat 10% discount* → *ship: tiered discounts* → *ship: stacking and precedence rules*

**9. Defer the hard operational bit.** Ship behind a flag, to internal users, or to one
tenant, before general availability.

## When *not* to split

Splitting has a cost — coordination, integration, review overhead, and cognitive load on
whoever holds the thread. Do not split when:

- The pieces cannot be independently verified, so you get overhead without feedback
- The split is purely technical and every piece is dark until the last one lands
- The result is a story so thin its acceptance criteria are longer than its implementation
- The seam you would create is one you will immediately have to remove

**A story of ~2–3 days is fine.** The ~3-day guideline is a signal to *look*, not a hard cap
requiring a split into four half-day fragments. Fragmentation has its own failure mode: a
backlog of 40 tiny items where nobody can see the shape of the feature.

## Spikes are not slices

If the reason the story is unsplittable is that nobody knows enough to size it, the answer is
a **spike**: time-boxed, produces a written answer and a recommendation, produces **no
production code**. Code written during a spike is thrown away — keeping it is how prototypes
become production systems nobody designed.

## Enablers

Sometimes real infrastructure genuinely must land first. Be honest about it: label it an
**enabler**, note which stories it unblocks, and accept that it delivers no user value on its
own. What you must not do is dress it up as a user story — that hides the true cost of the
feature it serves and corrupts the prioritisation data.

Prefer, where you can, to build the enabler *inside* the first vertical slice that needs it.
The slice justifies the infrastructure and proves it works.

## After splitting

Each resulting story needs its own full G1 treatment — narrative, binary acceptance criteria,
non-functional criteria with numbers, relevance triage (security / AI / privacy), dependencies,
estimate, test approach. See the `writing-acceptance-criteria` skill.

**Re-check INVEST on each piece**, particularly **I**ndependent. Splits frequently create
hidden ordering dependencies; if #2 cannot ship without #1, say so explicitly rather than
discovering it at planning.

## Controls

SA-3 · SA-4(3) (development methods) · SA-15 · AI RMF MAP 2.3.
