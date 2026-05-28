# Architecture

How the pieces of this harness fit together.

## Layers

```
┌─────────────────────────────────────────────────────────────┐
│ User                                                         │
│   ↓ (types /specify, /plan, /implement, etc.)                │
├─────────────────────────────────────────────────────────────┤
│ Constitution Layer                                           │
│   .claude/CLAUDE.md  (auto-loaded; the rules)                │
├─────────────────────────────────────────────────────────────┤
│ Configuration Layer                                          │
│   .claude/settings.json   permissions, hooks, env            │
│   .mcp.json               MCP servers                        │
├─────────────────────────────────────────────────────────────┤
│ Workflow Layer (slash commands)                              │
│   .claude/skills/{constitute,specify,clarify,plan,tasks,     │
│                  analyze,implement,verify,review,ship,loop,  │
│                  debug,research}                             │
├─────────────────────────────────────────────────────────────┤
│ Agent Layer (specialized expertise)                          │
│   .claude/agents/{core,quality,specialists}/*.md             │
├─────────────────────────────────────────────────────────────┤
│ Discipline Layer (skills auto-triggered)                     │
│   tdd-loop, verification, browser-e2e, security-guard,       │
│   token-budget, auto-loop, research-grounding, spec-driven   │
├─────────────────────────────────────────────────────────────┤
│ Memory Layer                                                 │
│   .claude/memory/{MEMORY.md, decisions/, patterns/,          │
│                   incidents/, playbooks/}                    │
├─────────────────────────────────────────────────────────────┤
│ Artifact Layer (the spec-driven lifecycle)                   │
│   specs/active/   plans/active/   tasks/TASKS.md             │
│   verify/         docs/research/                             │
├─────────────────────────────────────────────────────────────┤
│ Hook Layer (deterministic guardrails)                        │
│   .claude/hooks/{pre-bash-guard, pre-write-secret-scan,      │
│                  post-write-format, user-prompt-context,     │
│                  session-start, stop-verify, ...}            │
├─────────────────────────────────────────────────────────────┤
│ CI Layer (ship pipeline)                                     │
│   .github/workflows/{claude, claude-review, claude-security, │
│                     ci, e2e-preview, auto-merge-dependabot,  │
│                     release-please, harness-validate}        │
└─────────────────────────────────────────────────────────────┘
```

## The eight-phase workflow

```
   ╔══════════════════════════════════════════════════╗
   ║  Constitution  (one-time, /constitution)         ║
   ╚══════════════════════════════════════════════════╝
                       ↓
   ╔══════════════════════════════════════════════════╗
   ║  Specify       (/specify) → specs/active/<id>.md ║
   ╚══════════════════════════════════════════════════╝
                       ↓
   ╔══════════════════════════════════════════════════╗
   ║  Clarify       (/clarify) — resolve [OQ] items   ║
   ╚══════════════════════════════════════════════════╝
                       ↓
   ╔══════════════════════════════════════════════════╗
   ║  Plan          (/plan) → plans/active/<id>.md    ║
   ╚══════════════════════════════════════════════════╝
                       ↓
   ╔══════════════════════════════════════════════════╗
   ║  Tasks         (/tasks) → tasks/TASKS.md entries ║
   ╚══════════════════════════════════════════════════╝
                       ↓
   ╔══════════════════════════════════════════════════╗
   ║  Analyze       (/analyze) — consistency gate     ║
   ╚══════════════════════════════════════════════════╝
                       ↓
   ╔══════════════════════════════════════════════════╗
   ║  Implement     (/implement) → code + tests       ║
   ║                strict TDD per task               ║
   ╚══════════════════════════════════════════════════╝
                       ↓
   ╔══════════════════════════════════════════════════╗
   ║  Verify        (/verify) → verify/<date>/REPORT  ║
   ╚══════════════════════════════════════════════════╝
                       ↓
   ╔══════════════════════════════════════════════════╗
   ║  Review        (/review) — code + security       ║
   ╚══════════════════════════════════════════════════╝
                       ↓
   ╔══════════════════════════════════════════════════╗
   ║  Ship          (/ship) — PR, CI, merge, deploy   ║
   ╚══════════════════════════════════════════════════╝
```

## Agent team

| Agent | Tier | Model | Tools | Mandate |
|---|---|---|---|---|
| **architect** | core | opus | Read, Glob, Grep, WebFetch, WebSearch, TodoWrite | specs + plans (read-only) |
| **planner** | core | sonnet | Read, Edit (TASKS only), TodoWrite | decompose plans into atomic tasks |
| **implementer** | core | opus | Read, Edit, Write, Bash, TodoWrite | TDD per task → commit |
| **tester** | quality | sonnet | Read, Edit, Write, Bash | expand coverage, mutation testing |
| **reviewer** | quality | opus | Read, Glob, Grep, Bash | multi-pass code review (read-only) |
| **security** | quality | opus | Read, Glob, Grep, Bash, WebFetch | OWASP + LLM Top 10 audit (read-only) |
| **verifier** | quality | sonnet | Read, Bash, WebFetch + browser MCP | run app, exercise journey, capture evidence |
| **debugger** | specialist | opus | Read, Glob, Grep, Bash, WebSearch | systematic 4-phase debugging |
| **researcher** | specialist | sonnet | Read, WebSearch, WebFetch, Write | cite evidence, comparison briefs |
| **doc-writer** | specialist | sonnet | Read, Edit, Write, Bash | keep docs honest |
| **release** | specialist | sonnet | Read, Bash, TodoWrite | push, PR, CI watch, merge, tag, deploy |
| **coordinator** | core | opus | Read, Glob, Grep, Edit, Write, Bash, TodoWrite | orchestrates swarm fleet — plans, dispatches, monitors, merges |
| **feature-stream** | core | opus | Read, Glob, Grep, Edit, Write, Bash, TodoWrite | runs inside each `claude --bg -w feat-<N>` session, executes allocated tasks via TDD |

**Tiered model assignment** (from `wshobson/agents`):
- Opus for hard-thinking: architecture, security, debugging, code review
- Sonnet for everyday work: planning, verifying, testing, releasing, doc-writing
- Haiku for retrieval (via `Explore` subagent): grep, file searches, summaries

## Skill resolution

When the user types `/<name>` or Claude considers triggering a skill:

1. Project skills (`.claude/skills/<name>/SKILL.md`) — highest precedence
2. User skills (`~/.claude/skills/<name>/SKILL.md`)
3. Plugin skills (namespaced as `/<plugin>:<name>`)
4. Built-in skills (provided by Claude Code)
5. Legacy commands (`.claude/commands/<name>.md`) — same frontmatter, lower precedence

Each skill's frontmatter `description` is loaded into context at startup (~100 tokens per skill). The body loads on invocation.

## Memory resolution

Per Claude Code memory docs, files are loaded in order (broad → specific) and **concatenated**:

1. Managed CLAUDE.md (enterprise; usually empty)
2. `~/.claude/CLAUDE.md` (user-global)
3. Ancestor `CLAUDE.md`/`CLAUDE.local.md` (walk up to filesystem root)
4. `<cwd>/CLAUDE.md` or `<cwd>/.claude/CLAUDE.md`
5. `<cwd>/CLAUDE.local.md`

Subdirectory `CLAUDE.md` files load **on demand** when Claude reads files in that directory. Use `.claude/rules/` for path-scoped rules.

This harness puts the constitution at `.claude/CLAUDE.md`. The memory index is at `.claude/memory/MEMORY.md`.

## Hook lifecycle

```
SessionStart      → context boot summary (branch, dirty, active spec/plan, tasks)
  ↓
UserPromptSubmit  → inject branch/dirty/spec/plan into the prompt
  ↓
PreToolUse:Bash   → block destructive bash (rm -rf, force push, drop table)
PreToolUse:Write  → scan content for secrets (gitleaks + regex)
  ↓
PostToolUse:Write → auto-format (prettier / ruff / rustfmt / gofmt)
PostToolUse:Bash  → audit-log every command
  ↓
SubagentStop      → log subagent run (cost tracking)
  ↓
PreCompact:auto   → snapshot context before compaction
  ↓
Stop              → nudge to /verify if prod files changed
  ↓
SessionEnd        → capture usage via ccusage
```

## Token economy

The harness is built to minimize token waste:

- **CLAUDE.md, agents, skills are cacheable** — stable across turns
- **Subagents have fresh context** — heavy reads/searches don't pollute the parent
- **Skills load metadata-only** — description (~100 tokens) at startup, body only when invoked
- **Output style "Concise" is default** — no preamble/postamble, cite paths not file contents
- **Statusline shows context fill** — visible budget pressure
- **PreCompact snapshot** — never lose work to compaction
- **ccusage hook on SessionEnd** — daily cost tracking baked in

## Security posture

Five layers of defense:

1. **Settings deny list** — destructive bash and secret-file reads blocked at the policy level
2. **PreToolUse hooks** — actively scan and block (defense in depth)
3. **Sandbox config** — optional `sandbox: { enabled: true }` for hostile environments
4. **GitHub Rulesets** — required signed commits, required reviews, required checks
5. **Multi-pass security review** — Anthropic's `claude-code-security-review` GitHub Action

## Where to extend

- **New agent** → add `.claude/agents/<tier>/<name>.md` with frontmatter
- **New skill** → add `.claude/skills/<name>/SKILL.md` with frontmatter
- **New hook** → add a script in `.claude/hooks/` + register in `.claude/settings.json`
- **New MCP server** → uncomment in `.mcp.json` or add via `claude mcp add`
- **New CI gate** → add a workflow under `.github/workflows/` + add to ruleset required checks

## References

- Claude Code docs: https://code.claude.com/docs/en/
- Anthropic Skills: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview
- Effective harnesses (Anthropic): https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
- Effective context engineering (Anthropic): https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- See [RESEARCH.md](RESEARCH.md) for the full reference list
