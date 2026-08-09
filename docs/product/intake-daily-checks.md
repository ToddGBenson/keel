# Artifact intake — daily checks and home network security

**Source:** `sprint/inbox/daily-checks-and-network-security.md` · **Skill:** `artifact-intake`

## Extracted — stated in the description

| # | Requirement | Source |
|---|---|---|
| E1 | A program that runs "daily tasks and checks" | l.3 |
| E2 | It also checks the home network | l.4 |
| E3 | It also checks security | l.4 |
| E4 | Python | `Stack:` |
| E5 | Runs daily | `Schedule:` |

## Inferred — my reading, NOT stated. Confirm or overrule.

| # | Inference | Basis |
|---|---|---|
| I1 | This is for **one machine on a home LAN**, not a managed fleet | "my home network" |
| I2 | Output is a **report** the user reads, not automated remediation | "checks for me" — checking, not fixing |
| I3 | The checks should be **read-only and safe to run unattended** | it runs daily on a schedule with nobody watching |
| I4 | "Daily tasks" means recurring *system* housekeeping, not personal to-dos | grouped with checks; a to-do list is a different program |

## Unspecified — every one of these is a real decision

| # | Question | Why it matters | **Default chosen** |
|---|---|---|---|
| **U1** | **Which daily tasks?** Entirely undefined | The core of the request | Disk space, pending OS updates, backup freshness, service health, certificate expiry |
| **U2** | **What is "check the network"?** Scan? Inventory? Monitor? | Scanning has legal and safety implications | **Passive inventory of the local subnet only** — devices seen, open ports on *this* host. No active scanning of other hosts |
| **U3** | **What is "security"?** | Unbounded otherwise | Local posture: firewall on, disk encryption, auto-updates, no unexpected listeners, weak-config checks |
| U4 | Where does the report go? | Determines the interface | stdout + a JSON file; notification is a later slice |
| U5 | What is "unhealthy"? | Needs thresholds, not vibes | Disk > 85%, backup > 48 h old, cert < 30 days |
| U6 | Does it need admin/root? | Changes the security profile | **No.** Runs unprivileged; degrades and says so |
| U7 | Windows, macOS, or Linux? | Every check is OS-specific | Cross-platform core; per-OS probes behind a capability check |
| U8 | Retain history? | Trend vs. snapshot | Append JSONL; trends are a later slice |

## ⚠ Flags — this is security-relevant, so G2 is mandatory

**The important finding, and the reason intake exists:** "check my home network" most
naturally reads as *scan the network*. An unattended daily port-scan of a home LAN is a
materially different program from a health check — it can trip IDS, violate an ISP's
acceptable-use policy, and is exactly the behaviour malware exhibits.

**Chosen default: no active scanning of other hosts.** The program inspects *this machine*
and passively reads its own ARP/neighbour table for an inventory. If active scanning is
genuinely wanted, that is a separate story with its own threat model and an explicit
opt-in — not a default that arrives via a one-line description.

Also flagged: the report will contain hostnames, MACs, and local IPs — **privacy-relevant**.
It must stay local and never be transmitted.

## Proposed stories (vertical slices)

| # | Story | Ships alone? |
|---|---|---|
| **1** | **A daily report of this machine's health and security posture** | Yes — useful on day one |
| 2 | Passive inventory of devices on the local subnet | Yes |
| 3 | History and trend detection ("disk filling since Tuesday") | Yes |
| 4 | Notification on failure (email/webhook) | Yes |

Story 1 first: it is the thin slice that delivers value immediately and establishes the
check/report architecture the rest extend.
