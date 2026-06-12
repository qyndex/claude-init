---
name: dream
description: Memory consolidation. Dedupe and compress .claude/memory/ topic files, absolutize relative dates, archive stale instincts and processed checkpoints, and hard-enforce the 200-line MEMORY.md cap. Produces a reviewable proposal, never a silent overwrite.
when_to_use: User says "dream", "consolidate memory", "tidy memory". The Stop hook (auto-dream-check.sh) fires this when >24h since the last dream AND ≥5 sessions have accumulated. dream-cron.yml is the 03:00 backstop.
model: sonnet
---

# Dream — memory consolidation

Long autonomous runs accrete memory: duplicate observations, relative dates that
rot ("yesterday"), instinct files that no longer fire, checkpoints already
folded in. Left alone, `MEMORY.md` bloats past the context budget and the signal
drowns. Dreaming is the periodic GC that keeps memory dense and current.

## Trigger contract (with auto-dream-check.sh)

The Stop hook `.claude/hooks/auto-dream-check.sh` decides _when_; this skill is
_what_ runs. The hook fires a dream only when **both**:

- more than 24h have passed since the last dream, AND
- at least 5 sessions have accumulated since then.

State lives in `.claude/memory/.cache/.dream-state.json`; a lock at
`.claude/memory/.cache/.dream.lock` prevents concurrent dreams. **If an
un-reviewed proposal already exists in `.claude/memory.proposed/`, do nothing** —
the operator must clear it via `/dream-review` first, or a second dream would
silently overwrite the first's proposal and drop the human-review gate.

## What a dream does

1. **Gather** — read `.claude/memory/` topic files and every checkpoint under
   `.claude/memory/.cache/checkpoints/` written since the last dream.
2. **Dedupe + compress** — merge repeated observations into a single entry; drop
   anything already captured in a topic file. Prefer the denser phrasing.
3. **Absolutize dates** — rewrite relative dates ("yesterday", "last week") to
   absolute ISO dates, so the memory stays interpretable after time passes.
4. **Archive stale instincts** — move instinct files that haven't fired recently
   from the active set into `.claude/memory/.cache/archive/YYYY-MM/`.
5. **Detect contradictions** — group ADR files under `.claude/memory/decisions/`
   by their `subsystem:` frontmatter field. For each subsystem group with ≥2 ADRs,
   compare their `decision:` fields; flag any pair whose decisions conflict (e.g.,
   "use postgres" vs "use sqlite"). Write flagged pairs to
   `.claude/memory.proposed/conflicts.md` (one table row per conflict: subsystem,
   ADR-A path, ADR-B path, conflict summary). If no conflicts found, omit the
   file. Do not auto-resolve — surface for human review.
6. **Enforce the cap** — run `bash .claude/scripts/memory-gc.sh enforce` to hold
   `MEMORY.md` at ≤200 lines. This is the hard backstop: the cap is enforced by
   the script, not by this prompt, so a crashed/hallucinating dream cannot leave
   `MEMORY.md` bloated (Round 4 caught exactly that silent failure).
7. **Archive checkpoints** — move processed checkpoints to
   `.claude/memory/.cache/archive/YYYY-MM/`.
8. **Roll up horizons** — run `bash .claude/scripts/memory-rollup.sh auto`.
   This consolidates the week's events into `.claude/memory/rollups/YYYY-Www.md`
   and, at period boundaries, weeklies → monthly → quarterly (each ≤100 lines).
   Multi-year recall depends on this: day-scale memory (in-flight briefs,
   observations) ages out within days, but the rollup chain preserves it at
   log-scale cost. The factual skeleton is deterministic (git + task ledger);
   you may enrich the narrative sections of the current week's file, but never
   alter past-period rollups.

## Output

Write the consolidated result as a **proposal** under `.claude/memory.proposed/`,
not directly over `.claude/memory/`. The operator reviews and applies it via
`/dream-review`. Never overwrite live memory in place — the review gate is the
whole point.

## Done means

- A proposal exists under `.claude/memory.proposed/` (or the dream no-op'd because
  one was already pending).
- `memory-gc.sh enforce` has run and `MEMORY.md` is ≤200 lines.
- Relative dates in the proposal are absolutized; processed checkpoints archived.
- `.claude/memory.proposed/conflicts.md` written if any contradicting ADRs found
  (subsystem-grouped comparison); absent means no conflicts detected.
- `memory-rollup.sh auto` has run — the current week's rollup exists under
  `.claude/memory/rollups/`.

## References

- Trigger: `.claude/hooks/auto-dream-check.sh`
- Cap enforcement: `.claude/scripts/memory-gc.sh`
- Backstop schedule: `.claude/routines/dream-cron.yml`
- Review gate: `/dream-review`
