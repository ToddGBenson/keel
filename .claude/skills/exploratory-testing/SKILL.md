---
name: exploratory-testing
description: Run charter-driven exploratory testing to find defects scripted tests cannot reach. Use during the G4 QA gate, when asked to explore or manually test a feature, when a story is complex or risky, after an incident, or when scripted tests all pass but confidence is low. Covers charter design and the productive heuristics.
---

# Exploratory testing

Consumers: `qa-engineer`, `/qa-gate`, `process/gates/g4-verified.md`.

## Why it is not redundant with the test suite

**Scripted tests find what someone already thought of.** They encode yesterday's
understanding, which is exactly the understanding that produced the bug.

Exploration is simultaneous learning, test design, and execution. It is where the expensive
defects are found, because expensive defects live in the space nobody modelled — and it is
the cheapest testing you can do per defect found.

It is not "clicking around". It is disciplined, charter-driven, time-boxed, and it produces
evidence.

## The charter

Written **before** you start. Without one, exploration drifts to whatever is most familiar
and you re-test the happy path with extra steps.

```
Charter:   Explore draft recovery across concurrent sessions
           to discover data-loss and cross-user-visibility defects
Time-box:  45 minutes
Setup:     Two browsers, same user; a second user account; staging with synthetic data
Out:       Performance, accessibility (covered separately)
```

Format: **Explore `<area>` with `<resources>` to discover `<information>`.**

Keep it to 45–90 minutes. Beyond that, attention degrades and note quality collapses — take
a break and write a second charter instead.

**One risk per charter.** A charter naming three unrelated risks will get one of them tested
properly.

## Heuristics that reliably find things

**Concurrency and interleaving.** Two tabs, same user, divergent edits. Two users, same
resource. Submit twice quickly. Start an action, then start another before it completes.
Race the save against the timeout.

**State transitions.** Log out mid-action. Let the session expire during an in-flight
request. Change a permission while a session holds the old one. Navigate back after
submitting. Refresh at every step. Use the browser's back button — it is the most under-tested
control in every web application.

**Boundaries, and just past them.** Empty, one, exactly the limit, limit+1, maximum,
maximum+1. Zero, negative, very large. Empty string vs. whitespace vs. null.

**Data that looks nothing like demo data.** Unicode, emoji, RTL text, names with apostrophes,
very long strings, HTML, SQL fragments, newlines in single-line fields, leading and trailing
whitespace, a filename with a semicolon.

**Dependency degradation.** Not "down" — **slow**. Throttle the network. That path is almost
never tested and behaves far worse than the outage path, which at least has an error handler.

**The misunderstanding path.** What does a user do who has misread the feature? Who expects
it to work like the competitor's? Who is halfway through and interrupted?

**The second time.** Most features are tested once, on a clean account. Use it five times.
Use it after having already used the adjacent feature. Accumulate state.

**Interruption.** Close the laptop. Lose connectivity mid-request. Kill the tab during a
save.

## Note-taking, as you go

Not afterward. Reconstruction is where the truth quietly changes, and the detail that turns
out to matter is the one you did not think worth writing.

```
14:02 two tabs, same doc, edits in both → last-write-wins, no conflict surfaced,
      no indication the other edit existed. Reproducible 3/3. → #204 (Major)
14:11 session expiry during in-flight autosave → draft saved under expired session,
      invisible after re-auth. Data is in the DB but unreachable. → #205 (High)
14:20 5 MB limit: eviction fires but the notice renders behind the modal — cosmetic
14:31 tried to reproduce #205 with a slow network instead of expiry — did not repro
```

Record what you tried that **found nothing**. It is the only thing that distinguishes
"we tested that and it held" from "we never got to it", and at G4 that distinction is the
difference between coverage and a coverage claim.

## Debrief

At the end of the time-box:

1. **What did you find?** File each as an issue with reproduction steps.
2. **What did you cover?** Areas touched, and how deeply.
3. **What did you not reach?** Deferred, out of scope, or blocked.
4. **What is the next charter?** Findings usually suggest one — a defect in one area is
   evidence about the class of thinking that produced it.

The charter and the notes go to `evidence/<issue>/g4/qa/exploratory-charter.md`. They are
SA-11 evidence.

## Handing off findings

Reproduction steps, expected vs. actual, severity, and **how consistently it reproduces**.
"Intermittent 1 in 5" is a legitimate and important finding — it usually means a race, and a
race that reproduces one time in five in a manual session reproduces constantly in
production.

You do not fix what you find. File it and hand to `developer` — a tester who fixes becomes a
tester who stops looking hard.

## Time-boxing is the discipline

When the box ends, stop. Write the debrief. If the area deserves more, that is a new charter
with a fresh question — not an extension that runs until attention fails.

## Controls

SA-11 (developer testing and evaluation) · CA-2 · SI-2 (defects found feed remediation).
