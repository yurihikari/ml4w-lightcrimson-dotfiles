---
name: support-ticket
description: Use for any IT support case. A client or user reports a problem or asks for help (mail forwarded
  by the user, phone call summary, "client X has a problem with Y"), or the user works an incident. Covers
  intake, tracking, diagnosis, client communication and closing.
---
# Support ticket

## 1. Intake
Extract from what the user gives (mail, call notes, a sentence):
client, contact, affected users/devices, symptom, since when, impact (users blocked? data at risk?),
what was already tried. Ask only for what's missing **and** blocking (max 3 questions).

Urgency: **P1** many users blocked / security / data loss · **P2** one user blocked ·
**P3** degraded, workaround exists · **P4** request / question.

## 2. Record
- Create `tickets/YYYY-MM-DD-<client>-<topic>.md` from `ticket.md` (this folder).
- If `clients/<client>.md` doesn't exist, create it from `templates/client.md`.
- Add a task to `tasks.md`: `- [ ] [P2] <client>: <topic> 📅 <due> #support [[tickets/<file>]]`.
  Due: P1 today, P2 today/tomorrow, P3 within 3 working days, P4 within a week.

## 3. Diagnose
- Follow `blueprints/troubleshoot`. Give ranked hypotheses + the exact commands/checks
  the user can run (PowerShell, cmd, Linux, M365 admin, the RMM…).
- Search `notes/kb/` and past `tickets/` for the same symptom first (Grep).
- Log every finding in the ticket's **Log** with time.

## 4. Communicate
- If the client hasn't heard back yet: draft an acknowledgment with `blueprints/client-mail` (same day).
- Long case: suggest a status update every 1–2 days for P1/P2.

## 5. Close
- Fill **Resolution** and **Root cause** and estimate the time spent.
- Draft the resolution email (client-mail, variant "résolution").
- Mark the task done. Add a line to the client file's **History**.
- If the fix could be reused: write `notes/kb/<topic>.md` (symptom → cause → fix → commands).
