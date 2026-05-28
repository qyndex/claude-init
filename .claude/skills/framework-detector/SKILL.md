---
name: framework-detector
description: Maps a detected stack (from `detect-stack` / atlas) to the framework-specific SKILL.md that should be activated for this session. Invoke once at session start, or whenever a new spec mentions a stack that isn't already loaded. Reads `.claude/memory/atlas/STACK.md` and emits a list of skills to consult.
when_to_use: When session starts and atlas/manifest.json has detected frameworks; maps detected stack to recommended skills.
disable-model-invocation: true
---

# Framework detector

A routing skill. It does no work itself — it reads the atlas and tells you which framework-specific skill(s) to load.

## Inputs
- `.claude/memory/atlas/STACK.md` — produced by `detect-stack` (`bash .claude/scripts/atlas-refresh.sh`)
- Optional override: spec frontmatter `stack:` field

## Routing table

| Detected `frameworks.web` | Detected `frameworks.api` | Skill to activate |
|---|---|---|
| Vite-React | (none) | `.claude/skills/react-vite/SKILL.md` |
| Vite-React | Express \| Fastify \| Hono \| NestJS | `react-vite` + `react-node` |
| Next.js (App or Pages) | Express \| Fastify \| Hono \| (same Next.js) | `react-node` (+ proposed `nextjs` when seeded) |
| Remix | any Node | `react-node` (+ proposed `remix` when seeded) |
| (any React) | tRPC | `react-node` |
| (none) | Flask | `flask-realtime` if SocketIO present, else proposed `flask-rest` |
| (none) | FastAPI | proposed `fastapi` |
| (none) | Django | proposed `django` |
| (none) | Rails | proposed `rails` |
| (none) | Gin / Fiber / Echo | proposed `go-web` |
| (none) | Axum / Actix / Rocket | proposed `rust-web` |

## How to use

1. **Read the atlas:**
   ```bash
   cat .claude/memory/atlas/STACK.md
   ```
2. **Look up the row** in the routing table.
3. **Reference the skill file by path** in your reasoning — Claude Code's progressive disclosure loads it on demand. Do NOT inline the skill body.
4. **If the row says "proposed":** that skill isn't seeded yet. File a `mcp__ccd_session__spawn_task` to draft it, then proceed with general principles from the relevant `.claude/rules/{frontend,backend}.md`.

## Update to `detect-stack`

When `detect-stack` produces its manifest, it now also writes the *recommended skill list* to `.claude/memory/atlas/SKILL_HINTS.md`:

```markdown
# Recommended framework skills (auto-generated)
- React + Vite detected → load `.claude/skills/react-vite/SKILL.md`
- Flask + SocketIO detected → load `.claude/skills/flask-realtime/SKILL.md`
```

This file is short (10–20 lines), cheap to keep in context, and gives the architect/implementer agents an unambiguous "load this" signal on every session.

## When NOT to invoke
- Single-file scripts, throwaway repos, no `package.json` / `pyproject.toml` — atlas is empty, no routing to do.
- The user explicitly says "ignore the stack, just edit this file".
