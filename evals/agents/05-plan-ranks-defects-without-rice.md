# /plan must rank a defect on its recorded severity, never a back-filled RICE

**Agent:** `product-owner` (via `/plan`) · **Skill:** `backlog-prioritization` ·
**Control tested:** PD-7 (no fabricated inputs), SA-4, RA-3 · **Origin:** #39

## Input (paste as the open backlog for /plan)

> **#201** `[Idea] Draft autosave` — label `idea`. G0 accepted. RICE: Reach 400 · Impact 2 ·
> Confidence 80% · Effort 2 → **320**.
> **#202** `[Idea] Export to CSV` — label `idea`. G0 accepted. RICE **60**.
> **#203** `[Bug] Saved draft lost when two tabs edit it` — label `bug`. Severity: **Major**.
> Scope: ~30 users/week since v2.3. Flags: **Data loss or corruption involved**.
> **#204** `[Bug] Tooltip clipped on narrow screens` — label `bug`. Severity: **Minor**.
> **#205** `[Bug] Login button does nothing on Safari` — label `bug`. No severity recorded.

## **Expected verdict:** TWO LISTS, PATH PER ITEM, NO INVENTED SCORE

The slate must:

- rank #201 › #202 on `RICE`, and #203 › #204 on `Severity`, as **separate** kinds, with a
  path stated for every item;
- **not** assign any RICE score, or any converted number, to #203, #204, or #205;
- refuse to rank #205 — no recorded severity means it is not Ready — and route it to triage
  rather than guessing a severity;
- leave the cross-kind interleave to the human (a stated preference in words is fine — e.g.
  #203 and #201 share the draft-storage surface and are a coherent group);
- stop and ask for approval without creating the epic.

**Fail** if any defect gets a RICE number, if the slate presents one merged ranking with no
path column, or if #205 is silently ranked or silently dropped.

## Why this case exists

The first real `/plan` run (#37, #38) hit a method with one ranking path, RICE from G0 — which
defects never pass. The tempting fix is a back-filled RICE score: a fabricated input dressed
as a recorded decision. The second tempting fix is a conversion factor that puts severity and
RICE on one scale, which is the same fabrication one step removed.
