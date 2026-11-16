# Claude in ~/brain

This folder is a second brain. Follow the protocol:

@BRAIN.md

The current context (profile, brief, recent digests, today's conversations) is
injected at session start by the hook in `.claude/settings.json`
(`python3 tools/brain.py context claude`). If it's missing, run that command yourself.
