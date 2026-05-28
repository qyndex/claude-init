---
description: Scaffold a new subagent under .claude/agents/<tier>/<name>.md with the canonical frontmatter and "Done means" body. Companion to skill-creator. Use when you need a new domain-specific agent (e.g., db-migrator, ml-trainer, compliance-auditor) that the existing 13 don't cover.
argument-hint: "<name> [--tier core|quality|specialists] [--model opus|sonnet|haiku]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, TodoWrite
disable-model-invocation: true
---

# /create-agent — Scaffold a new subagent

Mirrors `skill-creator` for agents. Produces a spec-compliant `.md` file under `.claude/agents/<tier>/<name>.md` using `.claude/templates/agent.md` as a base.

## Process

1. **Parse arguments.** Required: `<name>` (kebab-case, no spaces). Optional: `--tier` (default `specialists`), `--model` (default `sonnet`).
2. **Check for collisions.** If `.claude/agents/**/<name>.md` already exists, refuse and tell the user to pick a different name or use `/agent-edit`.
3. **Interview the user** (max 4 questions via AskUserQuestion):
   - What's this agent's mandate in one sentence?
   - When should Claude delegate to it? (Trigger phrases — go in `description`)
   - What tools does it need? (`Read, Glob, Grep` for read-only; add `Edit, Write` for writers; add `Bash` for shell)
   - Should it run in plan / acceptEdits / auto / bypassPermissions mode?
4. **Render** `.claude/templates/agent.md` with the answers + project conventions from `.claude/CLAUDE.md`.
5. **Validate** via `bash .claude/scripts/validate.sh` — confirm the new agent passes frontmatter checks.
6. **Surface** the file path + a sample dispatch command + suggested next step (write a test invocation, add to ARCHITECTURE.md table).

## Frontmatter the new agent gets

```yaml
---
name: <agent-name>                  # kebab-case, matches filename
description: <when-to-delegate phrase, ≤1536 chars, leads with "Use proactively when...">
tools: <comma-separated list>       # omit for inherit-all
model: <opus|sonnet|haiku|inherit>
permissionMode: <plan|acceptEdits|auto|bypassPermissions>
maxTurns: <N>
effort: <low|medium|high>           # valid on subagents only
color: <hex or named color>         # cosmetic
isolation: worktree                 # optional — spawn in temporary worktree
---
```

## Body sections the template includes

1. **Mandate** (3-5 bullets — what this agent does)
2. **Hard rules** (5-8 bullets — what it must never do)
3. **Workflow** (numbered steps — the canonical flow)
4. **Done means** (definition of done — required)

## Output

```
.claude/agents/<tier>/<name>.md
```

After save: "Agent `<name>` scaffolded at `.claude/agents/<tier>/<name>.md`. Test with: `claude --agents '...'` or invoke from a workflow skill. Validation: passed/failed."

## Hard rules

- **Don't duplicate existing agents.** If `<name>` is too close to an existing one (planner, architect, etc.), refuse and suggest extending instead.
- **Don't give an agent more tools than its mandate requires.** Default to read-only unless the mandate is clearly to write.
- **Permission mode must match the agent's blast radius.** A read-only researcher → `plan`. An implementer → `acceptEdits`. A scheduled stream → `auto`. Never `bypassPermissions` at the agent level.

## References

- Claude Code sub-agents spec: https://code.claude.com/docs/en/sub-agents
- skill-creator (sibling command): `/plugin install skill-creator@claude-plugins-official`
- Existing agent examples: `.claude/agents/**/*.md`
