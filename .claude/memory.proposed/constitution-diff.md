# Constitution amendment proposal — memory-system read path (2026-06-12)

**Source:** docs/research/memory-system-review.md §7.3 (wire the read path) and §7.2
(initiative living state). The constitution is operator-protected; apply by hand or
via `/constitution` after review.

**Current size:** 206/300 — both amendments fit within the cap (+3 lines net).

## Diff 1 — §IV `<delegation_rules>`: add the memory-recall row

Insert into the delegation table after the Graphify row:

```markdown
| "Have we seen this before?" (patterns/ADRs/incidents for files being touched) | `bash .claude/scripts/memory-recall.sh --paths "<files>"` — index-backed, ≤5 lines; use BEFORE grepping .claude/memory/ |
```

**Why:** `memory-index.sh query` had zero callers — agents grepped memory blind or
not at all. This makes the index the documented first stop.

## Diff 2 — §IX Token & Context Discipline: add the initiative-state bullet

Insert after the "Subagents preserve parent context." bullet:

```markdown
- **`initiatives/active/<id>.STATE.md` is the always-current initiative answer.** Machine-rewritten at network boundaries by `initiative-state.sh sync`; read it (≤60 lines) instead of re-deriving state from specs/plans/tasks.
```

**Why:** the initiative layer is now live (review §7.2); without a constitution
pointer, agents will keep re-deriving state at ~10× the token cost.

---
*After applying: delete this file (the proposal is consumed) and bump the
constitution's amendment log if one exists.*
