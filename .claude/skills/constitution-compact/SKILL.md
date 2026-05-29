---
name: constitution-compact
description: Quarterly constitution compaction. Identifies redundant, stale, or over-verbose sections in .claude/CLAUDE.md, proposes a trimmed version under .claude/memory.proposed/constitution-diff.md, and enforces the ≤300-line cap. Never edits the constitution in-place — human applies the diff.
when_to_use: User says "compact constitution", "trim CLAUDE.md", or the quarterly cron fires. Also when validate.sh reports constitution >300 lines.
model: sonnet
---

# Constitution Compact

The constitution (`.claude/CLAUDE.md`) accumulates cruft over time: duplicated
rules, superseded round notes, verbose examples that were useful once. Beyond 300
lines, prompt-cache efficiency drops and agents start missing rules buried in the
middle. This skill compacts it.

## The 300-line cap

Every section added to the constitution displaces something else. The cap is not
arbitrary: with CLAUDE_CODE_AUTO_COMPACT_WINDOW=400K, a 300-line constitution
stays in the ~2K token range and keeps the cache warm across turns.

`validate.sh` checks `[constitution-size]` and warns at >250 lines, fails at >300.

## What compact does

1. **Read** `.claude/CLAUDE.md` in full.
2. **Identify** candidates for trimming:
   - Numbered "Round N" annotations that are now the settled default (the round
     label is no longer informative — the behavior is just how it works).
   - Rules that duplicate a hook or script (if `pre-bash-guard.sh` blocks
     `rm -rf`, the constitution doesn't need to list it too).
   - Verbose examples with multi-line code blocks where a one-line reference to
     the relevant script/skill is sufficient.
   - Sections superseded by newer rounds (if Round 5 changed something from
     Round 3, the Round 3 text can go).
3. **Propose** a compacted version in `.claude/memory.proposed/constitution-diff.md`:
   - Show the **diff** (removed lines prefixed `−`, kept lines as-is).
   - Add a brief rationale per removed section (why it's safe to drop).
   - Show the new line count target.
4. **Never write** to `.claude/CLAUDE.md` directly. The operator reviews the
   proposal via `/dream-review` and applies it with `FORCE_CONSTITUTION_EDIT=1`.

## Done means

- `.claude/memory.proposed/constitution-diff.md` exists with a `−`/`+` diff
  and a projected line count ≤ 300.
- `validate.sh [constitution-size]` will pass after the diff is applied.
- No section that is still load-bearing (active enforcement, security invariant,
  or unimplemented intent) has been removed.

## Archive, don't delete

Removed sections go to `.claude/memory/decisions/archive/constitution-removed-<date>.md`
so the reasoning is preserved if a rule needs to be reinstated.

## References

- Cap enforcement: `.claude/scripts/validate.sh` `[constitution-size]` check
- Quarterly trigger: `.claude/routines/constitution-compact-cron.yml`
- Review gate: `/dream-review`
