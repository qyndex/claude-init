# .claude/commands/ — User-invoked utility commands

This folder holds **user-only slash commands** that don't auto-trigger. They complement the workflow skills in `.claude/skills/` rather than duplicating them.

## Why a split?

Per [Claude Code skills docs](https://code.claude.com/docs/en/skills), custom slash commands were merged into the Skills system in late 2025. Both `.claude/skills/<name>/SKILL.md` and `.claude/commands/<name>.md` work; skills resolve first when names collide.

We use the split deliberately:

| Folder | Purpose | Auto-triggers? |
|---|---|---|
| `.claude/skills/` | Workflow phases + disciplines (`/specify`, `/plan`, `/tdd-loop`, etc.) | yes — by description |
| `.claude/commands/` | User-invoked utilities (`/status`, `/handoff`, `/prime`, etc.) | no — `disable-model-invocation: true` |

The `disable-model-invocation: true` frontmatter on every command in this folder ensures Claude only runs them when **the user** types `/<name>`, never autonomously. This is the right behavior for context-loading, diagnostics, and housekeeping that the user should opt into.

## Commands in this folder

| Command | Purpose |
|---|---|
| [/status](status.md) | Snapshot: branch, dirty, active spec/plan, pending tasks, recent CI |
| [/prime](prime.md) | Load project context at the start of a fresh session |
| [/handoff](handoff.md) | Generate a handoff doc so the next session can resume cold |
| [/health](health.md) | Run the full local health check (validate + lint + typecheck + tests) |
| [/cleanup](cleanup.md) | Routine hygiene: archive done specs, prune branches, vacuum logs |
| [/changelog](changelog.md) | Generate a CHANGELOG entry from Conventional Commits |
| [/diagram](diagram.md) | Generate a Mermaid diagram from code |
| [/onboard](onboard.md) | Walk a new team member through the eight-phase workflow |

## Adding new commands

Use the frontmatter template:

```yaml
---
description: One-line summary — also shown in the / menu.
argument-hint: "[arg-name]"
allowed-tools: Read, Glob, Grep, Bash
disable-model-invocation: true   # leave as true unless you want auto-triggering
---

# /<command> — Title

Body of the command — instructions for the agent.

Use ``!`command` `` for bash injection (runs before Claude sees the prompt).
Use `@path/to/file` to inline a file.
Use `$ARGUMENTS` to reference user-supplied args.
```

See [Claude Code skills docs](https://code.claude.com/docs/en/skills) for the full frontmatter reference.

## When to create a skill vs a command

| Decision | Pick |
|---|---|
| Should Claude auto-invoke this when a condition is met? | Skill (`.claude/skills/`) |
| Is this a user-facing utility that should only run on demand? | Command (`.claude/commands/`) |
| Is this part of the eight-phase workflow? | Skill |
| Is this a project-management or diagnostic helper? | Command |
| Should this match a Spec Kit equivalent? | Skill |
