---
name: context-budget
description: Inventory and recommend prunes for loaded agents, skills, MCP servers, and rules. Reports always-needed / sometimes-needed / rarely-needed buckets with token costs. From affaan-m/ECC context-budget.
when_to_use: Context >60% full. Cache hit rate dropping. User says "/context-budget", "what's costing tokens", "trim the harness".
model: sonnet
allowed-tools: Read, Glob, Grep, Bash
---

# Context Budget

Most agents accumulate skills/agents/rules cruft over time. This skill audits the current load and recommends prunes.

## What it scans

| Source | Path | Cost source |
|---|---|---|
| Agents | `.claude/agents/**/*.md` | Frontmatter loaded at startup; body loaded on dispatch |
| Skills | `.claude/skills/*/SKILL.md` | Frontmatter loaded; body on trigger |
| Rules | `.claude/rules/*.md` (if any) | Loaded by path-glob match |
| MCP servers | `.mcp.json` | Tool schemas; deferred unless `alwaysLoad: true` |
| Memory | `.claude/memory/MEMORY.md` + topic files | First 200 lines auto-loaded |
| Output styles | `.claude/output-styles/*.md` | Active one loaded into system prompt |

## What it computes

For each item:
- Token count (approximate via `wc -c / 4`)
- Loaded? (yes/no based on `alwaysLoad` / matched paths / active status)
- Last invoked (from `.claude/hooks/.log/`)
- Recommendation: keep / defer / archive

## Report format

```
# Context Budget Report — <date>

## Always-loaded (cost: <N> tokens)
- .claude/CLAUDE.md                       ████ 1840 tok    keep
- .mcp.json: filesystem (alwaysLoad)      ██ 920 tok        keep
- .mcp.json: git (alwaysLoad)             ██ 880 tok        keep
- .mcp.json: github (alwaysLoad)          ███ 1320 tok      keep

## Sometimes-loaded (cost on trigger: <N> tokens average)
- skills/autopilot                        body 4200 tok    invoked 12x this week    keep
- skills/self-heal                        body 1800 tok    invoked 4x                keep
- skills/research                         body 1200 tok    invoked 1x                consider deferring (low usage)

## Never invoked (cost: 0 active, <N> at startup for frontmatter)
- skills/onboard                          frontmatter only   not invoked in 30d        consider archiving
- agents/specialists/doc-writer           frontmatter only   not invoked in 14d        keep (low cost)

## MCP tool schemas (with Tool Search)
- chrome-devtools (deferred)               0 tok at start, ~3000 on first use
- playwright (deferred)                    0 tok at start
- apify (deferred)                         0 tok at start, ~8000 on first search
...

## Total
Startup cost: ~12,400 tokens (CLAUDE.md + agents + skill frontmatter + alwaysLoad MCPs)
Typical session: ~28,000 tokens (after a few skills triggered)
Budget headroom on 1M context: ~972,000 tokens
Recommendation: ✓ healthy
```

## Recommendations

- **Defer** (`alwaysLoad: false` on MCPs, or skill stays in dir but description trimmed)
- **Archive** (move to `.claude/skills/.archive/` — not loaded by Claude Code)
- **Trim** (rewrite a verbose skill body to <500 lines)
- **Consolidate** (two similar skills → one)

## Manual usage

```
/context-budget          # generate the report to stdout
/context-budget --archive-stale     # auto-archive items not used in 60d
/context-budget --by-cost           # sort by token cost descending
```

## Hard rules

- **Don't archive without invocation log.** Use `.claude/hooks/.log/skill.log` (when skill-router records triggers) as ground truth.
- **Never auto-archive agents.** Always confirm with the user.
- **Stale ≠ useless.** Some agents (release, security) are rarely-but-critically used.

## References

- affaan-m/ECC/skills/context-budget (source)
- Anthropic's progressive disclosure pattern (frontmatter cheap, body lazy)
- Claude Code Tool Search (deferred schemas)
