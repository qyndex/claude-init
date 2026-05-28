---
id: 002
slug: audit-remediation
status: approved
owner: "@claude"
human_owner: "@shravan"
created: 2026-05-29
updated: 2026-05-29
supersedes:
superseded_by:
complexity: XL
objective: KR-2026Q3-HARNESS-FACTORY-FITNESS
initiative: harness-factory-readiness
service_tier: T1
feedback_refs: []
github_issue:
---

# Spec 002: Audit Remediation — Bug fixes, Gap closures, claw-code adoptions

> Closes every finding from the 2026-05-29 six-agent audit (longevity, coherence, security, memory, claw-code, fitness). Lands the harness in a "best-in-class autonomous AI-driven software factory" posture suitable for weeks-to-years delivery with minimal operator intervention. Companion artifact: `verify/2026-05-29-audit/REPORT.md` (full audit transcript).

## Problem statement

The 2026-05-29 multi-angle audit (six independent specialist agents) found that spec 001 hardened the constitution and security claims but the harness still ships with **6 active code bugs** (security-critical), **6 critical process gaps** (would block multi-month delivery), **~20 significant gaps**, and is missing **6 adoptable patterns from claw-code**. Several spec 001 invariants are still bypassable in practice (notably the two-layer security model collapses to one because `pre-bash-guard.sh` and `stop-verify.sh` use the wrong exit code / JSON schema). Without this remediation the harness cannot be relied upon for autonomous multi-month delivery: operators will hit silent verification gate bypasses, runaway cost on `Agent` tool spawns, supply-chain compromise via mutable CI refs, and constitution sprawl that erodes the prompt cache by month 6.

## Goals

In scope:

- **Phase 1 (Bug fixes)**: fix every active code bug found by the audit (BUG-1 through BUG-6) — wrong hook schemas, wrong exit codes, escape-hatch bypasses, shell-redirect evasion, unpinned CI actions, model-routing doc conflict.
- **Phase 2 (Critical gap closures)**: close every CRITICAL gap that would block multi-month delivery — missing deploy pipeline policy, integration-test silent-pass, merge-gate first-run loophole, cost-cap fallback inversion, in-flight swarm version migration, initiative/roadmap layer.
- **Phase 3 (Significant gap closures)**: close all SIGNIFICANT gaps — stale-spec detection, spec-archival broken cross-references, missing `docs/ADOPTION.md`, possibly-missing `memory-promote.sh`, hook duplication, phase-state coverage, permission/constitution contradictions.
- **Phase 4 (Memory hardening for 12+ month projects)**: witness-brief delivery guarantee, evict-by-`last_accessed` memory GC, dream safety net (structured diff review), cross-session contradiction detection, NEXUS schema TDD-state fields, decision-staleness detection linked to code.
- **Phase 5 (Security gap closures)**: blanket `Write(./**)` narrowing, `Agent`/`Task` cost cap, plugin install integrity checks, MCP version pin tightening, PII scrubber path expansion, `gh issue view` / `gh api` permission contradiction.
- **Phase 6 (claw-code adoptions)**: 6 patterns adopted — worker lifecycle state machine, typed JSONL lane events, workspace-fingerprint isolation, branch-freshness preflight, `--json` on diagnostics, anti-slop eight-class PR triage agent.
- **Phase 7 (Meta-evolution discipline)**: constitution compaction/archival process so CLAUDE.md does not sprawl to 500+ lines over 12 months and collapse the prompt cache.
- **Phase 8 (Verification + exit)**: full `validate.sh` clean run + `harness-doctor` clean + paired regression evidence + REPORT.md.

## Non-goals

Explicitly out of scope (state to prevent drift):

- Deployment pipeline implementation (canary-deploy.yml stub remains a stub — this spec only **documents** that deploy is BYO; building it is a separate spec when a real consumer of the harness needs it).
- Non-GitHub forge abstraction (GitLab/Bitbucket/Azure DevOps support) — explicitly deferred to spec 003+ when first non-GitHub consumer arrives.
- Mobile/embedded verification adapters (Playwright is sufficient for web; mobile is a different spec).
- Monorepo affected-graph awareness (Nx/Bazel/Turbo integration) — separate spec.
- T-057/T-058 paired 16h regression run — still OPERATOR-ONLY; this spec inherits the `--regression-pair` driver build into Phase 8 only if T-057 still requires it after Phase 1-7.
- Multi-provider model routing (xAI, Ollama, etc.) — explicitly rejected from claw-code review; Anthropic-first is a deliberate decision.
- Discord/HTTP operator interface — explicitly rejected.
- Adopting claw-code `.omx/` layer or Rust binary — explicitly rejected (breaks no-build-step principle).

## User stories

- As an **operator**, I want the verification gate (`stop-verify.sh`) to actually block when production files change without a verification report, so that I do not wake up to a green CI status hiding unverified merges.
- As an **operator**, I want `pre-bash-guard.sh` to hard-block (exit 2) before the classifier runs, so that destructive commands cannot be rationalized through by the Sonnet override.
- As an **operator running overnight autopilot**, I want the cost cap to apply to `Agent`/`Task` tool spawns (not just Bash spawns), so that 10 parallel feature-streams × 5 subagents each do not silently burn the monthly budget.
- As an **operator running overnight autopilot**, I want missing telemetry to default to "continue with warning," not "abort the whole night," so that one bad JSON file doesn't kill 8 hours of planned work.
- As a **brownfield adopter**, I want `docs/ADOPTION.md` to exist when the root `CLAUDE.md` links to it, so that my first 5 minutes with the harness are not a 404.
- As a **multi-month project lead**, I want the constitution to have a compaction/archival process, so that by month 12 the prompt cache is not thrashing on 500+ lines of "Round N" patches.
- As a **multi-month project lead**, I want stale specs and spec-archival cross-reference rewriting, so that `tasks/TASKS.md` does not accumulate dead links to `specs/active/...` paths after each quarterly archive.
- As a **swarm coordinator**, I want a typed worker lifecycle state machine, so that I do not dispatch prompts to a still-spawning stream and create the phantom-completion bug class claw-code documented.
- As a **swarm coordinator**, I want typed JSONL lane events, so that `requeue-failed.sh` can reliably parse stream outcomes instead of scraping free-text logs.
- As a **security reviewer**, I want every third-party GitHub Action pinned to a commit SHA, so that an upstream compromise of `ludeeus/action-shellcheck@master` cannot inject code with `ANTHROPIC_API_KEY` access.
- As an **autonomous agent**, I want the `Write(./**)` blanket allow narrowed for task-state files (`tasks/TASKS.md`, `specs/active/**`, `plans/active/**`), so that a prompt-injected agent cannot silently mark tasks done or delete acceptance criteria.

## Acceptance criteria

Each criterion is testable, measurable, observable. Tasks reference these IDs.

### Phase 1 — Active code bugs

1. **AC-1 (BUG-1)**: `stop-verify.sh` emits `{"hookSpecificOutput": {"hookEventName": "Stop", "permissionDecision": "deny", "permissionDecisionReason": "..."}}` and `exit 2` on block. Verified by: a synthetic Stop event with unverified production-file changes produces a real Claude Code block, not a silent continue. Test artifact: `verify/2026-05-29-002/T-AC-1-stop-verify-block.log`.

2. **AC-2 (BUG-2)**: `pre-bash-guard.sh` exits with code 2 (not 0) on all `permissionDecision: deny` paths (lines 93, 116, 147). Verified by: `printf '{"tool_input":{"command":"rm -rf /tmp/x"}}' | bash .claude/hooks/pre-bash-guard.sh; echo $?` returns `2`.

3. **AC-3 (BUG-3)**: `coordinator` NEXUS handoff enforcement actually fires on its real lifecycle. Either: (a) `stop-verify.sh` adds a coordinator NEXUS check, OR (b) coordinator runs as a documented subagent so `subagent-stop.sh:58` triggers. Verified by: a coordinator Stop without a NEXUS block produces a real exit 2.

4. **AC-4 (BUG-4)**: `FORCE_CONSTITUTION_EDIT=1` env-var bypass is removed OR hardened. If kept, must validate against an out-of-band secret from `~/.claude/settings.local.json` (gitignored). `validate.sh` asserts no committed script, workflow, or agent frontmatter `export`s this variable. Verified by: `grep -rE 'export[[:space:]]+FORCE_CONSTITUTION_EDIT' .claude .github | wc -l` returns `0`.

5. **AC-5 (BUG-5)**: `pre-bash-guard.sh` deny list includes patterns for `tee` writes to `.claude/`, `find -exec sh`, `xargs sh`, and shell redirect (`>`, `>>`) targeting `.claude/hooks/`, `.claude/CLAUDE.md`, `settings.json`, `.github/workflows/`. Verified by: 8-case bypass-attempt fixture (`verify/2026-05-29-002/T-AC-5-bypass-fixtures.sh`) — all 8 must exit non-zero.

6. **AC-6 (BUG-6)**: All third-party GitHub Actions pinned to commit SHAs (not `@main` / `@master`). Verified by: `grep -rE '@(main|master)\b' .github/workflows/` returns zero matches (excluding the harness's own `actions/checkout@vN` pattern which uses major version tags by convention — but those tags must be verified-immutable; auditor flagged `ludeeus/action-shellcheck@master`, `bridgecrewio/checkov-action@master`, `google/osv-scanner-action/.github/workflows/osv-scanner-reusable.yml@main` as the three to fix).

7. **AC-7 (model-routing doc conflict)**: Root `CLAUDE.md:91` agent model assignments match `.claude/CLAUDE.md §V` exactly. Verified by: `bash .claude/scripts/check-doc-consistency.sh` (new script that diffs the two tables) exits 0.

### Phase 2 — Critical process gaps

8. **AC-8 (deploy pipeline policy)**: Root `CLAUDE.md` "What this repo is" section explicitly states deploy pipeline is BYO; `canary-deploy.yml` has a header comment `# STUB — replace with project-specific deploy logic; see docs/DEPLOY-INTEGRATION.md`; `docs/DEPLOY-INTEGRATION.md` exists with a checklist for projects adopting the harness. Verified by: `test -f docs/DEPLOY-INTEGRATION.md && grep -q 'STUB' .github/workflows/canary-deploy.yml`.

9. **AC-9 (integration tests required)**: `.github/workflows/ci.yml` removes `continue-on-error: true` from the integration-test step. Verified by: `grep -A2 'integration' .github/workflows/ci.yml | grep -c 'continue-on-error: true'` returns `0`.

10. **AC-10 (merge-gate first-run bounded)**: `merge-gate.yml` first-run allowance has a time bound (e.g., max 7 days after repo init) AND falls back to a synchronous security scan if `daily-batch` has never run. Verified by: synthetic test where `gh api .../actions/runs?workflow=daily-batch.yml` returns empty → merge-gate runs an inline `semgrep` + `gitleaks` scan instead of warn-and-pass.

11. **AC-11 (cost-cap fallback)**: `overnight-build.yml:110-113` cost-cap logic defaults to "continue with warning" when `cost-summary.json` is missing or malformed, NOT "abort." Verified by: removing `cost-summary.json` and running the cap check produces exit 0 with a `::warning::` annotation.

12. **AC-12 (in-flight swarm version check)**: Every feature-stream's `session-start` hook records the harness version (git SHA of `.claude/`) and compares to current main on every prompt; if drifted by N commits, emits a `harness.version.drift` lane event. Verified by: integration test that bumps `.claude/VERSION` mid-stream and asserts the lane event fires.

13. **AC-13 (initiative/roadmap layer)**: `initiatives/active/` directory exists with a template (`initiatives/templates/initiative.md`); `session-end.sh` reads `.claude/state/current-initiative` AND something writes it (`/initiative create <slug>` slash-command or skill). Verified by: `/initiative create test-initiative` produces `initiatives/active/<id>-test-initiative.md` AND `.claude/state/current-initiative` is updated.

### Phase 3 — Significant gaps

14. **AC-14 (stale-spec detection)**: New routine `stale-spec-check.yml` detects specs with `status: approved` AND zero task `[x]` completions referencing them AND `updated:` > 30 days ago, emits a warning to MEMORY.md incident log. Verified by: synthetic stale-spec fixture flags as stale.

15. **AC-15 (spec-archival cross-reference rewrite)**: `quarterly-archive.yml` rewrites `Spec: specs/active/<id>...` to `Spec: specs/archive/<quarter>/<id>...` in `tasks/TASKS.md` after each `mv`. Verified by: synthetic archive run leaves no dead-link cross-references in TASKS.md.

16. **AC-16 (docs/ADOPTION.md exists)**: `docs/ADOPTION.md` exists with the six-phase brownfield adoption flow referenced from root `CLAUDE.md:148`. Verified by: `test -f docs/ADOPTION.md && wc -l docs/ADOPTION.md` returns ≥ 100 lines.

17. **AC-17 (memory-promote.sh exists)**: `memory-promote.sh` exists at `.claude/scripts/memory-promote.sh` (referenced by `dream-cron.yml:52`). Implements ADR-staleness flagging by cross-referencing `code_paths:` frontmatter against git changes since `last_verified:`. Verified by: `bash .claude/scripts/memory-promote.sh --dry-run` exits 0 and lists stale ADRs.

18. **AC-18 (UserPromptSubmit hook dedup)**: `user-prompt-context.sh` and `workflow-state.sh` do not both inject active-spec/plan. Either consolidate into one hook OR add explicit non-overlapping responsibilities. Verified by: a single prompt's `additionalContext` mentions active-spec name at most once.

19. **AC-19 (workflow-state phase coverage)**: `workflow-state.sh` derives all 8 phases (constitute, specify, clarify, plan, tasks, analyze, implement, verify-review-ship) — not 5. Verified by: synthetic fixtures for each phase produce the matching phase string.

20. **AC-20 (gh issue read permission contradiction)**: Remove `Bash(gh issue view:*)` and `Bash(gh api:*)` from `settings.json` allow list (constitution §XVI prohibits reading task state from GitHub API). Replace with narrow allows if needed (`Bash(gh issue create:*)`, `Bash(gh pr ...:*)`). Verified by: `jq '.permissions.allow[]' .claude/settings.json | grep -E 'gh (issue view|api)'` returns empty.

### Phase 4 — Memory hardening

21. **AC-21 (witness-brief delivery guarantee)**: `session-start-context.sh` polls the witness checkpoint file for the `(pending)` sentinel and waits up to 90s before loading; logs `witness.timeout` if exceeded. Verified by: synthetic test with a deliberately slow witness — session-start waits, then loads.

22. **AC-22 (memory-gc eviction order)**: `memory-gc.sh enforce` evicts by `last_accessed:` frontmatter timestamp (oldest first), NOT by file position. Verified by: synthetic MEMORY.md with 250 entries where the newest 50 are at the bottom — after gc, the newest 50 must survive.

23. **AC-23 (dream safety net)**: `/dream-review` slash-command emits a structured diff (`memory-diff.md`) showing every removed line/entry before the proposal is applied. Verified by: dream-review on a non-empty `.claude/memory.proposed/` produces a diff artifact.

24. **AC-24 (cross-session contradiction detection)**: Dream skill step added: group decisions by `subsystem:` frontmatter; flag pairs where `decision:` fields contradict (LLM comparison pass); output `conflicts.md` in proposal. Verified by: synthetic two-decision fixture (one says X, one says Y) produces a flagged conflict.

25. **AC-25 (NEXUS schema TDD-state fields)**: `.swarms/templates/handoff.yaml` adds optional fields: `tdd_phase: red|green|refactor`, `last_test_command`, `last_test_exit_code`, `wip_sha`. `subagent-stop.sh` auto-populates from most-recent `WIP:` commit. Verified by: a feature-stream interrupted mid-red-phase produces a handoff with `tdd_phase: red` populated.

### Phase 5 — Security gap closures

26. **AC-26 (Write blanket narrow)**: `settings.json` removes `Write(./**)` blanket allow; adds explicit allows per-directory; adds `pre-edit-constitution-guard.sh` coverage for `tasks/TASKS.md`, `specs/active/**`, `plans/active/**`. Verified by: synthetic agent attempting to write `tasks/TASKS.md` without justification is blocked OR requires explicit operator approval.

27. **AC-27 (Agent/Task cost cap)**: `pre-spawn-cost-gate.sh` cost-cap check applies to `Agent` and `Task` tool names (not just Bash spawns). Verified by: spawning the 11th `Agent` in a session under a low cap (`MONTHLY_CAP_USD=1`) is blocked with a cap warning.

28. **AC-28 (plugin install integrity)**: `install-plugins.sh` pins each plugin install to a specific version or commit SHA. For community marketplaces, adds a `gh repo view <marketplace>` provenance check before adding. `CLAUDE.md §X` documents plugins as unverified supply chain unless pinned. Verified by: every `claude plugin install` line has a version pin.

29. **AC-29 (MCP version pin tightening)**: `validate.sh` flags bare package-name args (e.g., `@upstash/context7-mcp` with no `@version`) AND `git+https://` install patterns. `context7` and `replicate` pinned explicitly. Verified by: `bash .claude/scripts/validate.sh` reports zero `@latest` AND zero bare-name MCP entries.

30. **AC-30 (PII scrubber path expansion)**: `pre-write-secret-scan.sh` PII scrubber `case` block covers `OVERNIGHT_REPORT.md`, `verify/**/*.log`, `verify/**/REPORT.md` in addition to `.claude/memory/**`. Verified by: synthetic write of a session transcript containing `user@example.com` to `OVERNIGHT_REPORT.md` is scrubbed.

### Phase 6 — claw-code adoptions

31. **AC-31 (worker lifecycle state machine)**: `.swarms/streams/<id>/state.json` schema added (4 fields: `state`, `timestamp_ms`, `worktree`, `fingerprint`); valid states: `spawning|trust_required|ready_for_prompt|prompt_accepted|running|finished|failed`. `session-heartbeat.sh` writes transitions. Coordinator agent gates prompt dispatch on `state == ready_for_prompt`. Verified by: synthetic stream-spawning fixture — coordinator does not dispatch until state reaches `ready_for_prompt`.

32. **AC-32 (typed JSONL lane events)**: `.swarms/events/<stream-id>.jsonl` schema added; events: `lane.started|lane.blocked|lane.red|lane.commit.created|lane.finished`; `error.kind` enum (`filesystem|auth|session|parse|runtime|mcp|delivery|usage|policy`); `retryable: bool`. `post-bash-log.sh` and `subagent-stop.sh` emit. `requeue-failed.sh` rewritten to read JSONL. Verified by: a failing stream produces parseable JSONL; `requeue-failed.sh` correctly identifies retryable failures.

33. **AC-33 (workspace fingerprint isolation)**: `session-heartbeat.sh` computes `WORKSPACE_FP=$(printf "%s" "$(pwd -P)" | md5 | cut -c1-16)`; session state written under `.claude/sessions/$WORKSPACE_FP/`; mismatch emits `workspace.mismatch` lane event. Verified by: synthetic test running from two worktrees produces two distinct fingerprint dirs.

34. **AC-34 (branch-freshness preflight)**: `verify.sh` adds branch-freshness check as first step (before stack detection): `git fetch --quiet && git merge-base --is-ancestor HEAD origin/main`. On stale, emits `branch.stale_against_main` lane event AND warns user. Respects `SKIP_BRANCH_CHECK=1`. Verified by: synthetic 40-commit-behind branch fixture produces the warning.

35. **AC-35 (--json on diagnostics)**: `harness-doctor` script accepts `--json` flag, emits per-check `{"check":"...","status":"pass|fail|warn","detail":"..."}` JSON. `harness-validate.yml` uploads `verify/doctor-<date>.json` as CI artifact. Verified by: `bash .claude/scripts/harness-doctor.sh --json | jq .` parses successfully.

36. **AC-36 (anti-slop PR triage agent)**: `.claude/agents/quality/anti-slop-reviewer.md` exists with eight-class triage instruction (`actionable-bug|actionable-docs|duplicate|generated-slop|spam|security-sensitive|not-reproducible|externally-blocked`). Wired into `pr-review.yml` as warn-only initially (commented `# block after burn-in`). Verified by: synthetic PR descriptions in each class produce the matching classification.

### Phase 7 — Meta-evolution discipline

37. **AC-37 (constitution compaction process)**: New skill `.claude/skills/constitution-compact/SKILL.md` defines the quarterly compaction process for `.claude/CLAUDE.md`: extract resolved patches into archived ADRs, consolidate "Round N" sections into named principles, enforce a 300-line cap. New routine `constitution-compact-cron.yml` (quarterly) emits a `.claude/memory.proposed/constitution-diff.md` for human review. Verified by: `wc -l .claude/CLAUDE.md` ≤ 300; the routine produces a diff proposal without auto-applying.

### Phase 8 — Exit gates

38. **AC-38 (full validate clean)**: `bash .claude/scripts/validate.sh` exits 0 with zero new failures vs. spec-001-exit baseline (`commit 9904e8f` or current `T-056` baseline log). Pre-existing `python3 + pyyaml` warning still permitted. Verified by: diff of pre-vs-post run logged to `verify/2026-05-29-002/validate-exit.log`.

39. **AC-39 (harness-doctor clean)**: `bash .claude/scripts/harness-doctor.sh` exits 0 with zero CRITICAL or HIGH findings. Verified by: `harness-doctor --json | jq '[.[] | select(.status=="fail")] | length'` returns `0`.

40. **AC-40 (REPORT.md)**: `verify/2026-05-29-002/REPORT.md` emitted with: AC-by-AC pass/fail table; classifier-deny counts (if T-057 driver was completed as part of this spec); operator-intervention totals; rollback recommendation if any CRITICAL AC fails. Verified by: file exists AND contains all 40 AC IDs in a table.

## Constraints

- **Performance**: No new hook may add > 50ms to `UserPromptSubmit` p95 (cache-warming discipline). No new CI workflow may add > 2 min to PR-time gate. Constitution cap: 300 lines hard ceiling.
- **Security**: Every fix in Phase 1 + Phase 5 must be re-verified by an independent multi-pass security review (Anthropic claude-code-security-review pattern). No fix may introduce a new escape hatch.
- **Compatibility**: All changes backwards-compatible with spec 001 deliverables; pre-phase1 tag (`780fa60`) still resolves; existing TASKS.md schema preserved. Quarterly archive routine must not break on this spec's added `initiatives/` directory.
- **Compliance**: Atomic-write library (`lib/atomic-write.sh`) used for every file mutation in `quarterly-archive.yml`, `memory-gc.sh`, and all dream-proposal writes (no partial-write windows).
- **Accessibility**: N/A (harness, not user-facing UI).
- **Determinism**: Every gate that blocks must be deterministic (state-machine or exact pattern match), NOT LLM-judged. The 5 LLM-judgment patterns flagged by the audit (dream compression, anti-slop classification, conflict detection, witness brief, ADR staleness) all require an explicit human-review step before applying.

## Rollout

```yaml
flag:
  name: harness_audit_remediation_v2
  type: rollout
  default: false
  provider: none
  depends_on: []
  owner: "@shravan"

ramp_plan:
  - stage: phase1_bugs
    cohort: this-repo-only
    wait: same-day
    exit_gate: "AC-1..AC-7 green; validate.sh clean; manual smoke of hook block paths"
  - stage: phase2_critical_gaps
    cohort: this-repo-only
    wait: 24h
    exit_gate: "AC-8..AC-13 green; first overnight build under new cost-cap fallback succeeds"
  - stage: phase3_significant
    cohort: this-repo-only
    wait: 24h
    exit_gate: "AC-14..AC-20 green; one synthetic quarterly-archive dry-run passes"
  - stage: phase4_memory
    cohort: this-repo-only
    wait: 48h
    exit_gate: "AC-21..AC-25 green; one /dream-review cycle with proposal produces structured diff"
  - stage: phase5_security
    cohort: this-repo-only
    wait: 24h
    exit_gate: "AC-26..AC-30 green; independent security re-verification of Phase 1+5 clean"
  - stage: phase6_claw_adoption
    cohort: this-repo-only
    wait: 48h
    exit_gate: "AC-31..AC-36 green; one swarm dispatch under new state machine completes without phantom completion"
  - stage: phase7_meta
    cohort: this-repo-only
    wait: 7d
    exit_gate: "AC-37 green; constitution ≤ 300 lines; compaction-cron dry-run produces proposal"
  - stage: phase8_exit
    cohort: this-repo-only
    wait: 24h
    exit_gate: "AC-38, AC-39, AC-40 green; REPORT.md merged"

success_metric:
  name: harness_factory_fitness_score
  baseline: 6_active_bugs + 6_critical_gaps + 20_significant_gaps # from 2026-05-29 audit
  target: 0_active_bugs + 0_critical_gaps + 0_significant_gaps
  source: verify/2026-05-29-002/REPORT.md

auto_rollback_threshold:
  error_rate: "any AC-1..AC-7 fix introducing a NEW pre-bash-guard bypass"
  p95_latency: "UserPromptSubmit p95 > 1s after AC-18 dedup"
  custom: "validate.sh fail count > pre-phase1 baseline + 0"

cleanup_after: 90d # remove flag from any consumer projects 90 days after Phase 8 exit
```

## SLOs

```yaml
service_tier: T1
slos:
  availability: 100% # harness must never silently fail-open on a security gate
  latency_p95: 50ms # per-hook overhead budget
  latency_p99: 200ms
  error_budget_burn_alert: "any deterministic gate firing silently = SEV1"
runbook: docs/PLAYBOOK.md
dashboards:
  - .claude/hooks/.log/ (file-based; OTEL planned in separate spec)
on_call_rotation: "@shravan"
```

## Open questions

The clarification round resolved all of these inline during spec authoring. None remain open at draft time:

- ~~[OQ-1] Should `FORCE_CONSTITUTION_EDIT=1` be removed entirely or hardened?~~ → Decision: hardened against `~/.claude/settings.local.json` out-of-band secret (preserves operator escape for legitimate constitution amendments); AC-4 enforces no committed exports.
- ~~[OQ-2] Should the deploy pipeline stub be removed or marked?~~ → Decision: marked STUB with explicit BYO doc (AC-8); removal would lose the rollout-discipline pattern that consumers should follow.
- ~~[OQ-3] Should anti-slop triage be warn or block?~~ → Decision: warn-only initially (AC-36), block after 30-day burn-in. Documented in the agent file header.
- ~~[OQ-4] Constitution compaction: auto-apply or human-review?~~ → Decision: human-review always (AC-37). The dream-review precedent applies — never silent rewrites of the law.
- ~~[OQ-5] Should T-057/T-058 paired-regression driver be in this spec?~~ → Decision: included as **optional** Phase 8 deliverable. If operator wants the regression run as part of Phase 8 exit, the `--regression-pair` driver is built; otherwise T-057/T-058 stay `[s]` skipped and this spec exits on AC-38..AC-40 alone.

## Dependencies

- Depends on spec: 001 (harness-hardening — provides constitution guard, evidence-gate, hermetic sandbox, atomic-write library, doc-claims audit; all Phase 1-7 already shipped)
- Blocks spec: 003+ (non-GitHub forge abstraction, mobile/embedded verification, monorepo affected-graph) — those become tractable only after this spec lands the meta-evolution discipline.
- External: GitHub Actions Marketplace (for SHA pins); claw-code GitHub repos (instructkr/claw-code, ultraworkers/claw-code) for adoption patterns.

## Out of scope (will be picked up later)

- **Spec 003 (proposed)**: Non-GitHub forge abstraction layer (GitLab/Bitbucket/Azure DevOps) — extract `gh` calls into a thin `forge.sh` adapter; replace `no-issue-authority.yml` projection model with a forge-agnostic equivalent.
- **Spec 004 (proposed)**: Mobile + embedded verification adapters — XCUITest/Espresso replacements for the Playwright evidence rig; HIL test harness for embedded.
- **Spec 005 (proposed)**: Monorepo affected-graph awareness — Nx/Bazel/Turbo integration for `verify.sh` so it only runs affected targets.
- **Spec 006 (proposed)**: Cost observability closed loop — Langfuse integration with per-feature cost attribution and budget-cap enforcement at the initiative layer.
- **Spec 007 (proposed)**: Production incident → spec auto-loop — PagerDuty/Sentry → TASKS.md automatic feed; SEV→spec creation pipeline.
- **Spec 008 (proposed)**: Multi-environment promotion model — staging/prod gating logic in `canary-deploy.yml` (when the first real consumer needs it).
- **T-057/T-058 (if not bundled)**: 16h paired-regression autopilot run — remains OPERATOR-ONLY scheduled event.

## Change history

```
- 2026-05-29 | @claude | created | spec authored from six-agent audit findings; all 40 ACs cover bugs+gaps+adoptions; no [OQ] remaining at draft time
```

## References

- Spec 001: `specs/active/001-harness-hardening.md`
- Audit transcript (this session, 2026-05-29): full 6-agent report in the conversation log; key findings consolidated into this spec's ACs
- Incident report: `.claude/memory/incidents/2026-05-28-sec-constitution-unprotected.md`
- claw-code adoption analysis: `docs/research/claw-code-audit-2026-05-28.md`
- claw-code primary sources:
  - https://github.com/instructkr/claw-code (ROADMAP.md, PHILOSOPHY.md, USAGE.md, docs/g004-events-reports-contract.md, docs/g011-acp-json-rpc-status-contract.md)
  - https://github.com/ultraworkers/claw-code
  - https://www.eigent.ai/blog/claw-code
  - https://www.openaitoolshub.org/en/blog/claw-code-open-source-review
- Constitution: `.claude/CLAUDE.md` (§V model routing, §VII verification, §X security, §XV handoff, §XVI issue projection)
- Hook lifecycle reference: root `CLAUDE.md` "Hook lifecycle" section
- Pre-phase1 baseline tag: `git tag pre-phase1` → `780fa60`
- spec-001 exit baseline log: `verify/2026-05-29/T-056/green.log`
