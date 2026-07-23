# Memory System — Implementation Plan (reviewed & corrected)

> **Input:** the fix plan in §6 of [memory-audit-2026-07.md](memory-audit-2026-07.md) (87 verified gaps).
> **This document:** the result of adversarially reviewing that plan for correctness/completeness/sequencing/testability/blast-radius (5 independent reviewers + high-effort synthesis; workflow `wf_60684cb1-e2b`), then converting it into a **TDD-shaped, CI-gated, PR-by-PR implementation plan**. Every work item has a red-before/green-after test, a durable artifact, and CI wiring.
> **Machine-readable plan:** [`verify/2026-07-23-memory-plan-review/plan.json`](../../verify/2026-07-23-memory-plan-review/plan.json) — 25 work items, full review findings, landing order, open questions.

---

## 0. Verdict on the audit plan

The audit's **diagnosis is sound** and its Phase 0→5 dependency spine is broadly right — but **it is not safe to build as written.** Five corrections are load-bearing, and one of them corrects a factual error in the audit itself. I re-verified the two most consequential on-disk before trusting the reviewers:

### Correction 1 (audit was WRONG) — the headline root cause is misdiagnosed
The audit's root cause A said: hook-spawned `claude -p` resolves the *default* config dir instead of the operator's `CLAUDE_CONFIG_DIR`, fix = propagate the var. **This is verifiably false on this machine:**
- `CLAUDE_CONFIG_DIR` is already `/Users/shravanjha/.claude-qyndex` and is inherited by `nohup` subshells (the exact spawn form). Propagating it is a no-op.
- **But the failure is still real:** a `nohup bash -c "claude -p …"` spawn today reproduces `Not logged in · Please run /login` (exit 1) — *after* `claude` starts and reads settings. Interactive `claude` authenticates from the macOS keychain; a **detached/no-TTY background process cannot reach the keychain credential**, so auth works in a foreground shell and fails under `nohup`. The correct fix is an `apiKeyHelper` or an `ANTHROPIC_API_KEY` exported into the *spawn* environment — **not** `CLAUDE_CONFIG_DIR`, and it is operator-environment-specific (open question O-1).
- **Second, independent root cause the audit missed entirely:** `pre-compact-witness.sh:68` runs `timeout 120 claude …`, but **`timeout`/`gtimeout` do not exist on stock macOS** (`command -v` → not found). The witness spawn dies with "command not found" *before `claude` runs at all* — fully explaining the 100% witness-empty rate, independent of auth. (The dream and instinct spawns use bare `nohup` without `timeout`, so they fail on auth only.)

**Consequence:** re-scope Phase 0.1 from "propagate the config dir" (a no-op) to "reproduce the detached-spawn failure with a falsifiable probe, then apply the auth+timeout fix the reproduction justifies."

### Correction 2 (META blocker) — no CI runner executes the test suite
The harness has `.claude/scripts/test/*.sh` (incl. `memory-system.sh`, `gc-suite.sh`) but **no workflow runs them**: `harness-validate.yml` runs only `loop-control.sh` + `oq-aging.sh`; `ci.yml`'s `test-unit.sh` detects no language stack and exits 0 on this shell-only repo; `verify.sh` has no `scripts/test/` loop. **Every "add a test" the plan calls for would be a dead file that proves nothing** — which is exactly how 87 gaps shipped "green". Wiring a memory-test runner **plus a dead-test detector** (fail if a `test/*.sh` exists that no workflow references) must be **item zero**. This is the §8 meta-lesson made executable.

### Correction 3 — liveness probes are mis-sequenced into a repo-bricking wedge
The audit put hard-fail, clock-relative liveness probes into `validate.sh`. But `validate.sh` feeds the **required** `harness-validate` gate with no paths filter and **no escape hatch** (the evidence-gate maintenance hatch covers only the evidence-gate job). Every liveness condition is TRUE today (index 41d frozen, dream 6/6 failed, rollups frozen at W24, checkpoint 38d pending) — so landing this **reds main for every PR, including the fix PRs.** Chicken-and-egg. Fix: ship probes **advisory in `harness-doctor` FIRST**, promote them to **required in `validate.sh` LAST** (after the metabolism is proven alive), gated behind `LIVENESS_SOFT=1` and env-overridable thresholds so the promotion PR can prove-green, and check **branch-local committed-state** staleness (index older than newest committed memory file — deterministic, a PR can fix it) rather than wall-clock-since-last-dream.

### Correction 4 — the ledger repair hard-fails its own required gate
The audit's item 7 flips spec-004 `T-140..T-157` to `[x]`. But `check-tdd-ledger.sh` (`LEDGER_ENFORCE_FROM=111`, required in `harness-validate` **and** re-run inside `evidence-gate`) demands committed `red.log`+`green.log` for every `[x]` task ≥ 111 — and **only T-154 has them.** The flip fails immediately (and `SKIP_TDD_LEDGER` was removed server-side). Fix: record shipped-state via item 8's `specs/SHIPPED.md` and/or an `[s]` shipped-class terminal marker that skips the red/green requirement (land item 8 **before** the reconcile); only flip to `[x]` if you first backfill the ledger logs from the PR #13 evidence bundle.

### Correction 5 — several intra-phase orderings are load-bearing and implicit
`M-03` (working reindex) gates `M-05b` (boot rebuild); `M-10` (one schema) precedes `M-11` (executable supersession); `M-13`+`M-14` must ship together (sh-index is noise without the noise-floor filter; the filter can't match shell work without the index); `M-05b` (boot auto-sync) must land **after** `M-07` (ledger repair) or it rewrites STATE.md with the same wrong "specifying · 1/18" content plus a fresh timestamp — defeating the staleness banner that at least flags it today.

**Bottom line:** with these five corrections the plan is buildable as **~17 harness-maintenance PRs**, each mergeable through the evidence-gate maintenance hatch (`.claude`/`.github`-only diffs need no browser ACs). Without them, four of the first five PRs would red main.

*(Coverage caveat: the completeness reviewer's structured output was lost to a schema-retry cap; its progress preview reported "all 10 criticals mapped." The other four dimensions + synthesis completed, and I cross-checked critical-gap coverage against the register directly — all 10 criticals map to a work item below.)*

---

## 1. The work items (TDD-shaped)

Each item: **id · phase · what changes · test file · red (fails now) → green (passes after) · durable artifact · CI wiring · deps.** Full detail in `plan.json`; condensed here.

### Phase 0 — resuscitate (nothing downstream is real until these land)

| id | title | red → green | artifact | deps |
|---|---|---|---|---|
| **M-00** | Memory-test runner + dead-test detector in CI | Before: `memory-system.sh`/`gc-suite.sh` run in no workflow → dead-test check fails. After: a `Memory metabolism tests` step loops `test/*.sh`; validate.sh fails if any `test/*.sh` is unreferenced | `verify/<d>/ci-runner/run-log.txt` | — |
| **M-01a** | Falsifiable auth+timeout **probe** in harness-doctor (advisory) | Before: no probe; metabolism silently dead. After: `claude -p 'ok'` exit+stderr and `command -v timeout` captured | `verify/<d>/auth-probe/probe.txt` | M-00 |
| **M-01b** | Fix the **reproduced** spawn failure (auth env + portable timeout) | Before: `nohup claude -p` → "Not logged in"; `timeout 120` → command-not-found. After: spawn seam sources an auth-present env; `timeout` replaced by portable guard (detect g/timeout else drop) | `verify/<d>/spawn-fix/before-after.log` | M-01a |
| **M-02** | Record dream **failure as failure** | Before: `auto-dream-check.sh:120` stamps `last_run_epoch` unconditionally; early-exits drop `awaiting_review`; boot reads `.last_run` not `.last_run_epoch`. After: stamp only on exit 0; preserve the flag; one key | `verify/<d>/dream-state/fixtures.txt` | M-00 |
| **M-03** | Fix the silent no-ops | Before: `post-write-format.sh` relative globs vs absolute paths (touch never fires); `adr-new.sh:74` calls `memory-index.sh` with no subcommand (prints help); `memory-promote.sh` sed targets body lines no file has; gc `last_accessed` unwritten. After: absolute-path globs (+3-level); real `rebuild` subcommand; frontmatter mutation; gc order fixed | `verify/<d>/no-ops/each-fires.txt` | M-00 |
| **M-04** | Liveness probes in **harness-doctor** (advisory, env-parameterized) | Before: dead metabolism is silent/warn-only. After: harness-doctor fails (advisory) on stale committed index / dead dream / rollup gap, thresholds env-overridable | `verify/<d>/liveness/doctor-report.json` | M-00 |

### Phase 1 — make "current state" true and self-healing

| id | title | red → green | deps |
|---|---|---|---|
| **M-05a** | SessionStart matcher += `clear\|compact` | Before: no boot context after `/clear` or compaction. After: matcher covers all four sources | — |
| **M-07-data** | Reconcile spec-004 shipped-state **without bare `[x]`** | Before: TASKS.md says spec-004 unshipped 5wk after PR #13. After: `SHIPPED.md`/`[s]` records it; `check-tdd-ledger` still green | M-08 |
| **M-07-state** | Per-spec STATE filter + ground-truth phase + all-initiative sync | Before: STATE lists spec-003 tasks as spec-004's next; phase from stale swarm file; only newest initiative synced. After: spec-filtered, per-initiative phase, all active synced | M-07-data |
| **M-08** | Durable **SHIPPED registry** + evidence index w/ supersession | Before: proof rots in 29 dated dirs, no index. After: `specs/SHIPPED.md` (spec/PR/date/evidence/journeys) + indexed bundles, latest verdict wins; boot injects last 3 | M-00 |
| **M-05b** | Boot auto-sync + index rebuild + time-boxed atlas on staleness | Before: boot warns, never heals. After: deterministic sync/rebuild run (<2s); atlas backgrounded | M-03, M-07-data, M-07-state |
| **M-06** | Wire network-boundary sync into `/ship` + `/verify` | Before: only session-end syncs. After: skills call sync (grep-gated); STATE committed pre-merge on PR branch | M-07-state |
| **M-09a** | Atlas v2 **ENDPOINTS.md** (independent stack scraper) | Before: atlas emits only dir names. After: route table per stack (Flask/Express/Next) from fixtures | M-00 |
| **M-07-guard** | Reverse-drift guard (**post-merge**, advisory) + accept:/summary: check | Before: no detection of ledger-vs-git drift. After: `push:main` job flags merged-PR `Task:` trailers still `[ ]` (never `pull_request` — WIP branches carry them legitimately) | M-07-data |

### Phase 2 — latest-always-wins

| id | title | red → green | deps |
|---|---|---|---|
| **M-10** | One schema — frontmatter sole home of status/supersedes; migrate 3 ADRs (atomic: migrate + flip validate rule + rebuild in one PR) | Before: status split frontmatter vs body bullets. After: single schema, body-bullet form rejected | M-03 |
| **M-11** | Executable ADR supersession + convergence (mechanical consumers only) | Before: nothing flips a superseded ADR; recall's −5 penalty dead. After: `--supersedes` flips frontmatter+edges+index; recall excludes; ADR-vs-§V contradiction **detected**. §V auto-amend marked constitution-blocked/untestable | M-03, M-10 |
| **M-12** | MEMORY.md Decisions/Patterns **projected between delimiter markers** | Before: MEMORY.md says "(none yet)" while 3 ADRs exist. After: rows generated between `<!-- BEGIN:auto -->` markers; hand-written header untouched; single-writer (no dream race) | M-03, M-10 |

### Phase 3 — retrieval that retrieves

| id | title | red → green | deps |
|---|---|---|---|
| **M-13-14** | Kill recall noise floor + index sh/css/html/toml (**together**, rebuild) | Before: unrelated path returns 20 noise lines; no memory can carry a `.sh` path. After: unrelated → 0 lines; `.sh`-referencing entry carries the path | M-03 |
| **M-15-16-17** | Subagent recall scope (task code, not spec markdown) + `--grep` content/trailer recall + reachable archives + `modified:` stamp | Before: subagent recall scoped to markdown; no content search; archives unreachable; mtime recency. After: all four | M-13-14 |

### Phase 4 — multi-year horizon + graph

| id | title | red → green | deps |
|---|---|---|---|
| **M-18** | Deterministic rollup trigger + weekly backfill + period-close regen | Before: `rollup weekly 2026-W25` ignores arg; only dream triggers it. After: weekly CI job + week-boundary fallback; backfills W25–W30; month/quarter regenerate correctly | M-00 |
| **M-20** | Graph: back_ref matcher (ADR-NNNN↔slug) + self-ref fix + `[[slug]]` wikilinks | Before: `verify` reports 9 asymmetries; back_refs empty. After: 0 asymmetries; edges populated; self-edges gone | M-03, M-13-14 |
| **M-21-22** | Deterministic ledger decay + `hot.md` session cache | Before: old `[x]` blocks full-length; no hot cache. After: old blocks collapsed (live untouched); `hot.md` ≤ cap injected at boot | M-00 |
| **M-19** | Separate sleep agent — scheduled dream + same-machine fallback trigger | Before: stale+auth-absent → false success. After: auth-absent → loud fail no stamp; auth-present → spawn attempted. (LLM reconciliation marked untestable-by-rig) | M-01b, M-02, M-18 |

### Phase 5 — brownfield + the promotion that ends the cycle

| id | title | red → green | deps |
|---|---|---|---|
| **M-23-26** | Brownfield: archaeology (ADR backfill / endpoint inventory / SHIPPED reconstruction / hotspots), clean seeding, user-state mirror fix, initiative bootstrap | Before: adopted repo gets factory patterns + dangling index + empty mirror + no STATE. After: framework-scoped seeds, clean index, `CLAUDE_CONFIG_DIR`-correct mirror, bootstrapped STATE | M-08, M-09a, M-13-14 |
| **M-04-promote** | **Promote liveness probes into validate.sh (required) — LAST** | Before: no required liveness gate. After: validate.sh fails on committed-state staleness (env-overridable), real repo green because metabolism now runs. `LIVENESS_SOFT` grace | M-01b, M-02, M-03, M-05b, M-18, M-04 |

---

## 2. Landing order (main stays green at every step)

17 PRs, each a harness-maintenance diff (`.claude`/`.github`/`docs`/`specs` only) mergeable via the evidence-gate `no-ac.json` hatch. The ordering rule the audit omitted: **every validation/liveness gate lands AFTER the thing it checks is already green.**

1. **PR1 · M-00** — CI test runner + dead-test detector. *Nothing below is enforceable until this exists.*
2. **PR2 · M-01a, M-02** — auth/timeout probe (advisory) + record-failure-as-failure. *M-02 first so a failed dream stops reading green.*
3. **PR3 · M-01b** — real spawn fix (the reproduction from PR2 justifies the auth+timeout edit).
4. **PR4 · M-03** — silent no-ops (gates the boot rebuild + all reindex-dependent items).
5. **PR5 · M-04** — liveness probes in **harness-doctor** (advisory, never validate.sh yet).
6. **PR6 · M-05a, M-06** — SessionStart matcher + `/ship`,`/verify` sync wiring (pure settings/skill edits).
7. **PR7 · M-08** — SHIPPED registry + evidence index (**before** the reconcile needs a home).
8. **PR8 · M-07-data, M-07-state** — spec-004 reconcile via `SHIPPED.md`/`[s]` + per-spec STATE filter.
9. **PR9 · M-05b** — boot auto-sync/rebuild/atlas (after M-03 + M-07 so it writes *correct* state).
10. **PR10 · M-07-guard, M-09a** — reverse-drift guard (`push:main` advisory, after the reconcile) + ENDPOINTS scraper.
11. **PR11 · M-10** — one schema (migrate + flip rule + rebuild, atomic).
12. **PR12 · M-11, M-12** — executable supersession + MEMORY.md projection.
13. **PR13 · M-13-14** — recall noise floor + sh-index (together, rebuild).
14. **PR14 · M-15-16-17** — subagent scope + content/trailer/archive recall.
15. **PR15 · M-18, M-20, M-21-22, M-19** — rollup + graph + ledger-decay/hot.md + dream fallback.
16. **PR16 · M-23-26** — brownfield bootstrap (lands with the next adoption).
17. **PR17 (LAST) · M-04-promote** — promote liveness to required `validate.sh`. *Only after the metabolism is proven alive; `LIVENESS_SOFT` grace + branch-local check so this PR proves-green before flipping to hard-fail. This is the item that stops a third audit.*

---

## 3. How each hard-to-test item is actually tested (no real auth in CI)

- **Auth/spawn fix (M-01b), dream-failure (M-02), sleep agent (M-19):** inject a **fake `claude` on `PATH`** (a stub script that echoes a fixture and exits 0 or 1). Assert the spawn seam propagates auth env and that a non-zero exit leaves the state file **unstamped**. No real API call.
- **Liveness probes (M-04 / M-04-promote):** thresholds and target paths read **env-overridable variables** (mirroring `gc-suite.sh`'s `GC_VERIFY_AGE_DAYS`). Tests inject a stale committed fixture (`LIVENESS_INDEX=fixtures/stale-index.jsonl`) and assert red; the real repo passes because the metabolism runs.
- **Latest-wins convergence (M-11):** a fixture ADR reversal → assert the old ADR's frontmatter flips to `superseded`, both edges are written, `memory-recall` excludes it, and the ADR-vs-§V consistency check fires. The §V self-amend and agent-prompt consumers are marked **untestable/constitution-blocked** — the achievable guarantee is *mechanical-consumer* convergence + contradiction *detection*.
- **Rollup backfill (M-18):** `ROLLUP_NOW`/target-week env clock; assert `2026-W25.md` is created from the arg and a month-boundary regenerates the parent with correct counts.
- **Timeout portability (M-01b):** assert the witness runs when `timeout` is absent (unset `PATH` entry in the test).

---

## 4. Open questions (operator input before building)

1. **O-1 (blocks M-01b):** run the exact detached spawn in your real launch context — `nohup bash -c "claude -p 'ok'; echo exit=$?"`. My run today reproduced `Not logged in · exit=1`. Confirm the remedy: `apiKeyHelper`, exported `ANTHROPIC_API_KEY` in the spawn env, or a keychain-ACL grant for detached processes. This is environment-specific and I won't guess it.
2. **O-2 (constitution/hook apply):** M-02/M-03/M-05a edit hooks + settings.json. Hooks are agent-editable but prior audits used a stage-then-operator-install pattern. Which items, if any, need operator/FORCE sign-off before push?
3. **O-3 (spec-004 marker):** `SHIPPED.md` alone, an `[s]` terminal marker, or backfill red/green logs from the PR #13 bundle then `[x]`? Each has different downstream effects on `next-task.sh` counts and the reverse-drift guard.
4. **O-4 (CI STATE writer):** commit STATE.md **pre-merge on the PR branch** (recommended — avoids the empty-`bypass_actors` main-write problem) or provision a bypass actor for a post-merge committer?
5. **O-5 (liveness scope):** confirm clock-relative dream/rollup staleness stays **advisory** (harness-doctor + weekly cron issue), with only **branch-local committed-state** staleness as the required validate.sh gate — otherwise the wedge risk returns.
6. **O-6 (dream reconciliation):** extract ADD/UPDATE/DELETE/NOOP into a deterministic diff script (fixture-testable) or accept it as LLM-behavioral (untested)?

---

## 5. Meta

This review found the audit's own headline root cause wrong — proving the value of not letting the plan's author be its only reviewer. The pattern to internalize: the audit correctly identified the *symptom* (metabolism dead, "Not logged in" in the logs) but reached for a plausible *mechanism* (config-dir) without reproducing it; the real mechanisms (keychain-unreachable-under-nohup + missing `timeout`) needed a live probe to surface. Item **M-01a ships that probe first**, and item **M-04-promote** makes "is the metabolism actually alive?" a required, self-testing gate — so the diagnosis can never again be assertion instead of evidence.
