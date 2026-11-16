---
name: client-mail
description: Use when the user needs to write, answer or rephrase an email to a client, user or vendor, in French
  or English (acknowledgment, request for information, resolution, follow-up/reminder, planned maintenance,
  delay/escalation, quote). Drafts only, never sends.
---
# Client email

## Rules
- **Never send.** Produce the draft; the user copies it.
- **Language**: the language of the client's last message. If none: the default language in `memory/profile.md`.
- **Tone**: formal by default. French: *vous*, "Bonjour Madame X," / "Bonjour Monsieur X,",
  closing "Cordialement," or "Meilleures salutations," (Swiss usage).
  English: "Dear Ms/Mr X," / "Hello X," and "Kind regards,". Informal only if the user asks.
- **Structure**: subject line, greeting, 1 sentence of context, what was done/found,
  what happens next (who does what, when), what we need from them (if anything,
  as a short list), closing, signature.
- Short sentences. No jargon unless the recipient is technical. Never blame the client.
- Commit to dates only if the user gave one; otherwise write `{{date}}` for the user to fill in.
- Signature: from `memory/profile.md` (`## Email signature`). If empty, use `{{signature}}`
  and remind the user once to fill it in.
- Look at `clients/<client>.md` for the contact's name, language and preferences.

## Variants
`fr.md` and `en.md` hold a skeleton for each variant:
accusé de réception / acknowledgment · demande d'informations / information request ·
résolution / resolution · relance / follow-up · maintenance planifiée / planned maintenance ·
retard ou escalade / delay or escalation.
Adapt them; never paste them verbatim when the situation differs.

## After drafting
- If the mail promises something (callback, date, intervention), add a task to `tasks.md`.
- If it's linked to a ticket, add a line to the ticket's Log: `mail sent: <subject>` (once the user confirms).
- Show the subject on its own line, then the body in a code block, so it's easy to copy.
