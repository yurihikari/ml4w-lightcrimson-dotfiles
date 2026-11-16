---
name: weekly-review
description: Use when the user asks for a weekly review, a recap of the week, or to clean up tasks and inbox
  (typically Friday or Monday).
---
# Weekly review

1. **Recap**: read the digests (`memory/daily/`) of the last 7 days → 5 bullets of what got done.
2. **Inbox to zero**: for each `inbox.md` item, propose where it goes (task / client / project / note / delete).
   Apply after the user confirms, in one batch.
3. **Tasks**: list overdue tasks and ask for each: do, reschedule (new date), delegate or drop.
   Move `[x]` tasks older than 14 days from `## Open` to `## Done` (keep them; don't delete).
4. **Tickets**: open tickets with no Log entry for 5+ days → suggest a follow-up mail.
5. **Open threads** from the digests that have no task yet → propose tasks.
6. **Profile**: "About the user" items from the digests → add to `memory/profile.md` if not already there.
7. **Next week**: the 3 most important outcomes, written to `journal/<monday's date>.md`.
8. Commit: `python3 ~/brain/tools/brain.py commit "weekly review"`.
