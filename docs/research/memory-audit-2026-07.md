# Memory System Audit — 2026-07-23

> **Goal audited against:** every Claude session/prompt knows the current project state (what is shipped, which initiative/spec/task is next), updates memory after changes, stays correct over multi-year horizons, always picks up the latest decision, and actually retrieves relevant context via tool calls — in both greenfield and brownfield adoptions.
>
> **Method:** dynamic workflow — 9 parallel dimension auditors (session-boot, write-path, read-path, initiative-state, shipped-verified, latest-wins, graph-memory, brownfield, liveness) + 2 web researchers, followed by 4 adversarial verifiers that re-checked every claim on disk. 15 agents, 384 tool calls, ~1.44M tokens. **87 gap claims: 78 CONFIRMED, 9 ADJUSTED, 0 refuted.**
>
> Builds on the 2026-06-12 panel review ([memory-system-review.md](memory-system-review.md)). Several of its recommendations were implemented since (memory-recall.sh, initiative-state.sh, memory-rollup.sh, T-ID grep hardening, index lifecycle fields) — this audit verified what those implementations actually do in operation.

---

## 1. Headline verdict

The 2026-06-12 review said: *"write side strong, read path missing."* Five weeks later the truer statement is: **both sides are now built, and almost none of it runs.** The architecture is taxonomy-complete and the wiring exists on paper, but three root causes leave the system unable to answer the goal's core question — "what is the current state?" — correctly:

### Root cause A — the LLM metabolism has a 100% lifetime failure rate
Every memory stage that requires a background `claude -p --bare` spawn — dream consolidation, instinct extraction, compaction witness briefs — has failed **every single time since 2026-05-28** with "Not logged in": hook-spawned CLIs resolve the default config dir instead of the operator's `CLAUDE_CONFIG_DIR=$HOME/.claude-qyndex`. 79/79 instinct extractions failed; 6/6 dream spawns died; every witness returned empty. Worse, `auto-dream-check.sh` stamps `last_run_epoch` **unconditionally after the spawn**, recording every failure as a success and suppressing retries for 24h. Net organic memory produced in 2 months of intensive development: **zero**. All patterns are seeds, ADRs were batch-backfilled Jun 12, MEMORY.md is frozen at 2026-05-29 (still says "_(none yet)_" under Decisions while 3 accepted ADRs exist).

### Root cause B — freshness has a single fragile writer and no self-healing
`initiative-state.sh sync` — the mechanism behind "STATE.md is the always-current initiative answer" — has exactly **one** automatic caller: the graceful SessionEnd hook. The documented "network boundaries" (ship, verify, merge) are wired **nowhere**. Session start merely *warns* about staleness instead of running the <1s deterministic sync. None of the shipped schedulers (dream-cron 03:00, atlas-refresh 04:00, gc-nightly 02:30) were ever installed (`crontab` empty, no LaunchAgents, `routines-installed` sentinel missing), and all are `surface: desktop` — a closed laptop stops 100% of scheduled metabolism. Observed result: STATE.md 907h stale, atlas 56 days stale (and born invalid: `git_sha: "no-git"`), index.jsonl frozen 41 days, rollups stopped at 2026-W24.

### Root cause C — split-brain schemas and silently no-op'ing mutations
Multiple mechanisms *report* success while doing nothing:
- ADR `status`/`superseded_by`/`last_verified` live in **two disjoint representations** (YAML frontmatter read by the index/recall; body bullets written by templates/scripts) with disjoint readers — an edit through either path leaves the other stale.
- `post-write-format.sh` matches memory paths with **relative globs** while tool inputs carry **absolute paths** — the on-write `memory-index.sh touch` has never fired.
- `adr-new.sh:74` and `/adr-walk --reverify` invoke `memory-index.sh` with **no subcommand** — it prints the help text while the caller claims "(index rebuilt)".
- `memory-promote.sh`'s promotion/quarantine `sed` targets body lines (`- **Status**: emerging`) that **no pattern file contains** — and still increments its "promoted" counter.
- Session-start "Last dream:" reads `.last_run`; every writer writes `last_run_epoch` — the banner prints "never" unconditionally.
- `memory-gc.sh` evicts by `last_accessed`, a field **nothing ever writes** — all entries tie at epoch 0, making eviction order arbitrary.

### The single most damning finding for the goal
**`tasks/TASKS.md` — the constitutionally-declared sole source of truth — currently says spec-004 is unshipped (17/18 tasks `[ ]`) when it in fact shipped 2026-06-14 via PR #13 with all accepts passing.** STATE.md dutifully reports "phase: specifying · 1/18 done" for a five-week-shipped initiative, and injects spec-003's tasks as spec-004's next work (no spec filter on the "next unblocked" grep). There is no mechanism that detects or repairs ledger-vs-git-reality reverse drift. Today, a fresh session does not merely *lack* shipped-state awareness — it is **actively told the wrong state, labeled "machine-current"**, and subagents are instructed to trust it without staleness checks.

---

## 2. The taxonomy scorecard (user's question: short-term / long-term / episodic / graph)

| Layer | Exists? | Alive? | Verdict |
|---|---|---|---|
| **Working** (this turn) | ✓ hooks inject branch/phase/spec/next (~50 tok/turn, cache-stable) | ✓ | Best-in-class. `next-task.sh` is now dep-aware; the 31-turn placeholder loop is fixed. |
| **Short-term** (session bridge) | ✓ in-flight brief, witness, session-recent.json, crash detection + orphan reconcile | ⚠ half | Deterministic parts ran; LLM witness dead 100% (root cause A). No boot context after `/clear` or compaction (matcher is `startup\|resume` only). |
| **Episodic** (what happened) | ✓ incidents, verify/ evidence, decisions.log, observations (5,386 lines, still appending) | ⚠ write-only | Nothing reads it back: evidence rots in 29 dated dirs with no index; decisions.log has zero consumers; observations never distilled (extraction dead). |
| **Semantic** (what we know) | ✓ MEMORY.md, patterns, ADRs, atlas | ✗ frozen | All seeded/backfilled; zero organic writes in 2 months; index frozen; MEMORY.md contradicts the ADR store. |
| **Procedural** (how we act) | ✓ skills; instinct pipeline | ⚠ half | Skills fine. Instincts: observation side alive, extraction 79/79 failures, zero yield. |
| **Graph** | ✗ | ✗ | **No memory graph exists.** Graphify is a *code* call-graph, explicitly "NOT a memory layer" (.mcp.json:268), and nothing refreshes it. `[[wikilink]]` parsing exists in the indexer but `back_refs` are empty in all 27 entries (matcher can't resolve `ADR-0001` → slug ids); `superseded_by` edges are never written by anything. |
| **Consolidation** ("sleep") | ✓ dream/rollup/promote machinery | ✗ dead | Never succeeded once (root cause A); rollups frozen at W24; false-success recording masks it. |

**Retrieval (user's question: "does Claude use the tool call to get the right relevant context?"):** structurally yes — `memory-recall.sh` is auto-injected at SessionStart and on every subagent dispatch, and sits in the constitution's delegation table. In practice it serves noise: the `score > 0` filter passes entries with **zero path overlap** (status+recency bonuses alone clear it), the path extractor's extension whitelist **omits `.sh`** (so no memory can ever be recalled by path for shell work — i.e., for this entire harness), subagent recall is scoped to the spec/plan *markdown* paths rather than the code the child will touch, there is no content-based retrieval of any kind (no grep-body convention, no BM25, no embeddings), and archives are permanently unreachable. The hook Bash log shows the advisory path has **never been exercised organically** — every invocation was a session authoring or auditing the script itself.

---

## 3. Answers to the operator's specific questions

- **"Does each session know what is shipped?"** No. Nothing injects shipped state (only *next* state); TASKS.md is wrong in the reverse direction; STATE.md has no shipped field; specs never move out of `specs/active/` (archive empty); OVERNIGHT_REPORT.md describes a run from May 29.
- **"Does it know what backend API we have implemented?"** No. The atlas's "API / routes" section emits only directory names ("Route root: app/"); there is no endpoint/route/component inventory anywhere in memory, even when the atlas is fresh (it is 56 days stale).
- **"What frontend is done, with verification like the actual user sees and hears?"** The *merge-time* machinery is genuinely strong — `collect-evidence.sh` captures per-AC screenshots/video/HAR bound to a commit, and `evidence-gate` blocks merge without it. But nothing durable survives the merge: no verified-journey registry, no evidence index, contradictory bundles for the same spec coexist with no supersession pointer.
- **"When a decision changes, does Claude always pick up the latest?"** No — mechanically hollow. The reversal probe (flip ADR-0001 tomorrow) shows consumers never converge: nothing flips the old ADR to superseded (`memory-promote.sh` documents the rule but doesn't implement it; `/supersede` handles only specs; `adr-new.sh` has no `--supersedes` flag); the index never sees the new ADR (bash-written, reindex is a no-op); and `check-model-consistency.sh` would **actively enforce the old decision in CI** until a human amends the constitution. The `-5` superseded penalty in recall is unreachable dead code.
- **"Is memory maintained for multiple years?"** The design (rollup day→week→month→quarter, GC with archive, age-gating) is right and matches state-of-the-art recommendations — but the rollup chain's only trigger is the dead dream pipeline, monthly/quarterly rollups freeze at first mid-period generation, weeks W25–W30 are permanently ungenerated (cmd_weekly can only build the current week), and GC's eviction ordering is broken. As-is, year-two recall of year one would be git history plus whatever was hand-written.
- **"Greenfield/brownfield?"** Brownfield seeding is thin: `/adopt` builds an atlas + hotspots and imports ≤50 conventional doc files, but there is **no ADR backfill from git archaeology, no API inventory, no shipped-feature reconstruction**. The factory's own memory pollutes adoptions (flask/react-vite/… seed patterns, factory rollups, a 27-entry factory index.jsonl land in projects using none of those stacks); greenfield template-clean leaves index.jsonl dangling at moved paths; `mirror-user-state.sh` hardcodes `$HOME/.claude/` and silently snapshots the wrong tree under `CLAUDE_CONFIG_DIR` installs (live manifest shows an empty archive). Reconcile `--upgrade` does correctly preserve an adopted project's accumulated memory.

---

## 4. What is genuinely good (keep and build on)

- Per-turn/state injection design: cheap (~50 tok), cache-stable, dep-aware next-task, loop-breaker protocol, crash detection with orphan-task reconcile.
- Authority model: single ledger (TASKS.md) + write-only projections is exactly the architecture the ecosystem converged on (Beads → native Tasks).
- Merge-time evidence rigor: per-AC artifacts bound to commits, gated in CI — ahead of almost everything surveyed.
- Proposal-not-mutation consolidation (`memory.proposed/` + human review) and hard caps everywhere (200-line MEMORY.md, matching the official Claude Code memory contract).
- The STATE.md ≤60-line always-current concept is ahead of most Ralph-loop implementations — it just needs writers.
- Age-gating and content-based staleness checks on most boot surfaces (ADR dates immune to clone-reset mtimes; atlas SHA-vs-HEAD check).

---

## 5. External research grounding (2025–2026)

**Anthropic (primary):**
- Effective context engineering for AI agents — https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents (2025-09-29)
- Effective harnesses for long-running agents — https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents (2025-11-26) — initializer + per-session progress artifacts; the harness's STATE.md/in-flight pattern is a faithful match.
- Managing context (memory tool + context editing; write-before-forget measured +39%) — https://www.anthropic.com/news/context-management (2025-09-29) — validates pre-compact-witness *design*; argues the witness should persist insights into memory topic files, not just transcript summaries.
- Memory tool docs + cookbook — https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool · https://platform.claude.com/cookbook/tool-use-memory-cookbook
- Claude Code memory docs (index + topic files, 200-line/25KB budget, `modified:` stamping v2.1.214, post-write size check v2.1.210) — https://code.claude.com/docs/en/memory
- Claude Code best practices (Boris Cherny) — https://www.anthropic.com/engineering/claude-code-best-practices (2025-04-18)
- Multi-agent research system — https://www.anthropic.com/engineering/built-multi-agent-research-system (2025-06-13)

**Temporal-graph & memory-layer research:**
- Zep: temporal KG for agent memory — https://arxiv.org/abs/2501.13956 · provenance: https://blog.getzep.com/how-zep-tracks-provenance-in-agent-memory/
- Graphiti (bi-temporal edges; invalidate-don't-delete) — https://github.com/getzep/graphiti · https://neo4j.com/blog/developer/graphiti-knowledge-graph-memory/
- Letta memory blocks — https://www.letta.com/blog/memory-blocks/ · sleep-time compute — https://www.letta.com/blog/sleep-time-compute/
- Mem0 (ADD/UPDATE/DELETE/NOOP reconciliation) — https://arxiv.org/abs/2504.19413 · A-MEM — https://arxiv.org/abs/2502.12110
- PROJECTMEM (event-sourced local-first memory for coding agents) — https://arxiv.org/html/2606.12329v1 (2026-06)
- Redis long-horizon agent state — https://redis.io/blog/long-horizon-ai-agents-memory-state-infrastructure/

**Claude Code ecosystem:**
- Beads (git-is-the-database ledger, hash IDs, memory decay) — https://steve-yegge.medium.com/introducing-beads-a-coding-agent-memory-system-637d7d92514a · https://ianbull.com/posts/beads/ · native Tasks migration: https://paddo.dev/blog/from-beads-to-tasks/ · skills-write-ledger loop: https://dollardill.github.io/beads-superpowers/
- Ralph loops (stateless iterations; PLAN/progress/git as the only memory) — https://ghuntley.com/ralph/
- Obsidian-vault-as-memory — https://github.com/YuNaga224/obsidian-memory-mcp (Anthropic memory server → wikilinked markdown entities) · https://github.com/AgriciDaniel/claude-obsidian (hot.md/index.md two-tier) · https://buildtolaunch.substack.com/p/claude-code-obsidian-second-brain
- ADR bootstrap/drift for brownfield — https://github.com/rvdbreemen/adr-kit · git hotspot mining — https://www.repowise.dev/
- Git trailers as queryable memory — https://medium.com/@dstekanov.tech/can-git-history-act-as-a-lightweight-memory-layer-for-ai-coding-agents-d53fa345b0a2

**Key patterns adopted into the plan:** write-before-forget; supersedes-not-delete with bi-temporal metadata; sleep-time consolidation owned by a separate authenticated agent; explicit ADD/UPDATE/DELETE/NOOP reconciliation before appends; event-sourced ledger with state files as projections; index-first progressive disclosure; wikilinked one-idea-per-note graph approximation; commit-trailer retrieval; ADR archaeology for brownfield.

---

## 6. The fix plan

Ordered by dependency, not just severity — Phase 0 unblocks everything above it. Each item: **why** (which gaps it closes) and **how**.

### Phase 0 — Resuscitate the metabolism (days; unblocks 30+ downstream gaps)
1. **Fix headless auth** (`background-claude-auth-dead`, CRIT ×2): every hook that spawns `claude -p` must propagate the session's `CLAUDE_CONFIG_DIR` (capture it at SessionStart into `.claude/state/config-dir`, source it in spawns), check the exit code, and treat non-zero as failure. *Why:* one bug killed dream, instincts, and witness for the repo's entire life.
2. **Record failure as failure** (`dream-false-success-recorded`, `awaiting-review-flag-dropped`, `last-dream-key-mismatch`): stamp `.dream-state.json` only on exit 0; preserve `awaiting_review` on early-exit rewrites; read/write one key (`last_run_epoch`). *Why:* false success suppresses retries and hides six weeks of death.
3. **Fix the silent no-ops** (`index-frozen-touch-never-fires`, `adr-new-reindex-noop`, `promote-sed-targets-nonexistent-lines`, `gc-evicts-newest`): absolute-path globs in `post-write-format.sh` (+3-level nesting); give `adr-new.sh`/`adr-walk` a real `rebuild` subcommand call; make promote/quarantine mutate **frontmatter** (single schema, below); write `last_accessed` on recall hits or drop the field from GC ordering. *Why:* mutations that report success while doing nothing are worse than missing features — they defeat the audit trail.
4. **Add a liveness self-test** to `validate.sh`/`harness-doctor`: fail (not warn) on index mtime > 7d with newer memory files, `(pending)` checkpoints > 2d, dream last-success > 7d, rollup gap > 2 weeks. *Why:* the harness has a 361-test rig and every one of these bugs still shipped — the tests proved code paths once, never that the metabolism is alive. Detection-without-obligation was the 06-12 review's SRE finding; it repeated.

### Phase 1 — Make "current state" self-healing and true (week 1)
5. **Sync at boot, not just graceful death** (`single-writer-sessionend`, `sync-only-at-session-end`, `staleness-warning-advisory-only`): SessionStart runs `initiative-state.sh sync` + `memory-index.sh rebuild` + `atlas-refresh.sh` when their staleness checks trip — they are deterministic and <1s. Warnings become remediations. Extend the SessionStart matcher to `clear|compact` sources (`no-boot-context-after-clear-or-compact`).
6. **Wire the documented network boundaries** : `/ship` (release agent step), `/verify` completion, and a post-merge CI job each call `initiative-state.sh sync` and commit the result. *Why:* the constitution promises it; nothing implements it.
7. **Repair and guard the ledger** (`tasks-ledger-contradicts-shipped-reality`, CRIT): one-time reconcile of TASKS.md vs merged PRs (spec-004 → `[x]`); then a CI check on main that fails when a merged PR's `Task:` trailers reference tasks still `[ ]` — reverse-drift detection. Per-spec filter on STATE.md's "next unblocked" (`next-tasks-cross-spec-contamination`); per-initiative phase instead of the global swarm file (`state-does-not-answer-shipped`); sync **all** active initiatives, not newest-by-mtime (`multi-initiative-rot`).
8. **A durable SHIPPED registry** (`nothing-injects-shipped-state`, `no-durable-verified-journey-registry`, `specs-active-never-archived`): ship-time appends one line per spec to `specs/SHIPPED.md` (spec, PR, merge date, evidence bundle path, verified journeys); spec file moves `active/` → `shipped/`; session-start injects the last 3 shipped lines. Evidence bundles get index entries with supersession pointers (latest verdict wins) so proof stops rotting in dated dirs (`conflicting-evidence-bundles-no-supersession`).
9. **Atlas v2 with an API/journey inventory** (`atlas-has-no-endpoint-inventory`, `atlas-staleness-warn-only`): extend `atlas-refresh.sh` to emit `ENDPOINTS.md` (route table scraped per stack: Flask blueprints, Express routers, Next.js app routes) and `JOURNEYS.md` (from tagged Playwright specs + evidence index). Refresh at the merge boundary in CI — not a desktop cron that requires an open laptop.

### Phase 2 — Latest-always-wins mechanics (week 2)
10. **One schema** (`status-field-split-brain`, CRIT): frontmatter is the sole home of `status`/`supersedes`/`superseded_by`/`last_verified`; migrate body bullets; `validate.sh` rejects the body-bullet form.
11. **Executable supersession** (`adr-supersession-never-executes` CRIT, `supersede-edge-never-written`, `adr0001-reversal-does-not-converge`): `adr-new.sh --supersedes ADR-NNNN` flips the old ADR's frontmatter, writes both edges, reindexes; recall/`architect` filter `status: superseded` (extend the filter beyond architect to security/reviewer — `supersede-hygiene-human-only`); adopt Graphiti's invalidate-don't-delete: superseded entries stay, marked invalid-as-of-date with provenance. Add a CI consistency check ADRs-vs-constitution §V so a reversed decision can't be silently enforced backwards by `check-model-consistency.sh` (also un-hardcode its stale-model literal).
12. **MEMORY.md as projection** (`memory-md-decisions-stale`): generate the Decisions/Patterns sections of MEMORY.md from the index instead of hand-editing — it can then never contradict the ADR store.

### Phase 3 — Retrieval that actually retrieves (week 2–3)
13. **Kill the noise floor** (`recall-noise-floor` CRIT): status/recency are tie-breakers, not qualifiers — require path-intersection ≥ 1 or an explicit tag match; empty result is a valid result.
14. **Index what the project is made of** (`sh-paths-unindexable` CRIT): extension whitelist += sh/css/html/toml (or invert: blacklist binaries). *Why:* today path-recall is structurally impossible for this harness's own domain.
15. **Scope subagent recall to target code** (`subagent-recall-wrong-scope`): recall on the task's `files:`/plan-phase paths, not the spec/plan markdown paths.
16. **Content recall + trailer recall** (`no-content-retrieval`): add `memory-recall.sh --grep <term>` (body search across memory + `git log --grep` over Constraint/Rejected/Directive trailers — the commit protocol has been accumulating a rejected-alternatives memory nobody reads). Embeddings optional later; metadata+grep is 80% of the value.
17. **Reachable archives** (`archives-unretrievable`): index archived files with `superseded_by` chains; recall `--include-archived` follows them. Stamp `modified:` frontmatter on memory writes (native v2.1.214 parity) so recency survives clone-reset mtimes (`mtime-recency-fragile`).

### Phase 4 — Multi-year horizon + graph (week 3–4)
18. **Deterministic rollup trigger** (`rollup-no-deterministic-trigger`, `rollup-chain-dead-with-dream`, `rollup-parents-frozen-premature`): a weekly CI job (and a session-start week-boundary check as local fallback) runs `memory-rollup.sh`; `cmd_weekly` accepts a target week to backfill W25–W30; month/quarter regenerate at period close.
19. **Separate the sleep agent from the session** (Letta sleep-time pattern): dream runs as a scheduled Cloud Routine (already designed) **plus** a same-machine fallback that reuses the interactive session's auth (Phase 0.1). Dream adopts Mem0's ADD/UPDATE/DELETE/NOOP reconciliation and the invalidate-don't-delete rule.
20. **Graph approximation, then graduation** (`no-memory-graph-exists`, `back-ref-matcher-broken`, `obsidian-vault-viable-but-not-sufficient`): fix the back_ref matcher (normalize `ADR-NNNN` ↔ slug ids); adopt `[[slug]]` wikilinks in memory bodies (the indexer already parses them); memory/ becomes an Obsidian-compatible vault for free (human-auditable graph view, git-diffable — per obsidian-memory-mcp). Catalogue graphiti-mcp (version-pinned) in `_disabled_examples` for teams wanting a real temporal KG. *Assessment of the user's idea:* Obsidian-style linking is cheap and worth doing now; graphify is the wrong tool (code graph, explicitly not memory) — don't conflate them.
21. **Ledger decay** (Beads pattern): dream collapses long-closed `[x]` task blocks into one-line summaries; TASKS.md stays readable at year 3. Hash-suffixed task IDs if parallel swarm streams generate tasks on branches.
22. **hot.md session cache** (claude-obsidian pattern): session-end writes a ~500-word rolling recent-context note that session-start injects — the missing tier between per-turn state and MEMORY.md; also fixes today's loss of stale in-flight content (`stale-inflight-content-lost`).

### Phase 5 — Brownfield bootstrap (with the next adoption)
23. **Memory archaeology in `/adopt`** (`no-history-backfill`): a phase that mines git history into memory — ADR backfill (adr-kit pattern: detect decisions already in effect, batch-record as Accepted), endpoint inventory (Atlas v2 pass), shipped-feature reconstruction from merge history into `specs/SHIPPED.md`, hotspot list aimed at the characterize skill.
24. **Clean seeding** (`factory-memory-pollution`, `dangling-index-after-template-clean`, `seed-auto-overbroad`): reconcile/setup excludes factory rollups + index; `seed-patterns.sh` seeds only detected frameworks (not language→every-framework); template-clean rebuilds index.jsonl after moving files.
25. **Fix user-state mirroring under CLAUDE_CONFIG_DIR** (`user-state-mirror-wrong-home`): resolve the live config dir instead of hardcoding `$HOME/.claude/` — today the user-level knowledge base has an empty backup.
26. **Initiative bootstrap for adoptions** (`no-brownfield-initiative-bootstrap`): `/adopt` closes by creating the first initiative + STATE.md so the layer isn't empty on day one.

---

## 7. Worked example — this harness in another project

**Setup:** you adopt the harness into `acme-shop`, a 3-year-old Django + React storefront, via the brownfield flow (reconcile → setup → `/adopt`).

**Today (before fixes):**
- Day 1: `/adopt` builds an atlas (stack fingerprint + hotspots) and imports whatever markdown lives under `docs/adr/`. Memory otherwise starts with *someone else's* seeds: flask/react-vite/nextjs patterns, the factory's June rollups, and an index pointing at factory files. No record exists of the ~40 features acme-shop shipped over 3 years, its 85 API endpoints, or which checkout journeys are actually proven.
- Week 2: you ship a spec. Evidence is captured and gated at merge — then rots in `verify/2026-08-*/` forever. STATE.md updates only if the session ends gracefully. The first crashed session leaves it stale, and every subagent thereafter is told the stale file is "machine-current".
- Month 2: a decision changes (switch payments provider). A new ADR is written; the old one stays `accepted`; recall keeps serving it; nothing contradicts the agent that re-implements against Stripe assumptions. Dream has silently failed since day 1 (your shell exports a custom `CLAUDE_CONFIG_DIR`), while the state file claims it ran nightly.
- Year 2: "what did we do in 2026?" = git archaeology. Rollups stopped the week the laptop was closed overnight; MEMORY.md still lists week-1 seeds.

**After the plan:**
- Day 1: `/adopt` archaeology emits ~25 backfilled Accepted ADRs from commit history, `ENDPOINTS.md` with the 85 real routes, `SHIPPED.md` reconstructed from merge history, and hotspots feeding the characterization backlog. Seeds are Django+React only; the index is rebuilt clean. The first initiative + STATE.md exist before the first task.
- Every session, forever: boot self-heals — stale STATE/index/atlas are re-synced in <2s, not warned about. The `<state>` line says `Shipped: 41 specs (last: checkout-v2 #612) | Next: T-a4f2 payment-retry`. A subagent editing `payments/api.py` gets auto-recalled: the payments ADR (latest, because the superseded one is filtered), the incident from the March outage, and the two rejected approaches mined from commit trailers on that file.
- On every merge: CI flips the ledger, syncs STATE.md, refreshes the endpoint inventory, appends to SHIPPED.md, and indexes the evidence bundle — so "which journeys are proven" is answerable from one file, with the latest verdict winning.
- Nightly (or next session if the machine slept): dream runs authenticated, consolidates with ADD/UPDATE/DELETE/NOOP semantics, supersedes-not-deletes, and rolls the week into the month. In year 3, "what happened in 2026" is three Reads: `2026.md` → `2026-Q4.md` → the week you care about — with `[[links]]` from any decision to the incident that motivated it, browsable as an Obsidian graph.

---

## 8. Meta-lesson

The June audits recorded "ALL 63 gaps FIXED" and "ALL 40 fix items DONE" — and they were, at merge time, by the standards of the test rig. This audit found the *same subsystems* dead in operation for six weeks. The distinction the harness must internalize: **verified-at-merge is not alive-in-production.** The memory plane needs the same treatment the constitution demands for application code — evidence, not assertion; and for a metabolism, evidence means *continuous liveness probes that fail loudly*, not warnings that scroll past at boot. That is Phase 0.4, and it is the one item that prevents this report from being written a third time.

---

## Appendix A — full verified gap register

87 claims (78 CONFIRMED, 9 ADJUSTED, 0 refuted; 4 cross-dimension duplicates marked). Full structured data with evidence cites, adjusted notes, and proposed fixes: `verify/2026-07-23-memory-audit/gaps.json`. Severity: 10 critical · 31 high · 32 medium · 14 low. Dimensions: session-boot 11 · write-path 12 · read-path 9 · initiative-state 7 · shipped-verified 9 · latest-wins 12 · graph-memory 7 · brownfield 8 · liveness 12.
