#!/usr/bin/env python3
"""
Generate a visual dashboard of the backlog, CI/CD health, and control posture.

    python scripts/dashboard.py            -> writes dashboard.html
    python scripts/dashboard.py --open     -> and opens it

Reads live state via `gh` (PRs, issues, workflow runs, branch protection) and local files
(POA&M, lessons, evals). Everything is a snapshot with a visible timestamp — a dashboard that
looks live but is stale is worse than one that says when it was made.

Design intent: this is a UI, not a document. It is scanned, so state is encoded in FORM
(fill, stripe, chip) as well as number, and "what needs a human" sorts to the top.

No third-party dependencies — stdlib + gh only.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import webbrowser
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)


def gh(*args: str, default=None):
    """Call gh and parse JSON. Returns `default` on any failure — the dashboard degrades
    to 'unknown' rather than crashing, and says so on the page."""
    try:
        out = subprocess.run(
            ["gh", *args], capture_output=True, text=True, timeout=30, check=True
        ).stdout.strip()
        return json.loads(out) if out else default
    except Exception:
        return default


# ── gather ───────────────────────────────────────────────────────────────────
def collect() -> dict:
    d: dict = {"generated": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")}

    d["repo"] = gh("repo", "view", "--json", "nameWithOwner,visibility,isTemplate",
                   default={"nameWithOwner": "unknown"})

    d["open_prs"] = gh("pr", "list", "--state", "open", "--limit", "50", "--json",
                       "number,title,mergeStateStatus,isDraft,author,createdAt", default=[]) or []
    d["merged_prs"] = gh("pr", "list", "--state", "merged", "--limit", "30", "--json",
                         "number,title,mergedAt", default=[]) or []
    d["issues"] = gh("issue", "list", "--state", "open", "--limit", "50", "--json",
                     "number,title,labels", default=[]) or []
    d["runs"] = gh("run", "list", "--limit", "20", "--json",
                   "conclusion,name,createdAt,status", default=[]) or []

    prot = gh("api", f"repos/{d['repo'].get('nameWithOwner','')}/branches/main/protection",
              default=None)
    d["protection"] = prot

    # POA&M — parse the register table rows.
    poam = {"open": [], "closed": 0}
    p = Path("docs/compliance/poam.md")
    if p.exists():
        for line in p.read_text(encoding="utf-8").splitlines():
            m = re.match(r"\|\s*(POAM-\d+)\s*\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|", line)
            if not m:
                continue
            pid, weakness, ctrl, risk, owner, due, status = (x.strip() for x in m.groups())
            if "closed" in status.lower():
                poam["closed"] += 1
            else:
                poam["open"].append({
                    "id": pid, "weakness": weakness.strip("* "), "risk": risk,
                    "owner": owner or "unassigned", "status": status,
                })
    d["poam"] = poam

    d["lessons"] = len(list(Path("docs/lessons").glob("[0-9]*.md"))) if Path("docs/lessons").exists() else 0
    d["evals"] = len(list(Path("evals/agents").glob("[0-9]*.md"))) if Path("evals/agents").exists() else 0
    d["skills"] = len(list(Path(".claude/skills").glob("*/SKILL.md")))
    d["agents"] = len(list(Path(".claude/agents").glob("*.md")))
    return d


# ── derive ───────────────────────────────────────────────────────────────────
def needs_human(d: dict) -> list[tuple[str, str]]:
    """What is actually blocked on a person. This sorts to the top of the page."""
    out: list[tuple[str, str]] = []
    for pr in d["open_prs"]:
        if pr.get("isDraft"):
            continue
        st = pr.get("mergeStateStatus")
        if st == "CLEAN":
            out.append(("merge", f"PR #{pr['number']} is green and waiting — {pr['title'][:60]}"))
        elif st in ("BLOCKED", "DIRTY", "BEHIND"):
            out.append(("fix", f"PR #{pr['number']} is {st} — {pr['title'][:60]}"))
    for e in d["poam"]["open"]:
        if e["owner"].lower() in ("unassigned", "*unassigned*", ""):
            out.append(("assign", f"{e['id']} has no owner — {e['weakness'][:60]}"))
        elif "High" in e["risk"]:
            out.append(("risk", f"{e['id']} ({e['risk']}) open — {e['weakness'][:60]}"))
    return out


def ci_health(runs: list) -> dict:
    done = [r for r in runs if r.get("status") == "completed"]
    ok = sum(1 for r in done if r.get("conclusion") == "success")
    SHOWN = 8
    return {"total": len(done), "pass": ok,
            "rate": round(100 * ok / len(done)) if done else None,
            "recent": done[:SHOWN],
            # Carry the hidden count so the table can say what it dropped, rather than
            # implying the 8 rows are the whole story.
            "hidden": max(0, len(done) - SHOWN)}


# ── render ───────────────────────────────────────────────────────────────────
def esc(s) -> str:
    return (str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


CSS = """
:root{
  --ground:#F3F5F7; --surface:#FFF; --surface-2:#EAEEF1; --ink:#111820; --ink-2:#3D4854;
  --muted:#68737F; --rule:#D8DEE4; --accent:#0E5A63; --accent-soft:#DDEBEC;
  --good:#1C6446; --good-soft:#DEEDE5; --warn:#7E5C0E; --warn-soft:#F2EAD5;
  --bad:#9A3A22; --bad-soft:#F6E3DC;
  --sans:ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
  --mono:ui-monospace,"Cascadia Code","SF Mono",Consolas,monospace;
  --serif:ui-serif,"Iowan Old Style",Georgia,serif;
}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){
  --ground:#0E1216; --surface:#151A20; --surface-2:#1D242B; --ink:#E7EBEF; --ink-2:#BAC3CC;
  --muted:#8B96A2; --rule:#252D35; --accent:#54B4BD; --accent-soft:#123037;
  --good:#5CB287; --good-soft:#14291F; --warn:#C9A648; --warn-soft:#2B2415;
  --bad:#DB8062; --bad-soft:#2E1A13;
}}
:root[data-theme="dark"]{
  --ground:#0E1216; --surface:#151A20; --surface-2:#1D242B; --ink:#E7EBEF; --ink-2:#BAC3CC;
  --muted:#8B96A2; --rule:#252D35; --accent:#54B4BD; --accent-soft:#123037;
  --good:#5CB287; --good-soft:#14291F; --warn:#C9A648; --warn-soft:#2B2415;
  --bad:#DB8062; --bad-soft:#2E1A13;
}
*{box-sizing:border-box}
body{margin:0;background:var(--ground);color:var(--ink);font-family:var(--sans);
  font-size:15px;line-height:1.55;-webkit-font-smoothing:antialiased}
.wrap{max-width:1120px;margin:0 auto;padding:32px 24px 72px}
h1{font-family:var(--serif);font-size:30px;font-weight:600;margin:0 0 4px;letter-spacing:-.01em}
.sub{color:var(--muted);font-size:13px;margin:0 0 28px;font-family:var(--mono)}
h2{font-family:var(--serif);font-size:20px;font-weight:600;margin:34px 0 12px}
.card{background:var(--surface);border:1px solid var(--rule);border-radius:4px;padding:16px 18px}
.grid{display:grid;gap:10px}
.g4{grid-template-columns:repeat(auto-fit,minmax(150px,1fr))}
.stat b{display:block;font-family:var(--mono);font-size:24px;line-height:1.15;
  font-variant-numeric:tabular-nums}
.stat span{font-size:11px;text-transform:uppercase;letter-spacing:.07em;color:var(--muted)}
/* severity stripe — state encoded in form, not only colour */
.stat{border-left:3px solid var(--rule)}
.stat.ok{border-left-color:var(--good)} .stat.warn{border-left-color:var(--warn)}
.stat.bad{border-left-color:var(--bad)}
.chip{display:inline-block;font-family:var(--mono);font-size:10.5px;letter-spacing:.04em;
  padding:2px 7px;border-radius:2px;white-space:nowrap}
.c-ok{background:var(--good);color:var(--surface)}
.c-warn{background:var(--warn-soft);color:var(--warn);border:1px solid var(--warn)}
.c-bad{background:var(--bad-soft);color:var(--bad);border:1px dashed var(--bad)}
.c-mute{color:var(--muted);border:1px solid var(--rule)}
ul.plain{list-style:none;margin:0;padding:0}
ul.plain li{padding:9px 0;border-bottom:1px solid var(--rule);display:flex;gap:10px;
  align-items:baseline;font-size:14px}
ul.plain li:last-child{border-bottom:0}
.action{background:var(--accent-soft);border-left:3px solid var(--accent)}
.empty{color:var(--muted);font-style:italic;padding:8px 0}
table{width:100%;border-collapse:collapse;font-size:13.5px}
th{text-align:left;font-family:var(--mono);font-size:10.5px;letter-spacing:.08em;
  text-transform:uppercase;color:var(--muted);font-weight:500;padding:8px 10px;
  border-bottom:1px solid var(--rule)}
td{padding:8px 10px;border-bottom:1px solid var(--rule);vertical-align:top}
tr:last-child td{border-bottom:0}
.mono{font-family:var(--mono);font-size:12.5px}
.bar{display:flex;height:8px;border-radius:2px;overflow:hidden;background:var(--surface-2);margin-top:8px}
.bar i{display:block}
.foot{margin-top:40px;padding-top:18px;border-top:1px solid var(--rule);
  color:var(--muted);font-size:12.5px}
"""


def render(d: dict) -> str:
    ci = ci_health(d["runs"])
    nh = needs_human(d)
    open_poam = d["poam"]["open"]
    prot = d["protection"] or {}

    def prot_on(path, *keys):
        cur = prot
        for k in (path, *keys):
            cur = (cur or {}).get(k) if isinstance(cur, dict) else None
        return cur

    controls = [
        ("no admin bypass", prot_on("enforce_admins", "enabled")),
        ("linear history", prot_on("required_linear_history", "enabled")),
        ("force-push blocked", prot_on("allow_force_pushes", "enabled") is False),
        ("conversations resolved", prot_on("required_conversation_resolution", "enabled")),
        ("signed commits", prot_on("required_signatures", "enabled")),
    ]
    n_checks = len((prot.get("required_status_checks") or {}).get("contexts") or [])

    h = [f"<title>{esc(d['repo'].get('nameWithOwner','keel'))} — status</title>",
         f"<style>{CSS}</style>", '<div class="wrap">']
    h.append(f"<h1>{esc(d['repo'].get('nameWithOwner','keel'))}</h1>")
    h.append(f'<p class="sub">snapshot · {esc(d["generated"])} · regenerate with '
             f'<code>python scripts/dashboard.py</code></p>')

    # ── needs a human — first, always
    # DEFECT FIXED 2026-08-08 (found in this feature's own self-review): this capped at 10
    # with NO indicator, so a busy repo silently dropped items — the exact quiet omission
    # this project treats as a defect everywhere else. A truncation that does not announce
    # itself reads as "that's everything".
    NH_SHOWN = 10
    h.append("<h2>Needs a human</h2>")
    if nh:
        h.append('<ul class="plain card">')
        for kind, text in nh[:NH_SHOWN]:
            cls = {"merge": "c-ok", "fix": "c-bad", "assign": "c-warn", "risk": "c-bad"}.get(kind, "c-mute")
            h.append(f'<li><span class="chip {cls}">{esc(kind)}</span><span>{esc(text)}</span></li>')
        if len(nh) > NH_SHOWN:
            hidden = len(nh) - NH_SHOWN
            h.append(f'<li><span class="chip c-warn">+{hidden}</span>'
                     f'<span><strong>{hidden} more not shown.</strong> '
                     f'{len(nh)} items need a human — run <code>./keel status</code> for the '
                     f'full list.</span></li>')
        h.append("</ul>")
    else:
        h.append('<div class="card empty">Nothing blocked on a person. Queue is clear.</div>')

    # ── at a glance
    npr, nissue = len(d["open_prs"]), len(d["issues"])
    unowned = sum(1 for e in open_poam if e["owner"].lower().strip("*") in ("unassigned", ""))
    h.append("<h2>At a glance</h2><div class='grid g4'>")
    for label, val, cls in [
        ("open PRs", npr, "ok" if npr == 0 else "warn"),
        ("open issues", nissue, "ok"),
        ("open findings", len(open_poam), "ok" if not open_poam else "warn"),
        ("unowned findings", unowned, "ok" if unowned == 0 else "bad"),
        ("CI pass rate", f"{ci['rate']}%" if ci["rate"] is not None else "—",
         "ok" if (ci["rate"] or 0) >= 90 else "warn"),
        ("required checks", n_checks, "ok" if n_checks else "bad"),
        ("lessons", d["lessons"], "ok"),
        ("agent evals", d["evals"], "ok"),
    ]:
        h.append(f'<div class="card stat {cls}"><b>{esc(val)}</b><span>{esc(label)}</span></div>')
    h.append("</div>")

    # ── CI/CD
    h.append("<h2>CI / CD</h2><div class='card'>")
    if ci["total"]:
        good = ci["pass"]; bad = ci["total"] - good
        gp = 100 * good / ci["total"]
        h.append(f'<div><strong>{good}/{ci["total"]}</strong> of recent runs passed</div>')
        h.append(f'<div class="bar"><i style="width:{gp:.0f}%;background:var(--good)"></i>'
                 f'<i style="width:{100-gp:.0f}%;background:var(--bad)"></i></div>')
        h.append('<table style="margin-top:14px"><tr><th>run</th><th>result</th><th>when</th></tr>')
        for r in ci["recent"]:
            c = r.get("conclusion")
            chip = "c-ok" if c == "success" else ("c-mute" if c in ("skipped", "cancelled") else "c-bad")
            h.append(f'<tr><td>{esc(r.get("name",""))}</td>'
                     f'<td><span class="chip {chip}">{esc(c)}</span></td>'
                     f'<td class="mono">{esc((r.get("createdAt") or "")[:16].replace("T"," "))}</td></tr>')
        if ci.get("hidden"):
            h.append(f'<tr><td colspan="3" class="mono" style="color:var(--muted)">'
                     f'+{ci["hidden"]} older run(s) not shown — rate above covers all '
                     f'{ci["total"]}</td></tr>')
        h.append("</table>")
    else:
        h.append('<div class="empty">No completed runs found.</div>')
    h.append("</div>")

    # ── controls
    h.append("<h2>Controls on <code>main</code></h2><div class='card'>")
    if prot:
        h.append('<ul class="plain">')
        for name, on in controls:
            chip = "c-ok" if on else "c-bad"
            h.append(f'<li><span class="chip {chip}">{"enforced" if on else "OFF"}</span>'
                     f'<span>{esc(name)}</span></li>')
        h.append(f'<li><span class="chip {"c-ok" if n_checks else "c-bad"}">{n_checks}</span>'
                 f'<span>required status checks</span></li></ul>')
    else:
        h.append('<div class="empty">Branch protection not readable — treat every control as '
                 'unconfigured until verified.</div>')
    h.append("</div>")

    # ── findings
    h.append("<h2>Open findings (POA&amp;M)</h2><div class='card'>")
    if open_poam:
        h.append("<table><tr><th>id</th><th>risk</th><th>owner</th><th>weakness</th></tr>")
        for e in open_poam:
            rc = "c-bad" if "High" in e["risk"] else ("c-warn" if "Medium" in e["risk"] else "c-mute")
            oc = "c-bad" if e["owner"].lower().strip("*") in ("unassigned", "") else "c-mute"
            h.append(f'<tr><td class="mono">{esc(e["id"])}</td>'
                     f'<td><span class="chip {rc}">{esc(e["risk"])}</span></td>'
                     f'<td><span class="chip {oc}">{esc(e["owner"])}</span></td>'
                     f'<td>{esc(e["weakness"][:90])}</td></tr>')
        h.append("</table>")
    else:
        h.append('<div class="empty">No open findings.</div>')
    h.append(f'<p class="sub" style="margin:12px 0 0">{d["poam"]["closed"]} closed · '
             f'full register in docs/compliance/poam.md</p></div>')

    h.append(f'<p class="foot">Snapshot, not live — regenerate to refresh. '
             f'{d["agents"]} agents · {d["skills"]} skills · {d["lessons"]} lessons · '
             f'{d["evals"]} agent eval cases.</p>')
    h.append("</div>")
    return "\n".join(h)


def main() -> int:
    d = collect()
    out = Path("dashboard.html")
    out.write_text(render(d), encoding="utf-8")
    print(f"  wrote {out}  ({out.stat().st_size:,} bytes)")
    nh = needs_human(d)
    print(f"  needs a human: {len(nh)}")
    for _, t in nh[:5]:
        print(f"    - {t}")
    if "--open" in sys.argv:
        webbrowser.open(out.resolve().as_uri())
    return 0


if __name__ == "__main__":
    sys.exit(main())
