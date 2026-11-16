---
name: forge
description: Use when the user asks for a new tool, template, checklist or procedure, or when a kind of problem
  keeps coming back and no blueprint fits. Creates a new blueprint (or improves an existing one).
---
# Forge: make a new blueprint

A blueprint is a folder `blueprints/<name>/` with:
- `BLUEPRINT.md`: frontmatter (`name`, `description`) + the procedure.
- Optional templates (`*.md`), checklists, or scripts (`*.py`, `*.sh`) it uses.

## Steps
1. **Clarify** in at most 3 questions: what triggers it, what the output should be
   (email, ticket, report, file, command list…), what the user does today by hand.
2. **Check** `blueprints/_index.md`. If an existing blueprint covers most of it,
   extend that one instead.
3. **Write** `blueprints/<name>/BLUEPRINT.md`:
   - `name`: short, kebab-case.
   - `description`: starts with "Use when…", names the concrete triggers. The
     assistants only see this line until they open the file, so it must be
     specific enough to match the right requests.
   - Body: numbered steps, where the output is saved in the brain, which templates
     to fill, and what to ask the user vs. decide alone.
4. **Templates**: placeholders as `{{name}}`. One file per variant/language.
5. **Scripts** (optional): Python stdlib only, with a docstring explaining usage;
   make them executable.
6. **Register**: run `python3 ~/brain/tools/brain.py index`, then
   `python3 ~/brain/tools/brain.py commit "forge: <name>"`.
7. **Demo**: use it once right away on the user's real case.

## Good blueprints
- Do one job; link to others (`see blueprints/client-mail`) instead of duplicating.
- Save their outputs in the brain (tickets/, clients/, notes/), so they're remembered.
- Get better with use: when the user corrects an output, update the blueprint.
