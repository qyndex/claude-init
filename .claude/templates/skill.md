---
name: <kebab-case-skill-name>
description: One paragraph — leads with "when to use" / trigger phrases. Stays ≤ 1536 chars. Example "Use when... User says... Auto-triggers on..." patterns work best.
when_to_use: Additional trigger phrases the model uses to decide invocation. Concrete user prompts and phrases work better than abstract descriptions.
argument-hint: "[arg-name]"
allowed-tools: Read, Glob, Grep
disable-model-invocation: false       # true = user-only (no auto-trigger)
user-invocable: true                    # false = hidden from / menu (Claude-only)
model: inherit                          # opus | sonnet | haiku | inherit
paths:                                  # optional — auto-load only on matching files
  - "src/**/*"
context: fork                           # optional — runs in forked subagent (with `agent:` below)
agent: <name>                           # required if context: fork
mcpServers: [chrome-devtools]           # optional — pre-attached MCP servers
---

# <Skill Title>

> One-sentence summary of what this skill does. Keep it crisp.

## When to use

- Specific user phrase 1
- Specific user phrase 2
- Concrete scenario 1

## When NOT to use

- Scenario where another skill is better
- Scenario where this is overkill

## Process

```
1. Read inputs from <where>
2. Do <thing>
3. Validate via <how>
4. Output to <where>
5. Hand off to <next step>
```

## Hard rules

- **Rule 1** — why it matters
- **Rule 2** — why it matters
- **Rule 3** — why it matters

## Auto-clarity escape hatch (per caveman pattern)

If the skill modifies tone or behavior, declare when it must DISABLE itself:
- Security warnings
- Irreversible action confirmations
- Multi-step sequences where fragment order matters
- Ambiguity needing clarification

## Output

```
<path-or-artifact-this-produces>
```

After save: "<one-line summary of what was done>."

## References

- Source / inspiration: <github URL>
- Related skills: `.claude/skills/<other>/SKILL.md`
- Anthropic skills spec: https://code.claude.com/docs/en/skills
