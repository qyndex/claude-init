---
name: <agent-name>                      # kebab-case, matches filename
description: Lead with "Use proactively when..." or specific trigger phrases. ≤ 1536 chars. Concrete delegation cues work better than abstract descriptions.
tools: Read, Glob, Grep                 # omit for inherit-all
disallowedTools: []                     # subtractive denylist (optional)
model: sonnet                            # opus | sonnet | haiku | inherit
permissionMode: acceptEdits              # plan | acceptEdits | auto | bypassPermissions
maxTurns: 30
effort: high                             # low | medium | high — valid on subagents
skills: []                               # pre-load skill content (array of names)
mcpServers: []                           # pre-attach MCP servers
isolation: worktree                      # optional — temporary git worktree
color: cyan                              # cosmetic
---

# <Agent Title>

> One-sentence mandate. What this agent does and when to use it.

## Mandate

1. <Primary responsibility>
2. <Secondary responsibility>
3. <Boundary — what this agent does NOT do>

## Hard rules

- **Never <X>.** Why: <reason>.
- **Always <Y>.** Why: <reason>.
- **Cite evidence.** Every non-obvious claim references a file:line, doc URL, or test result.
- **One concern per invocation.** If the work expands beyond the mandate, stop and hand back.
- **Permission mode is <mode>.** That means <implication>.

## Workflow

```
1. Read <inputs>
2. <Action 1>
3. <Action 2>
4. <Validate via X>
5. <Output to Y>
6. <Hand off to Z>
```

## Per-stage details

### Stage 1 — <name>
What happens, what gets written, what gets validated.

### Stage 2 — <name>
...

## Done means

- <Specific observable artifact 1 exists>
- <Specific observable artifact 2 exists>
- <Test/check N passes>
- <Note added to memory if reusable>

## Output format

```
<example output structure>
```

## References

- Inspiration: <github URL>
- Sub-agents docs: https://code.claude.com/docs/en/sub-agents
