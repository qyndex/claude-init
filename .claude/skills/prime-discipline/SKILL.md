---
name: prime-discipline
description: Reference card of discipline patterns from across the research — Boris Cherny's CLAUDE.md / compaction / rewind rules, Karpathy's surgical-changes rule, Lovable's good/bad example format, Cursor's semantic-search-first, Devin's plan↔execute toggle. Single source of habits. Invoke manually via /prime-discipline; the skill-router will also hint it on `prime me`, `load context`, `refresh state`.
when_to_use: Manual invocation by the user via /prime-discipline. The skill-router hint surfaces it on `prime me`, `load context`, `refresh state`. Not auto-loaded — read this once at session start or when stepping into a new module.
model: inherit
---

# Prime Discipline

Habits that compound. From the best-engineered setups in the ecosystem.

## On corrections (Boris Cherny tips #74, #16)

- **Don't say "try X instead."** That keeps the failure in context. Use `/rewind` or double-tap Esc, then issue a fresh prompt.
- **After every correction, update CLAUDE.md** so the agent doesn't repeat the mistake. Pattern: "Note for future sessions: when you see X, do Y not Z. — added <date>"

## On compaction (Boris tips #75, #76)

- **Same task continuation** → `/compact "focus on X, drop test debugging"` (hint-driven)
- **New task** → `/clear`
- **`CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000`** is set in settings.json. Context rot starts at 300-400K on the 1M model.

## On exploration (Cursor pattern)

- **Always semantic-search before grep.** `Glob` for file shapes, then `Read` the candidate, only `Grep` when you have a specific symbol.
- Grep on a 50K-file repo without a path filter is a token sink.

## On planning (Devin pattern)

- **Plan mode → Execute mode toggle.** State the plan in 3-5 bullets. Get explicit user "go" (or implicit in autopilot). Don't interleave planning and execution turn-by-turn.

## On examples (Lovable pattern)

- When defining behavior in a skill or prompt, include BOTH good and bad examples:
  ```
  ✅ "Edited src/auth.ts:42-58 — fixed null-check order."
  ❌ "I've now updated the file. Here's what it contains: <500 lines>"
  ```
- Show the failure mode you're trying to prevent.

## On surgical changes (Karpathy)

- **Every changed line traces to the user's request.**
- "While I was in there I also fixed..." — undo it. Open a new task for that fix.
- Dead code: mention, never delete unilaterally.

## On verification (superpowers)

- "Looks fine" is not verification.
- "Tests pass" alone is not verification of a user-facing change. Boot the app.
- Evidence files in `verify/<date>-<feature>/`: at least one screenshot or HTTP response per acceptance criterion.

## On token discipline (token-budget skill)

- Cite paths, don't paste files.
- No preamble ("I'll now read..."), no postamble ("Let me know if...").
- Subagents for heavy reads. Their context dies with them.

## On autonomy (autopilot skill)

- 3x same error → ABORT, log, move on. No infinite retry.
- WIP commits every 5-15 minutes during long features.
- Hooks > permission prompts in autopilot mode.

## Cross-tool consistency

These same rules apply when running in Claude Code, Codex CLI, Cursor agents, etc. The harness deliberately uses `AGENTS.md`-compatible patterns (`CLAUDE.md @imports AGENTS.md` is a valid setup) so the discipline ports.

## References

- howborisusesclaudecode.com tips #1, #14, #16, #74, #75, #76, #81, #88, #89
- multica-ai/andrej-karpathy-skills/CLAUDE.md (surgical changes)
- x1xhlol/system-prompts-and-models-of-ai-tools (Cursor, Devin, Lovable patterns)
- obra/superpowers (verification + TDD)
