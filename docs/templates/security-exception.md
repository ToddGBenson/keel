# Security Exception / Risk Acceptance — EXC-<n>

**Requested by:** · **Date:** · **Control(s):** · **Related:** issue #<n>, POAM-<n>

> The only legitimate way to proceed without a control. **Time-boxed, justified,
> human-approved, POA&M-tracked.** An undocumented deviation is not an exception — it is a
> control failure.

## 1. What control is not being met?

The specific control (800-53 ID or AIC-<n>) and what the requirement is.

## 2. What is the actual gap?

Precisely what is missing or ineffective. Not "we need more time" — what is *not true* that
should be.

## 3. Why can it not be met now?

The real reason. Schedule pressure is a legitimate reason to *request* an exception and an
illegitimate reason to *grant* one without weighing the risk. Say which it is.

## 4. Risk

**What could happen:** the concrete failure, not the control's abstract purpose.
**Who is exposed:** users, data, systems.
**Likelihood and impact:** with reasoning.
**Severity:** Critical / High / Medium / Low.

If the severity is Critical or High, note that this exception requires an explicit human
decision to carry the risk, and that the decision is attributable.

## 5. Compensating controls

What reduces exposure while the exception is open. **"None" is an answer** — but it must be
stated, not omitted, because it changes the decision.

| Compensating control | Reduces | Effective? |
|---|---|---|

## 6. Remediation plan

What will be done, by whom, by when. Milestones if the work is longer than a sprint.

**Owner:** a named person, never a team.

## 7. Expiry

**Expires:** <date> — mandatory. **Maximum duration by severity:** Critical 7d · High 30d ·
Medium 90d · Low 180d.

**Indefinite acceptance is not acceptance.** It is a decision to carry the risk permanently,
and if that is what is meant, it should be written that way and approved on that basis — not
disguised as a temporary exception that is quietly renewed.

## 8. What happens at expiry?

The control is implemented, or the exception is re-requested with a fresh decision, or the
feature is removed. **Automatic renewal is prohibited.**

If this exception has already been extended once, say so here. A second extension is a
resourcing or will problem, not a schedule problem, and it should be named as one.

## 9. Approval

| Role | Name | Decision | Date |
|---|---|---|---|
| Security Engineer | | recommend / oppose | |
| AI Risk Officer *(if AI-related)* | | recommend / oppose | |
| **Human operator** | | **approve / deny** | |

**A human approves. Always.** An agent may prepare and recommend; it may not accept risk on
anyone's behalf, because accountability cannot be delegated to something that cannot hold it.

The Security Engineer's or AI Risk Officer's opposition does not block the human's decision —
but it is **recorded**, and the human is approving over a stated objection. That record is
the point.

## 10. Tracking

POA&M entry: **POAM-<n>** — created on approval, closed only on evidence of remediation.
Reviewed at every weekly security review and reported in `/status risks`.
