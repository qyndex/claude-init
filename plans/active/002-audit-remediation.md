---
id: 002
slug: audit-remediation
status: approved
spec: specs/archive/2026-Q3/002-audit-remediation.md
owner: "@claude"
created: 2026-05-29
updated: 2026-05-29
phases: 8
---

# Plan 002: Audit Remediation — Bug fixes, gap closures, claw-code adoptions

> Implementation plan for `specs/archive/2026-Q3/002-audit-remediation.md`. Every plan element traces back to one of 40 acceptance criteria across 8 phases. The plan adds **no new layers** to the harness stack — every change is a surgical edit to an existing `.claude/hooks/*.sh`, `.claude/scripts/*.sh`, `.claude/settings.json`, `.github/workflows/*.yml`, or `.swarms/templates/*.yaml`, plus a small set of new scripts, hooks, agents, skills, and CI workflows enumerated in Dependencies.

## TL;DR

Land every finding from the 2026-05-29 six-agent audit by: (Phase 1) restoring hook block paths to exit 2 with the correct `hookSpecificOutput.permissionDecision` envelope so the two-layer security model actually has two layers; (Phase 2) closing the six critical multi-month-delivery gaps (deploy BYO policy, integration-tests required, merge-gate first-run bounded, cost-cap fail-open, in-flight harness version drift detection, initiative layer); (Phase 3-5) closing 20 significant gaps and 5 security gaps; (Phase 6) adopting 6 claw-code patterns (worker state machine, JSONL lane events, workspace fingerprint, branch freshness, --json diagnostics, anti-slop reviewer); (Phase 7) shipping a constitution compaction skill + cron so CLAUDE.md cannot sprawl past 300 lines; (Phase 8) producing the AC-by-AC REPORT.md.

## Architecture

### Component changes per phase

The 40 ACs reduce to surgical edits of ~20 existing files, 7 new shell scripts, 4 new hooks/agents/skills, 4 new CI workflows or routines, and 2 new doc files. No new harness layer is introduced.

**Phase 1 — Active code bugs (AC-1..AC-7)**

- **`.claude/hooks/stop-verify.sh`** (modify, ~10-line change) — replace the legacy `{"decision":"block","reason":"..."}` block in lines 33-39 with the Claude Code 2.x envelope `{"hookSpecificOutput":{"hookEventName":"Stop","permissionDecision":"deny","permissionDecisionReason":"..."}}` AND change `exit 0` on the block path to `exit 2`. This is the canonical schema already used by `pre-edit-constitution-guard.sh:82` and `pre-bash-guard.sh:94-100`. Backs AC-1.
- **`.claude/hooks/pre-bash-guard.sh`** (modify, 3 line-changes + 8 pattern additions) — at lines 102, 125, 155 the script currently emits a `deny` JSON then `exit 0`; change each to `exit 2` to make the block hard (the `ask` path at line 155 stays `exit 0`). Then extend the `deny_patterns` array (line 25-78) with 8 new patterns covering: `tee +.* +.claude/`, `find +.* +-exec +(sh|bash|zsh)`, `xargs +.* +(sh|bash|zsh)`, and four shell-redirect patterns matching `(>|>>) +(.claude/hooks/|.claude/CLAUDE.md|.claude/settings.json|.github/workflows/)`. Existing chained-segment splitter at line 110 already handles `;`/`&&`/`||`/`|` so the new patterns inherit chain protection. Backs AC-2, AC-5.
- **`.claude/hooks/pre-edit-constitution-guard.sh`** (modify, 5-line hardening) — line 23 currently treats `FORCE_CONSTITUTION_EDIT=1` as sufficient; harden by also requiring a stable per-operator token from `~/.claude/settings.local.json` (gitignored). Logic: if `FORCE_CONSTITUTION_EDIT=1`, read `~/.claude/settings.local.json` `_force_constitution_edit_token` field, compare against `$FORCE_CONSTITUTION_EDIT_TOKEN`; if both present and equal → exit 0; otherwise → continue to deny. Backs AC-4.
- **`.claude/scripts/validate.sh`** (modify, ~8 lines added) — new check category `[force-bypass]` greps for `export[[:space:]]+FORCE_CONSTITUTION_EDIT` across `.claude .github`; non-empty → fail. Also greps MCP entries for bare-name args (no `@<version>`) and `git+https://` patterns. Backs AC-4, AC-29.
- **`.claude/hooks/subagent-stop.sh`** OR **`.claude/hooks/stop-verify.sh`** (modify) — extend the `feature-stream|coordinator` hard-enforce arm at line 58 to fire when the `coordinator` agent stops (today this only fires via `SubagentStop`; the coordinator may also be triggered via direct `claude --bg --agent coordinator` in which case `Stop` runs instead). Decision: keep the enforcement in `subagent-stop.sh` (already correct) and add a parallel branch in `stop-verify.sh` that detects a `coordinator` session-context marker and re-runs the same NEXUS validator. Backs AC-3.
- **`.github/workflows/*.yml`** (modify three workflows) — replace `ludeeus/action-shellcheck@master`, `bridgecrewio/checkov-action@master`, `google/osv-scanner-action/.github/workflows/osv-scanner-reusable.yml@main` with commit-SHA pins. SHAs to be looked up at task time via `gh api repos/<owner>/<repo>/commits/<branch>`. Backs AC-6.
- **`CLAUDE.md`** (modify, single-line edit) — root `CLAUDE.md:91` model-routing entry for `coordinator` and `feature-stream` must read "Sonnet 4.6" (matching `.claude/CLAUDE.md §V` which says they were demoted in Round 5). Backs AC-7.
- **`.claude/scripts/check-doc-consistency.sh`** (NEW, ~40 LOC) — diffs the root `CLAUDE.md` "Agent model assignments" table against `.claude/CLAUDE.md §V`. Exits 0 on match, 1 on drift. Wired into `validate.sh`. Backs AC-7.

**Phase 2 — Critical process gaps (AC-8..AC-13)**

- **`.github/workflows/canary-deploy.yml`** (modify, single header comment + 0 logic change) — prepend `# STUB — replace with project-specific deploy logic; see docs/DEPLOY-INTEGRATION.md`. Backs AC-8.
- **`CLAUDE.md`** (modify, ~3 lines added to "What this repo is" section) — explicit "Deploy pipeline is BYO; harness ships only stubs" sentence with a link to the new `docs/DEPLOY-INTEGRATION.md`. Backs AC-8.
- **`docs/DEPLOY-INTEGRATION.md`** (NEW, ~150 lines) — checklist: env secret map, target platform (Vercel/Fly/k8s/etc.), promotion gates, rollback contract. References `canary-deploy.yml` as the integration point. Backs AC-8.
- **`.github/workflows/ci.yml`** (modify, single-line delete) — remove `continue-on-error: true` at line 118. Backs AC-9.
- **`.github/workflows/merge-gate.yml`** (modify, ~30 lines added) — rework the first-run block at lines 35-38: instead of warn-and-pass when no daily-batch has run, check repo init age (`git log --reverse --format=%aI | head -1` vs `date -u +%s`); if ≤ 7 days, run an inline `semgrep --config=auto .` + `gitleaks detect --no-banner` as the fallback security gate; if > 7 days, fail with explicit instruction to trigger `daily-batch` manually. Backs AC-10.
- **`.claude/routines/overnight-build.yml`** (modify, ~6 lines in the `Monthly cap check` step) — invert the logic at lines 110-113: if `cost-summary.json` missing OR malformed → emit `::warning::cost-summary unavailable; continuing under fail-open posture` and `exit 0` (current behavior aborts the night). The hard-abort path is preserved ONLY when `cost-summary.json` exists AND `remaining < $30`. Backs AC-11.
- **`.claude/hooks/session-heartbeat.sh`** (modify, ~15 lines added) — at the swarm-stream branch (line 110), record `harness_sha = git -C .claude rev-parse HEAD` into `state.json`; on every subsequent turn, compare against `git rev-parse origin/main:.claude` (cached for 5min in `.claude/sessions/<fp>/.harness-sha.cache`). On drift > N commits (default N=10), append a `harness.version.drift` event to `.swarms/events/<stream-id>.jsonl`. Backs AC-12.
- **`initiatives/active/`** + **`initiatives/templates/initiative.md`** (NEW dir + template, ~80 lines template) — frontmatter schema: `id`, `slug`, `status (active|paused|archived)`, `okr`, `owner`, `created`, `target_quarter`, `specs:` (list), `kpi:`. Body sections: Vision, In-scope, Out-of-scope, Constituent specs, KPI tracking. Backs AC-13.
- **`.claude/commands/initiative.md`** (NEW slash-command, ~60 lines) — `/initiative create <slug>` creates `initiatives/active/<NNN>-<slug>.md` from template, writes `.claude/state/current-initiative` (slug only). `/initiative status` lists active initiatives + their child specs. Backs AC-13.
- **`.claude/hooks/session-end.sh`** (modify, ~5 lines) — already reads `.claude/state/current-initiative`; add a write of the initiative slug into the session-end summary (verification only — no behavior change). Backs AC-13.

**Phase 3 — Significant gaps (AC-14..AC-20)**

- **`.github/workflows/stale-spec-check.yml`** (NEW, ~50 lines) — weekly cron job. For each spec under `specs/active/*.md` with `status: approved` AND `updated:` > 30d ago, runs `grep -rE "Spec: specs/active/$(basename $spec)" tasks/TASKS.md | grep '\[x\]' | wc -l`; if zero, appends a stale-spec line to `.claude/memory/MEMORY.md` (under an `## Incidents` rolling log) and opens an issue tagged `stale-spec`. Backs AC-14.
- **`.github/workflows/quarterly-archive.yml`** (modify, ~20 lines) — after each `mv specs/active/<id>... specs/archive/<quarter>/`, runs `sed -i.bak 's|specs/active/<id>|specs/archive/<quarter>/<id>|g' tasks/TASKS.md plans/active/*.md`. Uses the `atomic-write.sh` lib (already present from spec 001). Backs AC-15.
- **`docs/ADOPTION.md`** (NEW, ~150 lines) — the six-phase brownfield adoption flow: (1) reconcile-claude-dir, (2) sentinel-detect-stack, (3) characterization-tests-for-legacy, (4) spec 001 the first feature, (5) verify, (6) graduate. Linked from `CLAUDE.md` "Brownfield adoption" section. Backs AC-16.
- **`.claude/scripts/memory-promote.sh`** (NEW, ~120 LOC) — for each ADR under `.claude/memory/decisions/*.md` with `code_paths:` frontmatter, runs `git log --since=<last_verified> --name-only -- <code_paths>`; if any commits touched the listed paths since `last_verified`, prints `STALE: <adr-path>` and (with `--mark`) appends `last_verified_needs_review: true` to the ADR frontmatter. `--dry-run` mode lists without writing. Wired from `dream-cron.yml:52` (already references this path). Backs AC-17.
- **`.claude/hooks/user-prompt-context.sh`** (modify, ~10 lines deleted) — delete active-spec + active-plan injection (lines 18-34); `workflow-state.sh` (line 51) already injects them in the `<state>` block. Remaining responsibility of `user-prompt-context.sh`: branch + dirty count only. Backs AC-18.
- **`.claude/hooks/workflow-state.sh`** (modify, ~25 lines in phase derivation at lines 41-48) — extend phase detection to all 8 phases:
  - `constitute` — no `.claude/CLAUDE.md` OR no `.claude/skills/constitution/`
  - `specify` — has constitution, no spec OR newest spec has `status: draft` AND no `[OQ]` markers
  - `clarify` — newest spec has `status: draft` AND contains `[OQ]` markers
  - `plan` — newest spec `status: approved`, plan missing or `status: draft`
  - `tasks` — plan `status: approved`, no matching task IDs in TASKS.md
  - `analyze` — TASKS.md has entries for the spec, but `.claude/state/analyze-<spec-id>.json` missing
  - `implement` — analyze marker present, pending `- [ ]` tasks exist
  - `verify-review-ship` — no pending tasks, but `verify/*-<spec-id>/REPORT.md` missing OR not merged
  Same sentinel format `<state>...</state>` preserved. Backs AC-19.
- **`.claude/settings.json`** (modify, ~3 lines in `permissions.allow`) — remove `Bash(gh issue view:*)` (line 148) and `Bash(gh api:*)` (line 156). Replace with `Bash(gh issue create:*)`, `Bash(gh issue comment:*)`, `Bash(gh issue edit:*)` (already present). The constitution §XVI explicitly prohibits reading task state from GitHub API. Backs AC-20.

**Phase 4 — Memory hardening (AC-21..AC-25)**

- **`.claude/hooks/session-start-context.sh`** (modify, ~20 lines added) — at the witness-brief load (line 56), if the latest checkpoint file contains a `(pending)` sentinel as its first line, poll-and-wait up to 90s (sleep 3s × 30 iterations); on timeout, append `witness.timeout` to `.claude/hooks/.log/witness-events.jsonl` and proceed with whatever content exists. Backs AC-21.
- **`.claude/scripts/memory-gc.sh`** (modify, ~40 lines in the `enforce` mode at lines 54-74) — replace `head -n MAX_LINES` truncation (which keeps oldest by file position) with last_accessed-ordered eviction:
  1. Parse `.claude/memory/MEMORY.md` into per-entry blocks (split on `^## ` headers).
  2. For each block, read its `last_accessed:` frontmatter (if missing, use file's mtime as proxy).
  3. Sort blocks by `last_accessed` DESC (newest first), keep first N that fit under `MAX_LINES`.
  4. Atomically rewrite MEMORY.md via `lib/atomic-write.sh`.
  5. Archive evicted blocks to `.claude/memory/.archive/MEMORY-<date>-evicted.md`.
  Backs AC-22.
- **`.claude/commands/dream-review.md`** (NEW slash-command, ~80 lines) — invokes a Sonnet review pass on `.claude/memory.proposed/*.md`. For each proposed file, runs `diff -u .claude/memory/<corresponding-file> .claude/memory.proposed/<file>` (if a corresponding committed file exists) AND extracts removed lines into `.claude/memory.proposed/memory-diff.md` (one section per file). Human-only review; never auto-applies. Backs AC-23.
- **`.claude/skills/dream/SKILL.md`** (modify, ~30 lines added — new step in the dream loop) — after "consolidate" step, add "detect contradictions": group ADRs under `.claude/memory/decisions/` by their `subsystem:` frontmatter; for each subsystem with ≥2 ADRs, prompt the dream agent to compare their `decision:` fields and flag pairs that contradict; output flagged pairs into `.claude/memory.proposed/conflicts.md`. Marked human-review-only. Backs AC-24.
- **`.swarms/templates/handoff.yaml`** (modify, ~6 lines added under a new `tdd_state:` block) — optional fields:
  ```yaml
  tdd_state:
    phase: red          # red | green | refactor | n/a
    last_test_command: "pnpm test --filter web"
    last_test_exit_code: 1
    wip_sha: "7a3f2b1"  # most recent WIP: commit at handoff time
  ```
  Backs AC-25.
- **`.claude/hooks/subagent-stop.sh`** (modify, ~25 lines added) — after the existing YAML parse (line 48), if the agent is `feature-stream` AND the parsed handoff lacks `tdd_state`, auto-populate it by:
  - `last_wip = git log --grep '^WIP:' --format='%H %s' -1` → wip_sha
  - `last_test = grep -E 'tdd-ledger.sh (red|green)' .claude/hooks/.log/bash.log | tail -1` → phase + command + exit_code
  Then re-emit the augmented handoff into the digest. Backs AC-25.

**Phase 5 — Security gap closures (AC-26..AC-30)**

- **`.claude/settings.json`** (modify, ~12 lines) — remove `Write(./**)` blanket at line 47. Replace with explicit per-dir allows:
  ```
  Write(./src/**), Write(./lib/**), Write(./tests/**), Write(./docs/**),
  Write(./verify/**), Write(./specs/**), Write(./plans/**),
  Write(./.swarms/**), Write(./.github/workflows/**),
  Write(./.claude/memory/**), Write(./.claude/memory.proposed/**),
  Write(./initiatives/**), Write(./README.md), Write(./CHANGELOG.md),
  Write(./OVERNIGHT_REPORT.md), Write(./CLAUDE.md)
  ```
  Then extend `.claude/hooks/pre-edit-constitution-guard.sh` deny-list (case block at line 60) to also cover `tasks/TASKS.md`, `specs/active/**` (newly-`approved` specs only — guarded by frontmatter grep), and `plans/active/**` similarly. Justification mechanism: writes to these protected paths require `Edit` tool (not `Write`), which is granular line-level and easier to audit. Backs AC-26.
- **`.claude/hooks/pre-spawn-cost-gate.sh`** (modify, ~15 lines added) — currently the cost-cap branch (lines 67-127) returns early at line 73 unless `cmd` matches `claude --bg/-p/--remote`. Add a pre-check: if `tool_name in (Agent, Task)`, read `cost-summary.json` and apply the same ≥100% deny / ≥90% ask logic on a PER-SESSION subagent-count counter (file: `.claude/hooks/.log/.subagent-spawn-count-<session_id>`). Hard ceiling: 10 subagent spawns per session under default cap. Backs AC-27.
- **`.claude/scripts/install-plugins.sh`** (modify, ~30 lines added) — for each `claude plugin install <name>@<marketplace>` line, add a preceding `claude plugin install <name>@<marketplace>@<version-pin>` (use the locked SHAs to be captured at task time from each marketplace's manifest). Add a provenance check before adding a marketplace: `gh repo view <marketplace-org>/<repo> --json owner,stargazerCount,createdAt --jq '...'`; fail with a clear warning if the repo is < 30 days old OR has < 50 stars (configurable via env). Backs AC-28.
- **`.claude/CLAUDE.md §X`** (modify, ~5 lines added) — note: "Plugins are an unverified supply chain unless pinned to a version and provenance-verified at install time. See `install-plugins.sh` for the integrity check." Backs AC-28.
- **`.mcp.json`** (modify, ~3 entries pinned) — `context7` (line 131-136) and the `_disabled_examples` `replicate` entry get explicit `@<version>` suffixes. The `osv` entry's `git+https://` is grandfathered with an inline comment justifying the install path (no npm package available) AND a manually-pinned tag (`@v0.1.0` — already present). Backs AC-29.
- **`.claude/hooks/pre-write-secret-scan.sh`** (modify, ~15 lines added in the PII scrubber case block) — extend coverage from `.claude/memory/**` to also `OVERNIGHT_REPORT.md`, `verify/**/*.log`, `verify/**/REPORT.md`. The scrubber logic (regex on email, phone, SSN, IPs) is unchanged — only the path glob expands. Backs AC-30.

**Phase 6 — claw-code adoptions (AC-31..AC-36)**

- **`.swarms/streams/<id>/state.json`** (schema-only — written by `session-heartbeat.sh`) — already partially implemented (line 102-138 of `session-heartbeat.sh`). Extend with `fingerprint` field (WORKSPACE_FP from line 31), and codify the valid-state enum (`spawning|trust_required|ready_for_prompt|prompt_accepted|running|finished|failed`) AND the transition rules: only the coordinator may transition into `spawning|trust_required|ready_for_prompt|prompt_accepted`; heartbeat may transition `prompt_accepted → running`; `subagent-stop.sh` may transition into `finished|failed`. Backs AC-31.
- **`.claude/agents/core/coordinator.md`** (modify, ~10 lines added under "Workflow") — explicit instruction: before dispatching any prompt to a stream, read `.swarms/streams/<stream-id>/state.json`; only dispatch if `.state == "ready_for_prompt"`; otherwise log and skip. Backs AC-31.
- **`.swarms/events/<stream-id>.jsonl`** (schema-only — written by `post-bash-log.sh` and `subagent-stop.sh`) — already partially implemented. Codify the event schema:
  ```
  {ts, stream_id, event, payload: { command?, exit_code?, status?, session_id? }, error?: { kind, retryable } }
  ```
  Event enum: `lane.started | lane.blocked | lane.red | lane.green | lane.commit.created | lane.finished | harness.version.drift | workspace.mismatch | branch.stale_against_main`. `error.kind` enum: `filesystem | auth | session | parse | runtime | mcp | delivery | usage | policy`. `retryable: bool`. Backs AC-32.
- **`.claude/hooks/post-bash-log.sh`** (modify, ~15 lines added) — extend the existing lane-event emitter (lines 46-76) with the new event types: emit `lane.started` on the first non-`*help*` command after a worktree's `state` transitions to `running`; emit `lane.commit.created` on detection of `git commit` exit 0; populate `error.kind` from a coarse classifier (grep stderr for "ENOENT|EACCES|permission denied" → filesystem; "401|403|unauthor" → auth; "syntax error|unexpected" → parse; etc.) and `retryable: true` for `mcp|delivery|filesystem` kinds. Backs AC-32.
- **`.claude/scripts/requeue-failed.sh`** (modify, ~40 lines rewritten) — replace the awk-on-TASKS.md scraping with a JSONL reader: for each `.swarms/events/<id>.jsonl`, find the last `lane.finished` or `lane.failed` event per stream; if `retryable: true`, surface in the report as "auto-retryable"; otherwise as "manual review". Backs AC-32.
- **`.claude/hooks/session-heartbeat.sh`** (modify, ~10 lines added) — emit `workspace.mismatch` lane event when `WORKSPACE_FP` from current `pwd -P` doesn't match the fingerprint recorded in `.swarms/streams/<id>/state.json`. Backs AC-33.
- **`.claude/scripts/verify.sh`** (modify, ~15 lines added at the top, before stack detection) — branch-freshness preflight: `git fetch --quiet origin main 2>/dev/null && git merge-base --is-ancestor HEAD origin/main || warn "branch is N commits behind origin/main"`. Honor `SKIP_BRANCH_CHECK=1`. On stale (>20 commits behind), emit `branch.stale_against_main` event into `.swarms/events/<stream-id>.jsonl` if inside a swarm stream. Backs AC-34.
- **`.claude/scripts/harness-doctor.sh`** (NEW, ~250 LOC) — extract the logic currently described in `.claude/commands/harness-doctor.md` into an executable script. Accepts `--json` flag emitting per-check `{"check":"...","status":"pass|fail|warn","detail":"..."}` array. Default mode: human-readable. Backed by the same 14 categories as `validate.sh` plus 5 doctor-specific checks (autopilot artifacts, swarm state, memory budget, security invariants, doc-claims). Backs AC-35.
- **`.github/workflows/harness-validate.yml`** (modify if exists, NEW if not, ~30 lines) — adds a step `bash .claude/scripts/harness-doctor.sh --json > verify/doctor-$(date -I).json` and uploads as artifact. Backs AC-35.
- **`.claude/agents/quality/anti-slop-reviewer.md`** (NEW agent, ~80 lines) — Sonnet 4.6 (per §V routing). System prompt: classify the PR body into one of `actionable-bug | actionable-docs | duplicate | generated-slop | spam | security-sensitive | not-reproducible | externally-blocked`. Output JSON `{class, confidence, rationale}`. Backs AC-36.
- **`.github/workflows/pr-review.yml`** (modify, ~15 lines added — or NEW workflow if missing) — invoke the anti-slop agent on every PR open, post the classification as a sticky PR comment. Header comment: `# WARN-ONLY: block after 30-day burn-in (uncomment classifier-gate step below).` Backs AC-36.

**Phase 7 — Meta-evolution discipline (AC-37)**

- **`.claude/skills/constitution-compact/SKILL.md`** (NEW skill, ~80 lines) — quarterly compaction process. Steps: (1) extract every "Round N" patch into a corresponding archived ADR under `.claude/memory/decisions/`; (2) consolidate the resolved patches into the named principle they amend; (3) re-flow body to ≤ 300 lines; (4) write a structured diff to `.claude/memory.proposed/constitution-diff.md`. **Human-review only — never auto-applies.** Backs AC-37.
- **`.claude/routines/constitution-compact-cron.yml`** (NEW routine, ~30 lines) — quarterly cron (15th of Jan/Apr/Jul/Oct at 06:00 UTC). Invokes the `constitution-compact` skill in dry-run mode. Emits the proposal but blocks at the `human-review-required` checkpoint (writes to `.claude/memory.proposed/constitution-diff.md` and tags `@shravan` in a PR comment). Backs AC-37.
- **`.claude/scripts/validate.sh`** (modify, ~5 lines added) — new check category `[constitution-size]` — fails if `wc -l < .claude/CLAUDE.md` > 300. Backs AC-37.

**Phase 8 — Exit gates (AC-38..AC-40)**

- **`verify/2026-05-29-002/validate-exit.log`** (NEW evidence artifact) — captured by running `bash .claude/scripts/validate.sh > verify/2026-05-29-002/validate-exit.log 2>&1` after Phase 7 ships, diffed against `verify/2026-05-29/T-056/green.log`. Backs AC-38.
- **`verify/2026-05-29-002/doctor-exit.json`** (NEW evidence artifact) — `bash .claude/scripts/harness-doctor.sh --json > verify/2026-05-29-002/doctor-exit.json`. Backs AC-39.
- **`verify/2026-05-29-002/REPORT.md`** (NEW evidence artifact) — assembled by `bash .claude/scripts/collect-evidence.sh 002` (already exists). Must contain the 40-row AC table, classifier-deny counts (or N/A if T-057 driver not run), operator-intervention totals, rollback recommendation block. Backs AC-40.

### Data flow

```mermaid
sequenceDiagram
  participant Op as Operator/Autopilot
  participant Stop as Stop hook
  participant Bash as PreBash hook
  participant Cost as Cost-gate hook
  participant FS as Filesystem
  participant Lane as .swarms/events/*.jsonl
  participant State as .swarms/streams/*/state.json
  participant Coord as Coordinator agent

  Note over Stop: AC-1: emit hookSpecificOutput + exit 2 on block
  Op->>Stop: Stop event w/ unverified prod changes
  Stop-->>Op: {permissionDecision: deny} + exit 2 (BLOCKED)

  Note over Bash: AC-2 + AC-5: exit 2 + 8 new deny patterns
  Op->>Bash: tee secrets to .claude/hooks/x.sh
  Bash-->>Op: {permissionDecision: deny} + exit 2

  Note over Cost: AC-27: cost cap now covers Agent/Task tools
  Op->>Cost: spawn 11th Agent under low cap
  Cost-->>Op: {permissionDecision: deny}

  Note over State,Coord: AC-31: coordinator gates on state.state
  Coord->>State: read .swarms/streams/feat-005/state.json
  State-->>Coord: {state: "spawning"}
  Coord-->>Op: defer dispatch; do not send prompt yet

  Op->>FS: tdd-ledger.sh red
  FS->>Lane: append lane.red event w/ error.kind classification
  Note over Lane: AC-32: typed events drive requeue-failed.sh
```

## Data model

This harness has no application database. "Data model" = file schemas.

### `.swarms/streams/<stream-id>/state.json` (AC-31, partial existing)

| Field | Type | Required | Notes |
|---|---|---|---|
| `stream_id` | string | yes | matches `feat-<slug>` pattern |
| `state` | enum | yes | `spawning|trust_required|ready_for_prompt|prompt_accepted|running|finished|failed` |
| `session_id` | string | yes | `CLAUDE_SESSION_ID` of the owning session |
| `updated` | ISO8601 | yes | last write timestamp |
| `worktree` | string | yes (new) | absolute path; written by coordinator on spawn |
| `fingerprint` | string (16-hex) | yes (new) | `WORKSPACE_FP` (md5 of resolved cwd, first 16 chars) |
| `harness_sha` | string (40-hex) | yes (new) | git SHA of `.claude/` at session-start, for AC-12 drift detection |

Transitions:
```
spawning → trust_required → ready_for_prompt → prompt_accepted → running → finished
                                                                       ↘ failed
```
Only the coordinator may write the first four states; heartbeat may write `running`; `subagent-stop.sh` may write `finished|failed`. Writes are atomic via `lib/atomic-write.sh` (already present from spec 001).

### `.swarms/events/<stream-id>.jsonl` (AC-32, partial existing)

Append-only newline-delimited JSON. One event per line. Schema:

```json
{
  "ts": "2026-05-29T14:23:11Z",
  "stream_id": "feat-005",
  "event": "lane.red",
  "payload": { "command": "pytest tests/auth", "exit_code": 1 },
  "error": { "kind": "runtime", "retryable": false }
}
```

`event` enum:
- `lane.started` — first non-help bash command after `state → running`
- `lane.blocked` — explicit `LANE_BLOCKED` marker in command
- `lane.red` — `tdd-ledger.sh red`
- `lane.green` — `tdd-ledger.sh green`
- `lane.commit.created` — `git commit` exit 0
- `lane.finished` — emitted by `subagent-stop.sh` on stream stop
- `harness.version.drift` — AC-12
- `workspace.mismatch` — AC-33
- `branch.stale_against_main` — AC-34

`error.kind` enum: `filesystem | auth | session | parse | runtime | mcp | delivery | usage | policy`
`error.retryable: bool` — read by `requeue-failed.sh` to decide auto-retry vs manual surface

### `.swarms/templates/handoff.yaml` additions (AC-25)

New optional block, slotted after the `verification` section:

```yaml
tdd_state:                       # optional; populated by subagent-stop.sh for feature-stream
  phase: red                     # red | green | refactor | n/a
  last_test_command: "pnpm test --filter web"
  last_test_exit_code: 1
  wip_sha: "7a3f2b1"             # most recent WIP: commit at handoff time
```

### `initiatives/active/<NNN>-<slug>.md` (AC-13)

Frontmatter:
```yaml
id: 001
slug: harness-factory-readiness
status: active                   # active | paused | archived
okr: KR-2026Q3-HARNESS-FACTORY-FITNESS
owner: "@shravan"
human_owner: "@shravan"
created: 2026-05-29
target_quarter: 2026Q3
specs:
  - 001-harness-hardening
  - 002-audit-remediation
kpi:
  name: harness_factory_fitness_score
  baseline: "6 active bugs + 6 critical gaps + 20 significant gaps"
  target: "0 active bugs + 0 critical gaps + 0 significant gaps"
```

Body sections: Vision, In-scope, Out-of-scope, Constituent specs (links), KPI tracking (manual updates per quarter).

### `verify/2026-05-29-002/REPORT.md` (AC-40)

Required sections:
1. `## AC pass/fail table` — 40 rows, columns `AC-ID | Title | Status | Evidence path`
2. `## Classifier denies` — count of `permissionDecision: deny` events from `.claude/hooks/.log/bash.log` during the test window (or `N/A — paired-regression driver not run`)
3. `## Operator interventions` — manual approve count for `ask`-tier prompts
4. `## Rollback recommendation` — `NONE | PARTIAL (phases X..Y) | FULL` based on any CRITICAL AC failure
5. `## Sign-off` — `@shravan` line with date

## API contracts

This harness's "API" = hook stdin/stdout JSON contracts.

### `stop-verify.sh` new output schema (AC-1)

Stdin: standard Stop hook payload (no fields needed).

Stdout on block (replaces lines 33-39):
```json
{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Production files changed but no recent verification report (verify/*/REPORT.md from the last 24h). Run /verify before ending. To override: re-send your last message."
  }
}
```
Exit code: `2` (was 0). Stdout on continue: empty, exit 0.

### `pre-bash-guard.sh` new deny patterns (AC-5)

Eight new entries appended to `deny_patterns` array:
```
'tee +(-a +)?.claude/'
'find +.*-exec +(sh|bash|zsh) '
'find +.*-exec +(sh|bash|zsh)$'
'xargs +.*(sh|bash|zsh) '
'>+ +.claude/hooks/'
'>+ +.claude/CLAUDE\.md'
'>+ +.claude/settings\.json'
'>+ +.github/workflows/'
```
Each segment of the chained command is checked independently (existing splitter at line 110). Match → emit `permissionDecision: deny` (existing JSON envelope at lines 117-124), `exit 2`.

### `pre-spawn-cost-gate.sh` new trigger (AC-27)

Currently lines 22-65 handle `Agent|Task` for prompt-size only. Add cost-cap check inside the same `if [ "$tool_name" = "Agent" ] || [ "$tool_name" = "Task" ]`:

```pseudo
spawn_count_file=".claude/hooks/.log/.subagent-spawn-count-${session_id}"
spawn_count=$(cat "$spawn_count_file" 2>/dev/null || echo 0)
spawn_count=$((spawn_count + 1))
echo "$spawn_count" > "$spawn_count_file"

if [ "$spawn_count" -gt 10 ] AND cost_pct >= 90: emit deny + exit 0
elif cost_pct >= 100: emit deny + exit 0
elif cost_pct >= 90 OR spawn_count > 5: emit ask + exit 0
```

### `session-heartbeat.sh` new state.json writes (AC-31, AC-33)

Currently writes `state.json` at lines 125-138 with fields `stream_id, state, session_id, updated, states`. Add: `worktree` (resolved cwd), `fingerprint` (`WORKSPACE_FP`), `harness_sha` (`git -C .claude rev-parse HEAD`).

On every turn, compare `harness_sha` against `git rev-parse origin/main:.claude` (cached 5min); on drift > 10 commits, append a lane event:
```json
{"ts":"...","stream_id":"feat-005","event":"harness.version.drift","payload":{"local_sha":"...","main_sha":"...","drift_count":12}}
```

### `post-bash-log.sh` new JSONL emission format (AC-32)

Extend existing emission (lines 64-74). New `error` block on failure (`exit_code != 0`):
```json
{
  "ts": "...",
  "stream_id": "feat-005",
  "event": "lane.red",
  "payload": {"command":"pytest tests/auth", "exit_code":1},
  "error": {"kind":"runtime", "retryable": false}
}
```
`error.kind` classifier (pseudocode):
```
case stderr:
  *"ENOENT"|*"EACCES"|*"permission denied"*) kind="filesystem"; retryable=true ;;
  *"401"*|*"403"*|*"unauthor"*|*"AuthenticationError"*) kind="auth"; retryable=false ;;
  *"syntax error"*|*"unexpected token"*) kind="parse"; retryable=false ;;
  *"ECONNREFUSED"*|*"timeout"*|*"ETIMEDOUT"*) kind="delivery"; retryable=true ;;
  *"MCP"*|*"mcp_"*) kind="mcp"; retryable=true ;;
  *"rate limit"*|*"429"*) kind="usage"; retryable=true ;;
  *"policy"*|*"forbidden by hook"*) kind="policy"; retryable=false ;;
  *) kind="runtime"; retryable=false ;;
```

## Dependencies (new files created)

This harness has no language packages. "Dependencies" = new shell scripts, hooks, agents, skills, routines, CI workflows, and doc files.

### Phase 1 (new files: 2)
- `.claude/scripts/check-doc-consistency.sh` — diffs root vs constitution model-routing tables (AC-7).
- `verify/2026-05-29-002/T-AC-5-bypass-fixtures.sh` — 8-case bypass-attempt regression fixture (AC-5 evidence).

### Phase 2 (new files: 4)
- `docs/DEPLOY-INTEGRATION.md` — BYO deploy checklist (AC-8).
- `initiatives/templates/initiative.md` — initiative frontmatter template (AC-13).
- `initiatives/active/.gitkeep` — directory marker (AC-13).
- `.claude/commands/initiative.md` — `/initiative create|status` slash-command (AC-13).

### Phase 3 (new files: 3)
- `.github/workflows/stale-spec-check.yml` — weekly stale-spec cron (AC-14).
- `docs/ADOPTION.md` — brownfield six-phase adoption flow (AC-16).
- `.claude/scripts/memory-promote.sh` — ADR staleness flagger (AC-17).

### Phase 4 (new files: 1)
- `.claude/commands/dream-review.md` — `/dream-review` slash-command (AC-23).

### Phase 5 (new files: 0)
All changes are modifications to existing files.

### Phase 6 (new files: 3)
- `.claude/scripts/harness-doctor.sh` — executable doctor script with `--json` mode (AC-35).
- `.github/workflows/harness-validate.yml` — uploads doctor JSON as artifact (AC-35; create if absent).
- `.claude/agents/quality/anti-slop-reviewer.md` — eight-class PR triage agent (AC-36).

### Phase 7 (new files: 2)
- `.claude/skills/constitution-compact/SKILL.md` — compaction process skill (AC-37).
- `.claude/routines/constitution-compact-cron.yml` — quarterly cron routine (AC-37).

### Phase 8 (new files: 3 evidence artifacts only)
- `verify/2026-05-29-002/validate-exit.log`
- `verify/2026-05-29-002/doctor-exit.json`
- `verify/2026-05-29-002/REPORT.md`

**Total new files: 18 (excluding evidence artifacts and `.gitkeep`).**

## Phasing

Phases match the spec exactly. Each phase is independently committable to main; within each phase, the sequence is text/doc edits → JSON/YAML edits → shell logic → CI workflow changes (lowest-risk first).

### Phase 1 — Active code bugs

**Exit criteria** (verbatim from spec AC-1..AC-7):
```bash
# AC-1
test -f verify/2026-05-29-002/T-AC-1-stop-verify-block.log && \
  grep -q 'permissionDecision":[[:space:]]*"deny"' verify/2026-05-29-002/T-AC-1-stop-verify-block.log
# AC-2
[ "$(printf '{"tool_input":{"command":"rm -rf /tmp/x"}}' | bash .claude/hooks/pre-bash-guard.sh; echo $?)" = "2" ]
# AC-3
# coordinator Stop w/o NEXUS block exits 2 (synthetic)
# AC-4
[ "$(grep -rE 'export[[:space:]]+FORCE_CONSTITUTION_EDIT' .claude .github | wc -l)" = "0" ]
# AC-5
bash verify/2026-05-29-002/T-AC-5-bypass-fixtures.sh   # all 8 cases exit non-zero
# AC-6
[ "$(grep -rE '@(main|master)\b' .github/workflows/ | wc -l)" = "0" ]
# AC-7
bash .claude/scripts/check-doc-consistency.sh
```

Sequence within phase:
1. Edit root `CLAUDE.md:91` to align model-routing table (AC-7 text).
2. Add header `# STUB —` to `canary-deploy.yml` (deferred to Phase 2 but cheap text).
3. Modify `stop-verify.sh` JSON envelope + exit code (AC-1).
4. Modify `pre-bash-guard.sh` exit codes + add 8 deny patterns (AC-2, AC-5).
5. Modify `pre-edit-constitution-guard.sh` for hardened bypass (AC-4).
6. Modify `subagent-stop.sh`/`stop-verify.sh` for coordinator enforcement (AC-3).
7. Pin three GH Actions to SHAs (AC-6).
8. New `check-doc-consistency.sh` + extend `validate.sh` (AC-7, AC-4 enforcement).
9. Write `T-AC-5-bypass-fixtures.sh` + capture `T-AC-1-stop-verify-block.log`.

### Phase 2 — Critical process gaps

**Exit criteria** (AC-8..AC-13):
```bash
# AC-8
test -f docs/DEPLOY-INTEGRATION.md && grep -q 'STUB' .github/workflows/canary-deploy.yml
# AC-9
[ "$(grep -A2 'integration' .github/workflows/ci.yml | grep -c 'continue-on-error: true')" = "0" ]
# AC-10
# synthetic: empty daily-batch history → merge-gate runs inline semgrep + gitleaks
# AC-11
rm -f .claude/hooks/.log/cost-summary.json && \
  bash .claude/routines/overnight-build.yml dry-run-monthly-cap-check ; [ $? = 0 ]
# AC-12
# integration: bump .claude/VERSION mid-stream → harness.version.drift event in jsonl
# AC-13
/initiative create test-initiative && \
  test -f initiatives/active/*-test-initiative.md && \
  test -f .claude/state/current-initiative
```

Sequence:
1. Edit `ci.yml` to remove `continue-on-error: true` (AC-9 — single line).
2. Write `docs/DEPLOY-INTEGRATION.md`, add header to `canary-deploy.yml`, update root `CLAUDE.md` (AC-8).
3. Edit `overnight-build.yml` Monthly cap check fallback inversion (AC-11).
4. Edit `merge-gate.yml` first-run bounded fallback + inline scan (AC-10).
5. Edit `session-heartbeat.sh` for `harness_sha` + drift check (AC-12).
6. Create `initiatives/{active,templates}/`, write template, write `/initiative` command, update `session-end.sh` (AC-13).

### Phase 3 — Significant gaps

**Exit criteria** (AC-14..AC-20):
```bash
# AC-14 — synthetic stale-spec fixture flags as stale (semantic check)
# AC-15
# synthetic quarterly-archive run → grep -c 'specs/active/<archived-id>' tasks/TASKS.md returns 0
# AC-16
test -f docs/ADOPTION.md && [ "$(wc -l < docs/ADOPTION.md)" -ge 100 ]
# AC-17
bash .claude/scripts/memory-promote.sh --dry-run ; [ $? = 0 ]
# AC-18
# synthetic prompt → additionalContext mentions active-spec exactly once
# AC-19
# 8 synthetic fixtures (one per phase) → each emits matching phase string
# AC-20
[ -z "$(jq '.permissions.allow[]' .claude/settings.json | grep -E 'gh (issue view|api)')" ]
```

Sequence:
1. Edit `.claude/settings.json` to remove `gh issue view` + `gh api` allows (AC-20 — text).
2. Edit `user-prompt-context.sh` to remove dedup (AC-18 — delete lines).
3. Write `docs/ADOPTION.md` (AC-16).
4. Edit `workflow-state.sh` for 8-phase derivation (AC-19).
5. Write `memory-promote.sh` (AC-17).
6. Write `stale-spec-check.yml` workflow (AC-14).
7. Edit `quarterly-archive.yml` cross-reference rewrite (AC-15).

### Phase 4 — Memory hardening

**Exit criteria** (AC-21..AC-25):
```bash
# AC-21 — synthetic slow witness → session-start waits then loads
# AC-22 — synthetic 250-entry MEMORY.md with newest 50 at bottom → after gc the newest 50 survive
# AC-23
test -f .claude/memory.proposed/memory-diff.md
# AC-24 — synthetic 2-decision fixture → conflicts.md flags the pair
# AC-25 — interrupted mid-red feature-stream → handoff.tdd_state.phase == "red"
```

Sequence:
1. Edit `handoff.yaml` template (AC-25 — text only).
2. Edit `session-start-context.sh` for witness polling (AC-21).
3. Edit `memory-gc.sh` for last_accessed eviction (AC-22 — careful; uses atomic-write).
4. Write `/dream-review` command (AC-23).
5. Edit `dream` skill for contradiction detection (AC-24).
6. Edit `subagent-stop.sh` to auto-populate `tdd_state` (AC-25).

### Phase 5 — Security gap closures

**Exit criteria** (AC-26..AC-30):
```bash
# AC-26 — synthetic agent Write tasks/TASKS.md → blocked OR requires approval
# AC-27 — spawn 11th Agent under MONTHLY_CAP_USD=1 → blocked
# AC-28
grep -c 'claude plugin install [^ ]*$' .claude/scripts/install-plugins.sh   # → 0 (every line pinned)
# AC-29
bash .claude/scripts/validate.sh 2>&1 | grep -cE '(@latest|bare-name MCP)'   # → 0
# AC-30 — synthetic Write of user@example.com to OVERNIGHT_REPORT.md → scrubbed
```

Sequence:
1. Edit `.mcp.json` to pin `context7`, `replicate` (AC-29 — text).
2. Edit `validate.sh` for `@latest` + bare-name + `git+https://` flags (AC-29 — already partial from Phase 1).
3. Edit `pre-write-secret-scan.sh` PII scrubber path expansion (AC-30).
4. Edit `install-plugins.sh` for version pins + provenance check (AC-28).
5. Edit `pre-spawn-cost-gate.sh` for Agent/Task cost cap (AC-27).
6. Edit `settings.json` to narrow `Write(./**)` + extend constitution-guard deny-list (AC-26 — highest blast radius; ship last in phase).

### Phase 6 — claw-code adoptions

**Exit criteria** (AC-31..AC-36):
```bash
# AC-31 — coordinator does not dispatch until state.state == "ready_for_prompt"
# AC-32 — failing stream → parseable JSONL; requeue-failed.sh identifies retryable
# AC-33 — two worktrees → two distinct .claude/sessions/<fp>/ dirs
# AC-34 — 40-commits-behind branch → warning emitted
# AC-35
bash .claude/scripts/harness-doctor.sh --json | jq .   # parses
# AC-36 — synthetic PRs in each of 8 classes → matching classification
```

Sequence:
1. Edit `handoff.yaml` already updated in Phase 4; no overlap.
2. Edit `session-heartbeat.sh` for fingerprint + worktree + harness_sha (AC-31, AC-33; Phase 2 already touched this — coordinate squash).
3. Edit `coordinator.md` agent for state-gate dispatch (AC-31).
4. Edit `post-bash-log.sh` for new event types + error.kind (AC-32).
5. Rewrite `requeue-failed.sh` to read JSONL (AC-32).
6. Edit `verify.sh` for branch-freshness preflight (AC-34).
7. Write `harness-doctor.sh` + extend `harness-validate.yml` (AC-35).
8. Write `anti-slop-reviewer.md` agent + edit `pr-review.yml` (AC-36).

### Phase 7 — Meta-evolution discipline

**Exit criteria** (AC-37):
```bash
[ "$(wc -l < .claude/CLAUDE.md)" -le 300 ]
test -f .claude/skills/constitution-compact/SKILL.md
test -f .claude/routines/constitution-compact-cron.yml
# dry-run produces .claude/memory.proposed/constitution-diff.md without modifying .claude/CLAUDE.md
```

Sequence:
1. Write `constitution-compact` skill.
2. Write `constitution-compact-cron.yml` routine.
3. Edit `validate.sh` for 300-line cap check.
4. Run skill once manually to produce the first proposal; human reviews and merges via PR to bring `.claude/CLAUDE.md` under 300 lines.

### Phase 8 — Exit gates

**Exit criteria** (AC-38..AC-40):
```bash
# AC-38
bash .claude/scripts/validate.sh > verify/2026-05-29-002/validate-exit.log 2>&1 ; \
  diff <(grep -c '✗' verify/2026-05-29-002/validate-exit.log) \
       <(grep -c '✗' verify/2026-05-29/T-056/green.log) | grep -q '^$'
# AC-39
[ "$(bash .claude/scripts/harness-doctor.sh --json | jq '[.[] | select(.status=="fail")] | length')" = "0" ]
# AC-40
test -f verify/2026-05-29-002/REPORT.md && \
  for ac in AC-1 AC-2 ... AC-40; do grep -q "$ac" verify/2026-05-29-002/REPORT.md || exit 1; done
```

Sequence:
1. Run full `validate.sh`, archive to `verify/2026-05-29-002/validate-exit.log`.
2. Run `harness-doctor.sh --json`, archive to `verify/2026-05-29-002/doctor-exit.json`.
3. Run `collect-evidence.sh 002`, finalize `REPORT.md`.

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| AC-1/AC-2 exit-code change breaks existing hook tests | M | H | Run `.claude/scripts/test/pre-bash-guard*.sh` after each pattern addition; add a regression-fixture test for `stop-verify.sh` block path before the change lands. |
| AC-26 `Write(./**)` narrowing blocks legitimate agent writes overnight | M | H | Ship enumerated allow-list with 14 explicit paths covering the 95th-percentile of agent writes (see Phase 5 component spec); keep a single `Write(./.claude/state/**)` and `Write(./tmp/**)` as agent-scratch fallback; monitor classifier-deny rate for 48h post-deploy via `verify/2026-05-29-002/T-AC-26-write-deny-rate.log`. Auto-rollback trigger: deny-rate > 5/h. |
| AC-22 memory-gc eviction-order change corrupts MEMORY.md in production | M | H | Wrap rewrite in `lib/atomic-write.sh`; always archive evicted blocks to `.claude/memory/.archive/MEMORY-<date>-evicted.md` BEFORE the truncation write; ship a `--dry-run` mode and exercise it in CI before any `enforce` run. |
| AC-32 JSONL emission adds perceptible latency to fast bash commands | L | M | Emission is append-only with `O_APPEND` (atomic on local FS); benchmark with `time` on 100 sequential commands before/after; target: < 5ms added p95. If exceeded, defer error.kind classification to an async hook. |
| AC-37 constitution compaction auto-applies despite human-review gate | L | CRITICAL | Skill explicitly writes to `.claude/memory.proposed/constitution-diff.md` only; cron routine has no Write permission on `.claude/CLAUDE.md` (protected by `pre-edit-constitution-guard.sh`); skill body has the assertion "NEVER mv this proposal into place — human PR only" in two locations. |
| AC-12 harness drift check spams events when developing the harness itself | M | L | Drift threshold N=10 commits (not 1); cached 5-min per session; events go to `.swarms/events/*.jsonl` only (not the session transcript), so noise stays out of the prompt context. |
| AC-27 subagent cost cap blocks legitimate large-scale verifier runs | L | M | Default ceiling is 10/session under low cap; raise to 30/session when `cost_pct < 50%`; honor `SUBAGENT_SPAWN_CAP` env override. |
| Coordinator NEXUS check (AC-3) breaks existing direct `claude --bg --agent coordinator` invocations that don't emit handoffs | M | M | Phase 1 ships the check as warn-only for the first 7 days; flip to block via env var `COORDINATOR_NEXUS_BLOCK=1` after burn-in. Document in `.claude/agents/core/coordinator.md`. |
| Phase 5 `.mcp.json` pin changes break a working dev environment | L | M | Pin to the EXACT version each entry is running today (queried via `npm view <pkg> version` / `pip show` per Round 8 A constraint); no upgrades in this phase; upgrades are spec 006 (cost observability) territory. |

## Rollback

Per-phase rollback procedure (each phase is independently ship-able, so any phase can roll back without affecting prior phases):

- **Phase 1**: `git revert <sha-range>`; `validate.sh` returns to spec-001 baseline.
- **Phase 2**: revert workflow + routine files; `initiatives/` dir can be left in place (harmless if empty).
- **Phase 3**: revert `settings.json` `gh` allow-list change last (lowest-risk first means it's also easiest to undo); revert `workflow-state.sh` to 5-phase derivation; the new `stale-spec-check.yml` can be disabled via `gh workflow disable stale-spec-check.yml`.
- **Phase 4**: revert `memory-gc.sh` to head-truncation (the eviction-order change is the only one with data-loss risk; the archive backup at `.claude/memory/.archive/MEMORY-<date>-evicted.md` allows recovery); other Phase 4 changes are read-mostly.
- **Phase 5**: revert `.claude/settings.json` (`Write(./**)` restoration); revert MCP pins; the cost cap and PII scrubber expansions are safe to leave in place.
- **Phase 6**: `git revert` the `harness-doctor.sh` and `anti-slop-reviewer.md`; the lane-events schema additions are backwards-compatible (consumers tolerate missing fields).
- **Phase 7**: revert the skill + routine; the 300-line cap check in `validate.sh` becomes a no-op once the constitution is shrunk; if a rewrite was applied to `.claude/CLAUDE.md`, revert the rewrite commit (the original is preserved in git history).
- **Phase 8**: rollback = re-run `collect-evidence.sh 002` after fixing the failing AC.

Auto-rollback trigger (from spec Rollout): any AC-1..AC-7 fix introducing a NEW `pre-bash-guard` bypass → revert Phase 1; `UserPromptSubmit p95 > 1s` after AC-18 → revert that single hook edit; `validate.sh` fail count > pre-phase1 baseline → halt phase progression and triage.

## Observability

New events emitted (logged to `.claude/hooks/.log/` or `.swarms/events/`):

- **`witness.timeout`** (`.claude/hooks/.log/witness-events.jsonl`) — when `session-start-context.sh` polls 90s without the witness brief settling (AC-21).
- **`harness.version.drift`** (`.swarms/events/<id>.jsonl`) — when a swarm stream's `.claude/` SHA diverges > 10 commits from `origin/main` (AC-12).
- **`workspace.mismatch`** (`.swarms/events/<id>.jsonl`) — when `WORKSPACE_FP` of current `pwd -P` ≠ recorded fingerprint (AC-33).
- **`branch.stale_against_main`** (`.swarms/events/<id>.jsonl`) — when `verify.sh` preflight detects > 20 commits behind (AC-34).
- **`lane.commit.created`**, **`lane.started`** (`.swarms/events/<id>.jsonl`) — new event types (AC-32).
- **`constitution-write-attempts.log`** (`.claude/hooks/.log/`) — already present; extended to cover new deny-list paths (AC-26).
- **`.subagent-spawn-count-<session_id>`** (`.claude/hooks/.log/`) — per-session subagent spawn counter (AC-27).

New `validate.sh` check categories:
- `[force-bypass]` — greps for committed `export FORCE_CONSTITUTION_EDIT` (AC-4).
- `[doc-consistency]` — runs `check-doc-consistency.sh` (AC-7).
- `[constitution-size]` — `wc -l < .claude/CLAUDE.md` ≤ 300 (AC-37).
- `[mcp-bare-name]` — flags MCP entries with no `@<version>` (AC-29).

New `harness-doctor.sh` checks (in addition to the 14 `validate.sh` categories):
- autopilot artifacts present and within freshness window
- swarm state files match active feature-streams
- memory budget current vs cap
- security invariants (`disableBypassPermissionsMode == "disable"`, etc.)
- doc-claims audit (links from `CLAUDE.md` resolve to existing files)

## References

### Spec + ADRs + patterns + incidents consulted (Step 3 evidence)

- **Spec**: `specs/archive/2026-Q3/002-audit-remediation.md`
- **Predecessor spec**: `specs/archive/2026-Q3/001-harness-hardening.md` (atomic-write lib, evidence-gate, constitution guard — all reused)
- **Incident**: `.claude/memory/incidents/2026-05-28-sec-constitution-unprotected.md` (the SEV1 that motivated Phase 1 hardening; AC-1/AC-2/AC-4 all derive from it)
- **Research brief**: `docs/research/claw-code-audit-2026-05-28.md` (Phase 6 adoption analysis; primary source for AC-31..AC-36)
- **Constitution**: `.claude/CLAUDE.md` §V (model routing — AC-7), §VII (verification — AC-1/AC-3), §X (security — Phase 5), §XV (handoff contract — AC-25), §XVI (issue projection — AC-20)

### File-level references (existing code the plan must coexist with, not re-implement)

- `.claude/hooks/pre-bash-guard.sh` lines 25-78 (existing `deny_patterns` array; AC-5 appends to it), line 110 (chained-segment splitter; reused by new patterns)
- `.claude/hooks/stop-verify.sh` lines 33-39 (legacy block envelope; AC-1 replaces)
- `.claude/hooks/pre-edit-constitution-guard.sh` line 23 (`FORCE_CONSTITUTION_EDIT` check; AC-4 hardens), line 60-70 (deny-list case block; AC-26 extends)
- `.claude/hooks/session-heartbeat.sh` lines 102-138 (existing swarm state machine — extended by AC-31, AC-12, AC-33)
- `.claude/hooks/subagent-stop.sh` lines 58-90 (existing feature-stream/coordinator hard-enforce; AC-3 extends to Stop hook, AC-25 augments handoff)
- `.claude/hooks/post-bash-log.sh` lines 46-76 (existing lane event emitter; AC-32 extends with new event types + error.kind)
- `.claude/hooks/pre-spawn-cost-gate.sh` lines 22-65 (existing Agent/Task prompt-size gate; AC-27 adds cost-cap branch alongside it)
- `.claude/hooks/pre-write-secret-scan.sh` lines 22-30 (existing path-block case; AC-30 path expansion appended)
- `.claude/scripts/memory-gc.sh` lines 54-74 (existing enforce mode; AC-22 replaces head-truncation with last_accessed eviction)
- `.claude/scripts/validate.sh` lines 19-60 (existing `--json` mode; AC-29/AC-37/AC-4 add new check categories that flow through it)
- `.claude/scripts/requeue-failed.sh` lines 30-44 (existing awk-on-TASKS.md report; AC-32 rewrites to JSONL reader)
- `.claude/settings.json` line 47 (`Write(./**)` blanket — AC-26 narrows), lines 148/156 (`gh issue view` + `gh api` allows — AC-20 removes)
- `.swarms/templates/handoff.yaml` lines 68-80 (verification block — AC-25 inserts `tdd_state` after)
- `.mcp.json` lines 131-136 (`context7` — AC-29 pins), lines 240-244 (`replicate` — AC-29 pins)
- `.github/workflows/ci.yml` line 118 (`continue-on-error: true` — AC-9 removes)
- `.github/workflows/merge-gate.yml` lines 35-38 (first-run allowance — AC-10 bounds + inlines scan)
- `.claude/routines/overnight-build.yml` lines 108-116 (Monthly cap check — AC-11 inverts fallback)
- `.claude/scripts/install-plugins.sh` lines 36-79 (plugin install loop — AC-28 adds version pin + provenance)
- `.claude/scripts/test/pre-edit-constitution-guard.sh` (existing contract reference for AC-4 hardening)
- `.claude/commands/harness-doctor.md` (existing slash-command; AC-35 extracts logic into `harness-doctor.sh`)

### External references (for Phase 6 adoptions, cited in spec)

- claw-code primary sources: https://github.com/instructkr/claw-code (ROADMAP.md, PHILOSOPHY.md, USAGE.md, docs/g004-events-reports-contract.md, docs/g011-acp-json-rpc-status-contract.md), https://github.com/ultraworkers/claw-code
- Claude Code hook schema: https://code.claude.com/docs/en/hooks (AC-1, AC-2 envelope reference)
- Claude Code permissions schema: https://code.claude.com/docs/en/permissions (AC-26 `Write(<path>)` syntax reference)

### Decisions not in prior ADRs (new ADRs to write during implementation)

- **ADR-XXXX (Phase 6)**: Adopt typed JSONL lane events (`.swarms/events/<id>.jsonl`) over enriched bash.log scraping. Citation: claw-code `docs/g004-events-reports-contract.md`; rejected: extending `bash.log` format because it conflates per-command audit with per-stream lifecycle.
- **ADR-XXXX (Phase 7)**: Constitution compaction is human-review only, never auto-applied. Citation: AC-37 + spec OQ-4 resolution; dream-review precedent.
- **ADR-XXXX (Phase 5)**: `Write(./**)` blanket allow replaced with enumerated 14-path allow-list. Citation: AC-26; rejected: keep blanket + add a per-write classifier (latency too high; classifier already runs in Auto Mode).
- **ADR-XXXX (Phase 4)**: `memory-gc.sh` evicts by `last_accessed:` frontmatter, not file position. Citation: AC-22; rejected: append-only with quarterly archive (data already exceeds 200-line cap weekly during heavy phases).
```

---

Plan written: plans/active/002-audit-remediation.md | 8 phases | 18 new files (excluding evidence artifacts) | ~20 modified files

Note: my tool surface in this thread is read-only (Read/Glob/Grep/WebFetch/WebSearch — no Write/Edit). The complete plan content is above for the harness to write to disk at the requested path.

```nexus
attempt: 1
status: complete
agent: architect
output: plans/active/002-audit-remediation.md
phases: 8
evidence:
  - plans/active/002-audit-remediation.md content delivered inline (read-only tool surface; parent harness writes file)
  - 18 new files enumerated in Dependencies section
  - ~20 modified files enumerated in Architecture section
  - 40 ACs traced to component changes
  - rollback procedure per phase
  - risk table with mitigations
  - references cite spec 001, incident 2026-05-28-sec-constitution-unprotected, claw-code research brief, constitution sections V/VII/X/XV/XVI
next_step: "/tasks 002 to decompose into atomic tasks"
handoff_to: planner

