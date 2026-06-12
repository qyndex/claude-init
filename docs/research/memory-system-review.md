# Memory System Review — Expert Panel Assessment

> **Date:** 2026-06-12 · **Scope:** the full memory stack of the claude-init harness, assessed against the goal: *a memory system for any initiative that always knows the current state of the system across sessions, over multi-year horizons, with agents reading context-optimized memory reflecting the latest state.*
>
> Format: five-expert panel. Each expert reviewed the same evidence (file tree census, mechanics trace, state-flow trace — all cites verified on disk 2026-06-12).

---

## 0. The memory taxonomy as implemented today

| Cognitive layer | Harness implementation | Write path | Read path |
|---|---|---|---|
| **Working memory** (this turn) | Session context + per-turn injections (`workflow-state.sh`, `user-prompt-context.sh`) | UserPromptSubmit hooks, every turn | Injected automatically (~60 tokens/turn) |
| **Short-term / session bridge** | `in-flight.md` (session-end snapshot, 200-line cap, 7-day TTL), `session-recent.json`, killed-session sentinel (`current-session.json`), compaction witness briefs (`.cache/checkpoints/`) | `session-end.sh`, `pre-compact-witness.sh` | `session-start-context.sh` injects pointers + ages (~150-400 tokens) |
| **Episodic** (what happened) | `incidents/`, `audits/`, `dora/`, `decisions.log`, `usage.jsonl`, `verify/` evidence bundles, `observations.jsonl` (1,797 raw tool events) | Hooks + scripts at event time | **Mostly none** — grep/Read on demand; observations only read by instinct extraction |
| **Semantic** (what we know) | `MEMORY.md` (200-line capped index), `patterns/` (9), `playbooks/` (7), `decisions/` (0 real ADRs), `atlas/` (codebase map), `deprecations/` | Manual writes + `/dream` proposals via `memory.proposed/` | `MEMORY.md` auto-loaded; rest by Read/grep; `index.jsonl` queryable but **never queried by anything** |
| **Procedural** (how we act) | Skills, instincts (`observations → active.yml → skill candidates`), playbooks | `instinct-observer.sh`, `task-signature-detector.sh`, `/dream-review --approve-skill` | Skill descriptions at session start; instincts only as a count + "read the file" hint |
| **Consolidation** ("sleep") | `/dream` (>24h + ≥5 sessions, proposal-not-mutation), `memory-promote.sh` (emerging→established→quarantined lifecycle), `memory-gc.sh` (caps + archive) | Stop hook + 03:00 cron | Output lands in `memory.proposed/` for human review |

---

## 1. Dr. A — Cognitive architecture researcher

"The taxonomy is genuinely complete on paper — I rarely see working/episodic/semantic/procedural all represented, plus a sleep-consolidation cycle. The proposal-not-mutation dream flow and the confidence-decayed instincts are textbook complementary-learning-systems design.

But look at the *density*: `decisions/` has **zero real ADRs**, `anti-patterns/`, `feedback/`, `post-mortems/` are empty templates, and `index.jsonl` has 9 entries whose `status`, `created`, and `last_verified` fields are all blank. The semantic layer is a beautifully engineered library with almost no books. Worse, the promotion rules (`memory-promote.sh`: emerging→established needs ≥3 `verified_in_commits`) can never fire because nothing populates those fields. **The lifecycle machinery exists; the metabolism doesn't.** For a multi-year project this is the difference between a memory system and a memory-shaped folder structure."

## 2. Eng. B — Distributed-systems / state engineer

"Authority is well-defined: `tasks/TASKS.md` sole source for task state, specs/plans/roadmap each authoritative for their layer, GitHub Issues write-only projections. That's the right shape for multi-year consistency — one ledger, projections everywhere else.

But I traced the chain and found it broken at the layer the end-goal cares most about — **the initiative**:

- `initiatives/active/` contains only `.gitkeep`; `roadmap.md` references initiative files that don't exist.
- `.claude/state/current-initiative` and `current-spec` are read by `session-end.sh:23-24` for token attribution but **no code ever writes them** — attribution silently fails.
- And the live bug everyone watched this session: `workflow-state.sh:38` does `grep -m1 '^- \[ \]' tasks/TASKS.md` and matched the **format-template line** (line ~7: `T-NNN | spec:NNN | phase:N | priority: <P>...`) because all real tasks are `[x]`. The harness then displayed a placeholder as 'Next task' for **31 consecutive turns** (`workflow-state.json: streak:31, warned_at:3`). The loop detector correctly fired at turn 3, then correctly went silent — the *detector* works; the *state derivation* it monitors is grep-fragile.

The lesson: state is derived by regex over human-formatted markdown at read time, with no schema validation at write time. Over years, every format drift becomes a silent state corruption."

## 3. Eng. C — Context & retrieval engineer

"The **write side is excellent and the read side is the missing half.** Writes are mechanized at every lifecycle point: PostToolUse observations (~100 bytes, PII-safe), session-end briefs (hard 200-line cap), index `touch` on every memory write, dream consolidation under a 200-line MEMORY.md cap. Token discipline is real: session-start injection is ~150-800 tokens of *pointers with ages*, not content dumps — that's the correct pattern.

Reads, though:

1. `index.jsonl` supports `query --type --status --paths` (`memory-index.sh:72-125`) — **and nothing in the harness ever calls it.** No hook, no skill, no delegation rule.
2. There is no content-based retrieval at all — no embeddings, no BM25, not even a wired-up grep convention. Recall depends on the agent already knowing which file to Read.
3. `paths_touched` in the index is the killer feature nobody uses: when an agent edits `src/api/auth/`, the relevant pattern/ADR/incident could be auto-surfaced by path intersection. Today it isn't.
4. Archives (`.archive/`) are write-only graves — evicted MEMORY.md entries and year-old decisions go in, and no retrieval path ever brings them back.

For 'context-optimized memory based on latest state', the architecture should be: small always-loaded index → query-on-demand by path/type/recency → content loaded just-in-time. The harness built piece one and piece three and never connected them with piece two."

## 4. SRE D — Operations & failure modes

"Defensive engineering is above average: hard caps everywhere (MEMORY.md 200 lines, in-flight 200 lines, observations 1 MB rolling), age-gating on every injection (7d in-flight, 7d atlas, 1d witness, 365d ADRs), proposal staging, killed-session detection, and an audit trail for promotions. The GC story (`memory-gc.sh` check/enforce/archive + `gc-verify.sh`) would actually survive years without disk bloat.

What pages me:

- **Silent failures in the memory plane.** Token attribution fails silently (missing pointer files). The witness checkpoints are 13+ days old with `status: pending` — the async witness generation appears to have died and nothing alerted. This session's own boot context flagged 'ATLAS STALE' and 'Last dream: never' — staleness *detection* works, but remediation is a suggestion string nobody is obligated to act on.
- **The 31-turn placeholder loop cost ~1,200 wasted tokens and 28 turns of operator noise** after the one-shot warning was suppressed. Detection without escalation is a smoke alarm with the battery removed.
- Housekeeping drift: `.gitignore` covers a `.claude/memories/` directory that doesn't exist while the real dir is `.claude/memory/` — fossilized config that will confuse the next maintainer.

This week's incident pattern (stop-hook reasons dropped on stdout for 8 turns — fixed 2026-06-12) and the placeholder loop are the same genus: *the harness knows something is wrong and cannot make anyone care.* Multi-year systems need memory-plane errors to be loud."

## 5. PM E — Long-horizon initiative lead

"Judge it by the end-goal: *'any initiative always knows its current state across sessions for very long-running tasks.'* Today the harness answers 'what was I doing yesterday?' brilliantly (in-flight brief + witness + next-tasks: genuinely best-in-class session continuity) and cannot answer 'where is initiative 042 after eight months?' at all — because the initiative layer is the *only* layer with no living state file, no write path, and no injection.

Also: nothing rolls up. in-flight briefs die at 7 days; observations rotate at 5,000 lines; checkpoints archive after each dream. There's no week→month→quarter summarization hierarchy, so in year two the episodic record of year one is effectively gone except for git history and whatever incidents got promoted. Multi-year recall needs log-scale compression — each horizon summarized into the next — and the dream machinery is *exactly* the right place to build it; it just only operates on one horizon today."

---

## 6. Panel synthesis — gaps ranked against the end-goal

| # | Gap | Severity | Evidence |
|---|---|---|---|
| 1 | Initiative layer is hollow: no living state file, pointers never written, roadmap references ghosts | **Critical** — it's the end-goal's core object | `initiatives/active/` empty; `session-end.sh:23-24`; roadmap.md |
| 2 | Read/retrieval half missing: index never queried, no content-based recall, archives unreachable | **Critical** | `memory-index.sh query` has zero callers |
| 3 | State derived by fragile grep at read time; no write-time schema validation | **High** — caused the live 31-turn loop | `workflow-state.sh:38`, `workflow-state.json streak:31` |
| 4 | Index/frontmatter fields unpopulated → promotion/decay lifecycle can't run | **High** | `index.jsonl`: all `status:"unknown"` |
| 5 | No multi-horizon consolidation (day→week→quarter) → episodic memory evaporates in months | **High** for multi-year | 7d TTLs, 5,000-line rotation, single-horizon dream |
| 6 | Memory-plane failures are silent (attribution, witness death, suppressed loop warnings) | **Medium** | `pending` checkpoints 13d old; missing pointer files |
| 7 | Drift/debris: `.claude/memories/` ignores for a nonexistent dir; empty template categories | **Low** | `.gitignore:36-41` |

## 7. Recommended build plan (toward the end-goal)

1. **Fix the task grep now** (one line, unblocks the live loop): require a real ID — `grep -m1 -E '^- \[ \] T-[0-9]+' tasks/TASKS.md` in `workflow-state.sh:38` (constitution-class: operator applies). Same hardening in `session-start-context.sh` and `subagent-context.sh` task greps.
2. **Give every initiative a living STATE.md** — `initiatives/active/<id>/STATE.md` with machine-maintained sections (phase, % done, last-5 events, open risks, links to active spec/plan/tasks), rewritten at network boundaries (ship, verify, session-end, coordinator merge). Write `current-initiative`/`current-spec` pointers at session start (skill-side) so attribution starts working. This file becomes the always-injected, always-current ~40-line answer to "what is the state of this initiative?"
3. **Wire the read path**: (a) session-start injects top-K index entries by `paths_touched` ∩ recently-touched files + recency; (b) add `memory-index.sh query` to the constitution's delegation table so agents reach for it before grep; (c) index `.archive/` entries with `superseded_by` chains so history stays retrievable. Embeddings can come later — the metadata index is already 80% of the value, unused.
4. **Enforce provenance at write time**: `validate.sh` (or the post-write index touch) rejects/flags memory files missing `status/created/last_verified` frontmatter; backfill the 36 existing files. This single change turns the promotion/decay lifecycle from fiction to running code.
5. **Multi-horizon dream**: extend `/dream` to roll up — daily in-flight briefs → weekly digest per initiative → monthly rollup → quarterly archive summary. Each horizon caps at ~100 lines. Year-two sessions then recall year one in three Reads, not three thousand.
6. **Make memory-plane failures loud**: witness-brief generation and pointer-file writes get the same treatment stop-hooks just got — a visible stderr/report line when they fail, and a `harness-doctor` check for `pending` checkpoints older than 2 days.

**One-paragraph verdict:** this is one of the most complete memory *write* architectures the panel has reviewed — taxonomy-complete, cap-enforced, proposal-gated, age-aware. It is held back by an almost entirely missing *read* path, an unimplemented initiative layer (precisely the end-goal's subject), and unpopulated metadata that leaves the lifecycle machinery idle. The recommendations above are mostly wiring, not invention: the harness already owns every component it needs.
