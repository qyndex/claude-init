---
description: Capture a hand-written lesson learned and persist it to .claude/memory/incidents/ or .claude/memory/decisions/. Complement to the auto-extracted instinct skill — this is the explicit, narrative path. Use after a debugging session, a postmortem, or any moment where you want to teach the agent (and your team) something.
argument-hint: "<short title or 'auto' to prompt for fields>"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, TodoWrite
disable-model-invocation: true
---

# /lesson-learned — Capture an explicit lesson

The auto-extracted `instinct` skill catches patterns Claude noticed. `/lesson-learned` is for the things YOU want to teach — usually because they were painful to learn.

## Process

1. **Parse argument.** If `$ARGUMENTS` is empty or `auto`, interview the user (via AskUserQuestion, ≤4 questions):
   - What's the title in 6-10 words?
   - Category: `incident` | `decision` | `pattern` | `playbook`
   - What was the trigger / context?
   - What's the lesson — in one paragraph?
2. **Pick the target directory** based on category:
   - `incident` → `.claude/memory/incidents/<date>-<slug>.md` (template: `incidents/0000-template.md`)
   - `decision` → `.claude/memory/decisions/<n>-<slug>.md` (template: `decisions/0000-template.md`)
   - `pattern` → `.claude/memory/patterns/<n>-<slug>.md` (template: `patterns/0000-template.md`)
   - `playbook` → `.claude/memory/playbooks/<slug>.md` (template if available, else free-form)
3. **Copy the template**, fill in the user's answers, leave `[TODO]` markers for sections requiring narrative the user didn't supply.
4. **Open the file** for the user to flesh out (or auto-fill if running headless).
5. **Append a one-liner** to `.claude/memory/MEMORY.md` under the appropriate section pointing at the new file.
6. **Surface** the file path + a one-line summary of what was captured.

## When to use which category

| Category | When |
|---|---|
| `incident` | Something broke. You debugged. Write the postmortem so it doesn't happen again. |
| `decision` | You chose between two options. Write an ADR so future-you remembers why. |
| `pattern` | You found a recurring solution worth naming. Codify it so others reuse. |
| `playbook` | You did an operational task (rollback, migration, key rotation). Write the recipe. |

## Hard rules

- **No empty `[TODO]` sections in the final file.** Either fill them in or remove them.
- **Cite evidence.** Reference commits (SHAs), PRs, files (path:line), or logs. A lesson without evidence is folklore.
- **Update MEMORY.md.** A file in `.claude/memory/` that isn't indexed won't be loaded by sessions and won't be discoverable.
- **Tag for path-scoping** if relevant: add a `paths:` frontmatter glob so the lesson only loads in relevant contexts.

## Output

```
.claude/memory/<category>/<file>.md   (new)
.claude/memory/MEMORY.md              (appended)
```

After save: "Lesson `<title>` saved to `.claude/memory/<category>/<file>.md` and indexed in MEMORY.md."

## Example

```
> /lesson-learned "prod migration deadlock"
  ↳ asks category → incident
  ↳ asks trigger → "ran ALTER TABLE during peak hours"
  ↳ asks lesson → "always run schema migrations during low-traffic windows..."
  ↳ writes .claude/memory/incidents/2026-05-27-prod-migration-deadlock.md
  ↳ appends MEMORY.md
```

## References

- Templates: `.claude/memory/{decisions,incidents,patterns}/0000-template.md`
- Sibling skill: `.claude/skills/instinct/` (auto-extracted observations)
- Memory index: `.claude/memory/MEMORY.md`
