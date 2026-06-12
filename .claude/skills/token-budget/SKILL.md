---
name: token-budget
description: Per-session token discipline — cache, delegate, compact. Use when output is getting verbose, context is filling, or cache hit-rate drops. Companion to context-budget (which inventories the harness); this governs in-session behavior.
when_to_use: Long session underway. Output verbosity creeping. context-monitor injected a [context] or [output] warning. Cache hit-rate below 40%.
model: sonnet
allowed-tools: Read, Glob, Grep, Bash
---

# Token Budget

In-session token discipline. `context-budget` audits what the harness *loads*;
this skill governs what the session *spends*. (Gap-audit G8: previously
referenced from CLAUDE.md, README, ARCHITECTURE, RESEARCH §9, and
prime-discipline but never shipped.)

## Output rules (the model's own tokens)

- **Cite paths, don't paste files.** `src/foo.ts:42`, never the contents.
- **No preamble, no postamble.** No "I'll now read…", no "Let me know if…".
- **State results, don't narrate.** One sentence per milestone, not per tool call.
- **Don't echo back what the user (or a hook) just said.**
- If the `context-monitor` hook injects an `[output]` warning, the previous
  turn exceeded the growth nudge — tighten immediately.

## Input rules (what enters context)

- **Subagents for heavy reads** (>3 files or >20K tokens) — their context dies
  with them; only the conclusion returns. Use `Explore` (Haiku).
- **Graphify MCP over grep** for cross-module questions (>3 files).
- **memory-recall.sh before grepping `.claude/memory/`** — index-backed, ≤5 lines.
- **Read `initiatives/active/<id>.STATE.md`** (≤60 lines) instead of re-deriving
  initiative state from specs/plans/tasks.

## Cache rules

- **Don't rewrite prefix surfaces mid-session**: CLAUDE.md, agents/*, skill
  frontmatter, settings. They invalidate the prompt cache for every later turn.
- **TTL is ~5 minutes** and not configurable from Claude Code: turns spaced
  >5min apart re-pay the cache write. Keep unattended loops tight.
- **Measure, don't guess**: `bash .claude/scripts/cost-report.sh day` →
  `cache_hit_rate` in cost-summary.json; statusline shows `cache:N%`;
  harness-doctor warns under `CACHE_HIT_MIN` (default 40%).

## Compact rules

- Same task continuing → `/compact "<focus hint>"` at a clean boundary.
- New task → `/clear`.
- The `context-monitor` hook nudges at 60% and 80% estimated fill; at 80%,
  persist in-flight state (WIP commit, tasks/notes) *before* compaction.

## References

- docs/RESEARCH.md §9 (sources: Anthropic context-engineering + long-running-agents posts)
- .claude/skills/context-budget/SKILL.md (harness-load inventory)
- .claude/skills/prime-discipline/SKILL.md (session-start digest of these rules)
