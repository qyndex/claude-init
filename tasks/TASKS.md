# Tasks

Append-only task ledger. The planner agent (`.claude/agents/core/planner.md`) populates this from approved plans.

## Format

```
- [ ] T-NNN  | spec:NNN  | phase:N  | priority: <P>  | created: <ISO>  | last_touched: <ISO>  | deps: T-AAA, T-BBB  | parallel: yes|no  | est: <Nm>
  summary: <verb-first one-line description>
  files: path/to/file1, path/to/file2
  accept: <shell command that exits 0 when this task is done>
  owner: @<person-or-implementer>
```

### Field reference

| Field          | Required | Notes                                                                 |
| -------------- | -------- | --------------------------------------------------------------------- |
| `T-NNN`        | yes      | monotonic ID across the whole repo                                    |
| `spec:NNN`     | yes      | spec the task implements                                              |
| `phase:N`      | yes      | phase within the plan (matches plan.md)                               |
| `priority`     | yes      | see priority taxonomy below — drives `/triage` ordering               |
| `created`      | yes      | ISO timestamp; required for `[!]`/`[s]` aging via `/debt age`         |
| `last_touched` | optional | ISO timestamp; updated when status changes or block reason is updated |
| `deps`         | optional | comma-separated task IDs                                              |
| `parallel`     | optional | `yes` if it can run beside its siblings                               |
| `est`          | yes      | honest minutes estimate; if >5min, decompose                          |
| `owner`        | yes      | `@<person>` for human-only tasks, `implementer` for agent tasks       |

### Priority taxonomy (drives `/triage` ordering)

| Priority            | Source                                                                  | SLA                                          |
| ------------------- | ----------------------------------------------------------------------- | -------------------------------------------- |
| `hotfix`            | **live prod alert (Sentry/SLO burn/synthetic) — externally originated** | **NOW — top of queue, pre-empts everything** |
| `incident-followup` | postmortem action item                                                  | this sprint                                  |
| `security`          | security review or `security` agent flagged                             | this sprint                                  |
| `P1-spec`           | spec marked `priority:P1`                                               | this sprint                                  |
| `debt`              | aged `[!]` items + tech debt                                            | next sprint                                  |
| `normal`            | most planner tasks                                                      | when bandwidth                               |
| `cleanup`           | flag cleanup, dep upgrades                                              | when bandwidth                               |
| `deprecation`       | sunset / migration                                                      | quarter-bounded                              |

**Hotfix tasks** (Round 12) carry extra fields: `fingerprint:` (Sentry dedup key), `sentry:` (permalink), `hotfix_issue:` (projected issue #). Inserted at the TOP of `## Active` by `hotfix-to-task.sh`. `spec:HOTFIX` is a sentinel — a hotfix has no originating spec.

## Status legend

- `[ ]` pending — eligible for `/implement next`
- `[~]` in_progress — currently being worked
- `[x]` completed — `accept:` exited 0 AND verification passed
- `[!]` failed — `accept:` did not pass; debt register entry. **Requires `reason:` line.**
- `[s]` skipped — explicitly deferred. **Requires `reason:` line.** Visible in `/debt list`.
- `[b]` blocked — waiting on a dep/decision/external. **Requires `blocked_by:` line.**

## Conventions

- Task IDs are monotonic across the whole repo (don't reset per spec/plan).
- Every task has an `accept:` command. No exceptions.
- Dependencies are explicit. The implementer follows the DAG.
- `parallel: yes` means the task can run alongside its siblings without conflict.
- Estimate `est:` honestly. If > 5 minutes, decompose.
- **Every status change updates `last_touched:`.** This is how staleness is computed.
- **`[!]` and `[s]` without `created:`** are invisible to aging — the SLA can't trigger. Treat as a format violation.

## Hygiene cadence

| Command                   | When            | Purpose                      |
| ------------------------- | --------------- | ---------------------------- |
| `/triage`                 | weekly (Monday) | re-rank backlog              |
| `/debt list`              | weekly          | see all `[!]`/`[s]`          |
| `/debt age`               | monthly         | surface SLA breaches         |
| `/debt triage`            | monthly         | force decision on >90d items |
| `/owner-walk @<departed>` | on departure    | re-assign all artifacts      |

---

## Active

### Spec 001 — Harness Hardening

#### Phase 1 — Security blockers (AC-1..AC-4)

- [x] T-001 | spec:001 | phase:1 | priority: security | created: 2026-05-29 | last_touched: 2026-05-29 | parallel: yes | est: 4m | completed: 2026-05-29
      summary: Write bypass-test scaffolding harness for pre-edit-constitution-guard (15+ deny-list paths, FORCE escape hatch, allow-pass on normal path) — fails red until T-002 lands
      files: .claude/scripts/test/pre-edit-constitution-guard.sh
      accept: bash -n .claude/scripts/test/pre-edit-constitution-guard.sh && grep -q 'permissionDecision' .claude/scripts/test/pre-edit-constitution-guard.sh && grep -q 'FORCE_CONSTITUTION_EDIT' .claude/scripts/test/pre-edit-constitution-guard.sh
      owner: implementer

- [x] T-002 | spec:001 | phase:1 | priority: security | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-001 | parallel: no | est: 5m | completed: 2026-05-29
      summary: Implement pre-edit-constitution-guard.sh hook (PreToolUse:Write|Edit|NotebookEdit) — deny-list glob match, FORCE_CONSTITUTION_EDIT escape hatch, append constitution-write-attempts.log, emit JSON permissionDecision deny, latency <50ms
      files: .claude/hooks/pre-edit-constitution-guard.sh
      accept: bash -n .claude/hooks/pre-edit-constitution-guard.sh && test -x .claude/hooks/pre-edit-constitution-guard.sh && bash .claude/scripts/test/pre-edit-constitution-guard.sh
      owner: implementer

- [x] T-003 | spec:001 | phase:1 | priority: security | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-002 | parallel: no | est: 3m | completed: 2026-05-29
      summary: Register pre-edit-constitution-guard.sh in settings.json under PreToolUse:Write|Edit|NotebookEdit matcher block — positioned BEFORE pre-write-secret-scan.sh in the chain
      files: .claude/settings.json
      accept: jq -e '.hooks.PreToolUse[] | select(.matcher == "Write|Edit|NotebookEdit" or .matcher == "Write|Edit") | .hooks[] | select(.command | test("pre-edit-constitution-guard"))' .claude/settings.json
      owner: implementer

- [x] T-004 | spec:001 | phase:1 | priority: security | created: 2026-05-29 | last\*touched: 2026-05-29 | parallel: yes | est: 5m | completed: 2026-05-29
      summary: Write 15-class bypass regression test for pre-bash-guard.sh — exercise command-substitution, backtick, process-substitution, env-var indirection, no-space -c/-e, IFS poisoning, heredoc-piped-to-shell, base64 printf variant, and 7 others from spec AC-2; expect all 15 to be rejected
      files: .claude/scripts/test/pre-bash-guard-bypass.sh
      accept: bash -n .claude/scripts/test/pre-bash-guard-bypass.sh && grep -cE 'BYPASS-?[0-9]+' .claude/scripts/test/pre-bash-guard-bypass.sh | awk '{exit ($1 < 15)}'
      owner: implementer

- [x] T-005 | spec:001 | phase:1 | priority: security | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-004 | parallel: no | est: 5m | completed: 2026-05-29
      summary: Rewrite pre-bash-guard.sh pre-pass — reject $(…), backticks, <(…), >(…), env-var indirection at command head, collapse whitespace before pattern match; preserve existing 30+ patterns; p95 <100ms
      files: .claude/hooks/pre-bash-guard.sh
      accept: bash .claude/scripts/test/pre-bash-guard-bypass.sh
      owner: implementer

- [x] T-006 | spec:001 | phase:1 | priority: security | created: 2026-05-29 | last\*touched: 2026-05-29 | parallel: yes | est: 4m | completed: 2026-05-29
      summary: Write security-invariants.sh baseline with first 4 invariant tests (constitution write-protect, bash-guard bypass coverage, evidence-gate ruleset presence, sandbox enabled in auto mode) — scaffold extended in Phase 6 to cover all of §VII/§X
      files: .claude/scripts/test/security-invariants.sh
      accept: bash -n .claude/scripts/test/security-invariants.sh && grep -cE 'INVARIANT-?[0-9]+' .claude/scripts/test/security-invariants.sh | awk '{exit ($1 < 4)}'
      owner: implementer

- [x] T-007 | spec:001 | phase:1 | priority: security | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-002, T-005 | parallel: no | est: 3m | completed: 2026-05-29
      summary: Wire evidence-gate as required check in main-protection.json ruleset — add {"context":"evidence-gate"} to required_status_checks.required_checks
      files: .github/rulesets/main-protection.json
      accept: jq -e '.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[]?.context // .parameters.required_checks[]?.context' .github/rulesets/main-protection.json | grep -q evidence-gate
      owner: implementer

- [x] T-008 | spec:001 | phase:1 | priority: security | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-006 | parallel: no | est: 4m | completed: 2026-05-29
      summary: Enable sandbox.enabled:true in settings.json gated on permissionMode auto — preserve interactive local override via settings.local.json comment guide; document allowedDomains catalogue
      files: .claude/settings.json
      accept: jq -e '.permissions.sandbox.enabled == true or (.permissions.sandbox.enabledWhen // "" | test("auto"))' .claude/settings.json
      owner: implementer

- [x] T-009 | spec:001 | phase:1 | priority: security | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-002, T-005, T-007, T-008 | parallel: no | est: 3m | completed: 2026-05-29
      summary: Update docs/PLAYBOOK.md — add "How to legitimately edit constitution-class files" section covering FORCE_CONSTITUTION_EDIT escape hatch and out-of-Claude editor workflow
      files: docs/PLAYBOOK.md
      accept: grep -qE 'FORCE_CONSTITUTION_EDIT|legitimately edit constitution' docs/PLAYBOOK.md
      owner: implementer

- [x] T-010 | spec:001 | phase:1 | priority: security | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-002, T-003, T-005, T-006, T-007, T-008 | parallel: no | est: 3m | completed: 2026-05-29
      summary: Phase 1 exit gate — run validate.sh + security-invariants.sh + pre-bash-guard-bypass.sh + pre-edit-constitution-guard.sh; confirm all pass
      files: .claude/scripts/validate.sh
      accept: bash .claude/scripts/test/pre-bash-guard-bypass.sh && bash .claude/scripts/test/security-invariants.sh && bash .claude/scripts/test/pre-edit-constitution-guard.sh && bash .claude/scripts/validate.sh
      owner: implementer

#### Phase 2 — Loop correctness (AC-5..AC-7)

- [x] T-011 | spec:001 | phase:2 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | parallel: yes | est: 4m | completed: 2026-05-29
      summary: Write test for consecutive-aborts counter state machine — fresh state inits to count:0, increment on [!] write, reset on [x] write, hard-stop on count>=3; uses temp state file via STATE_FILE override
      files: .claude/scripts/test/loop-control.sh
      accept: bash -n .claude/scripts/test/loop-control.sh && grep -q 'consecutive-aborts' .claude/scripts/test/loop-control.sh
      owner: implementer

- [x] T-012 | spec:001 | phase:2 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-011 | parallel: no | est: 4m | completed: 2026-05-29
      summary: Create consecutive-aborts.json schema + initial empty state file (count:0, last_task:null, last_error_hash:null, last_pivot_attempt:0, updated:iso); add JSON Schema validator at templates/consecutive-aborts.schema.json
      files: .claude/state/consecutive-aborts.json, .claude/templates/consecutive-aborts.schema.json
      accept: jq -e '.count == 0 and (.last_pivot_attempt | type == "number")' .claude/state/consecutive-aborts.json && jq -e '.properties.count.type == "integer"' .claude/templates/consecutive-aborts.schema.json
      owner: implementer

- [x] T-013 | spec:001 | phase:2 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | parallel: yes | est: 3m | completed: 2026-05-29
      summary: Author pivot-prompt.md template — researcher subagent prompt instructing alternative-approach generation, ≤2 alternatives, returns <alternative> block
      files: .claude/templates/pivot-prompt.md
      accept: test -f .claude/templates/pivot-prompt.md && grep -qE '<alternative>|alternative approach' .claude/templates/pivot-prompt.md
      owner: implementer

- [x] T-014 | spec:001 | phase:2 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-012, T-013 | parallel: no | est: 5m | completed: 2026-05-29
      summary: Extend loop-iteration.sh — read/write consecutive-aborts.json via write_atomic, increment on [!], zero on [x], spawn researcher on 2nd same-task abort with pivot-prompt.md, hard-stop on count>=3 with explicit "consecutive-abort cap reached" message; new exit codes (0/1/2)
      files: .claude/scripts/loop-iteration.sh
      accept: bash -n .claude/scripts/loop-iteration.sh && grep -qE 'consecutive-aborts\.json|consecutive-abort cap reached' .claude/scripts/loop-iteration.sh && bash .claude/scripts/test/loop-control.sh
      owner: implementer

- [x] T-015 | spec:001 | phase:2 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-014 | parallel: yes | est: 3m | completed: 2026-05-29
      summary: Update autopilot SKILL.md — add explicit Phase 3.5 PIVOT tier section, remove LLM-only 3-strike rule prose (delegated to loop-iteration.sh)
      files: .claude/skills/autopilot/SKILL.md
      accept: grep -qE 'PIVOT tier|Phase 3\.5' .claude/skills/autopilot/SKILL.md && ! grep -qE '^\- LLM enforces 3-strike' .claude/skills/autopilot/SKILL.md
      owner: implementer

- [x] T-016 | spec:001 | phase:2 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | parallel: yes | est: 4m | completed: 2026-05-29
      summary: Write test for oq-aging.sh — seed an [OQ-1] item in a spec with backdated created:>7d, run script, assert P1-spec task appears in tasks/TASKS.md with last_touched and back-link
      files: .claude/scripts/test/oq-aging.sh
      accept: bash -n .claude/scripts/test/oq-aging.sh && grep -q 'OQ-' .claude/scripts/test/oq-aging.sh
      owner: implementer

- [x] T-017 | spec:001 | phase:2 | priority: P1-spec | created: 2026-05-29 | last\*touched: 2026-05-29 | deps: T-016 | parallel: no | est: 5m | completed: 2026-05-29
      summary: Implement oq-aging.sh — scan specs/active/\*\*/\_.md for [OQ-N] items >7d old, append RESOLVE: P1-spec task per item with last_touched + back-link, idempotent (skip if already appended), uses with_tasks_lock
      files: .claude/scripts/oq-aging.sh
      accept: test -x .claude/scripts/oq-aging.sh && bash -n .claude/scripts/oq-aging.sh && bash .claude/scripts/test/oq-aging.sh
      owner: implementer

- [x] T-018 | spec:001 | phase:2 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-017 | parallel: yes | est: 3m | completed: 2026-05-29
      summary: Wire oq-aging.yml daily routine — schedule daily, invoke .claude/scripts/oq-aging.sh; add harness-validate.yml step that confirms consecutive-aborts.json schema validates
      files: .claude/routines/oq-aging.yml, .github/workflows/harness-validate.yml
      accept: test -f .claude/routines/oq-aging.yml && grep -q 'oq-aging.sh' .claude/routines/oq-aging.yml && grep -q 'consecutive-aborts' .github/workflows/harness-validate.yml

  owner: implementer

#### Phase 3 — Operational (AC-8..AC-10)

- [ ] T-019 | spec:001 | phase:3 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | parallel: yes | est: 4m
      summary: Write test for lint-silent-failures.sh — seed fixtures with || true, 2>/dev/null, set -uo pipefail (no -e), and # JUSTIFIED: annotations; assert unjustified count surfaced correctly
      files: .claude/scripts/test/lint-silent-failures.sh
      accept: bash -n .claude/scripts/test/lint-silent-failures.sh && grep -q 'JUSTIFIED' .claude/scripts/test/lint-silent-failures.sh
      owner: implementer

- [ ] T-020 | spec:001 | phase:3 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-019 | parallel: no | est: 5m
      summary: Implement lint-silent-failures.sh — grep .claude/scripts and .claude/hooks for silent-error patterns, emit .claude/state/silent-failure-audit.json with {path,line,pattern,justified,justification}, exit non-zero when any unjustified
      files: .claude/scripts/lint-silent-failures.sh
      accept: test -x .claude/scripts/lint-silent-failures.sh && bash .claude/scripts/test/lint-silent-failures.sh
      owner: implementer

- [ ] T-021 | spec:001 | phase:3 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-020 | parallel: yes | est: 3m
      summary: Wire silent-failure-audit.yml workflow — run lint-silent-failures.sh on PR, fail if .unjustified > 0
      files: .github/workflows/silent-failure-audit.yml
      accept: test -f .github/workflows/silent-failure-audit.yml && grep -q 'lint-silent-failures.sh' .github/workflows/silent-failure-audit.yml
      owner: implementer

- [x] T-022 | spec:001 | phase:3 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-020 | parallel: no | est: 5m | completed: 2026-05-29
      summary: One-time sweep — annotate every existing intentional silent-error pattern in .claude/scripts and .claude/hooks with # JUSTIFIED: <reason> within 3 lines; ensure lint-silent-failures.sh now emits unjustified == 0
      files: .claude/scripts, .claude/hooks
      accept: bash .claude/scripts/lint-silent-failures.sh && jq -e '.unjustified == 0' .claude/state/silent-failure-audit.json
      owner: implementer

- [x] T-023 | spec:001 | phase:3 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | parallel: yes | est: 4m | completed: 2026-05-29
      summary: Write test for gc-tasks/gc-verify/gc-logs — seed tasks/TASKS.md >2000 lines + old verify/ dirs >30d + .log files >50MB, assert each script moves/rotates correctly and is idempotent
      files: .claude/scripts/test/gc-suite.sh
      accept: bash -n .claude/scripts/test/gc-suite.sh && grep -cE 'gc-tasks|gc-verify|gc-logs' .claude/scripts/test/gc-suite.sh | awk '{exit ($1 < 3)}'
      owner: implementer

- [x] T-024 | spec:001 | phase:3 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-023 | parallel: no | est: 5m | completed: 2026-05-29
      summary: Implement gc-tasks.sh + gc-verify.sh + gc-logs.sh — task archival >2000 lines moving [x]/[s] >30d into tasks/archive/TASKS-YYYY-MM.md; verify/ dirs >30d moved to verify/archive then pruned after 60d; .log files >50MB rotated to .log.1..5 with truncation; all idempotent
      files: .claude/scripts/gc-tasks.sh, .claude/scripts/gc-verify.sh, .claude/scripts/gc-logs.sh
      accept: test -x .claude/scripts/gc-tasks.sh && test -x .claude/scripts/gc-verify.sh && test -x .claude/scripts/gc-logs.sh && bash .claude/scripts/test/gc-suite.sh
      owner: implementer

- [x] T-025 | spec:001 | phase:3 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-024 | parallel: yes | est: 3m | completed: 2026-05-29
      summary: Wire gc-nightly.yml routine — schedule nightly, chain gc-tasks/gc-verify/gc-logs (or chain into existing dream-cron.yml)
      files: .claude/routines/gc-nightly.yml
      accept: test -f .claude/routines/gc-nightly.yml && grep -qE 'gc-tasks|gc-verify|gc-logs' .claude/routines/gc-nightly.yml
      owner: implementer

- [x] T-026 | spec:001 | phase:3 | priority: P1-spec | created: 2026-05-29 | last*touched: 2026-05-29 | parallel: no | est: 4m | completed: 2026-05-29
      summary: Modify pre-bash-dep-freshness.sh to fail CLOSED (emit permissionDecision ask) when api.osv.dev or registry returns network error (non-2xx, DNS failure, timeout); CLAUDE_CODE_AUTO_MODE=1 contexts accept ask after 5s classifier delay; add inline test that exercises a simulated network failure
      files: .claude/hooks/pre-bash-dep-freshness.sh, .claude/scripts/test/pre-bash-dep-freshness.sh
      accept: bash -n .claude/hooks/pre-bash-dep-freshness.sh && grep -qE 'permissionDecision.\_ask|permissionDecision":[[:space:]]*"ask' .claude/hooks/pre-bash-dep-freshness.sh && bash .claude/scripts/test/pre-bash-dep-freshness.sh
      owner: implementer

#### Phase 4 — Reconciliation (AC-11..AC-15)

- [x] T-027 | spec:001 | phase:4 | priority: normal | created: 2026-05-29 | last_touched: 2026-05-29 | parallel: yes | est: 4m | completed: 2026-05-29
      summary: Write test for check-model-consistency.sh — seed an agent .md with mismatched model: field vs CLAUDE.md §V; assert script exits non-zero; assert <!-- model-consistency: ignore --> marker bypasses
      files: .claude/scripts/test/check-model-consistency.sh
      accept: bash -n .claude/scripts/test/check-model-consistency.sh && grep -q 'model-consistency' .claude/scripts/test/check-model-consistency.sh
      owner: implementer

- [x] T-028 | spec:001 | phase:4 | priority: normal | created: 2026-05-29 | last\*touched: 2026-05-29 | deps: T-027 | parallel: no | est: 5m | completed: 2026-05-29
      summary: Implement check-model-consistency.sh — parse §V table from .claude/CLAUDE.md, walk .claude/agents/**/\*.md, .claude/skills/**/SKILL.md, .claude/routines/\*\*/\_.yml, docs/AUTOPILOT.md, docs/ARCHITECTURE.md; verify every model: matches; honor ignore marker
      files: .claude/scripts/check-model-consistency.sh
      accept: test -x .claude/scripts/check-model-consistency.sh && bash .claude/scripts/test/check-model-consistency.sh
      owner: implementer

- [x] T-029 | spec:001 | phase:4 | priority: normal | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-028 | parallel: yes | est: 3m | completed: 2026-05-29
      summary: Wire model-consistency.yml workflow — run check-model-consistency.sh on PR
      files: .github/workflows/model-consistency.yml
      accept: test -f .github/workflows/model-consistency.yml && grep -q 'check-model-consistency.sh' .github/workflows/model-consistency.yml
      owner: implementer

- [x] T-030 | spec:001 | phase:4 | priority: normal | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-028 | parallel: no | est: 4m | completed: 2026-05-29
      summary: Reconcile model: mismatches across .claude/agents/**, .claude/skills/**, .claude/routines/\*\*, docs/AUTOPILOT.md, docs/ARCHITECTURE.md against §V — fix any divergent fields so check-model-consistency.sh exits 0
      files: .claude/agents, .claude/skills, .claude/routines, docs/AUTOPILOT.md, docs/ARCHITECTURE.md
      accept: bash .claude/scripts/check-model-consistency.sh
      owner: implementer

- [x] T-031 | spec:001 | phase:4 | priority: normal | created: 2026-05-29 | last_touched: 2026-05-29 | parallel: yes | est: 5m | completed: 2026-05-29
      summary: Author .claude/skills/dream/SKILL.md body — define when_to_use trigger, consolidate MEMORY.md, archive stale instincts, run memory-gc.sh enforce; reference auto-dream-check.sh trigger contract
      files: .claude/skills/dream/SKILL.md
      accept: test -f .claude/skills/dream/SKILL.md && grep -qE '^---' .claude/skills/dream/SKILL.md && grep -qE 'memory-gc\.sh' .claude/skills/dream/SKILL.md && grep -qE 'name:[[:space:]]\*dream' .claude/skills/dream/SKILL.md
      owner: implementer

- [x] T-032 | spec:001 | phase:4 | priority: normal | created: 2026-05-29 | last_touched: 2026-05-29 | parallel: yes | est: 3m | completed: 2026-05-29
      summary: Modify setup.sh greenfield branch — write empty .claude/state/adopt/uncharacterized-paths.txt with header-comment so verify.sh characterization gate is active on greenfield (AC-15)
      files: .claude/scripts/setup.sh
      accept: grep -q 'uncharacterized-paths.txt' .claude/scripts/setup.sh
      owner: implementer

- [x] T-033 | spec:001 | phase:4 | priority: normal | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-032 | parallel: no | est: 3m | completed: 2026-05-29
      summary: Modify setup.sh — dispatch daily-batch.yml once on initial install via gh workflow run daily-batch.yml so first PR after setup passes merge-gate.yml (AC-14)
      files: .claude/scripts/setup.sh
      accept: grep -qE 'gh workflow run daily-batch\.yml|daily-batch\.yml' .claude/scripts/setup.sh
      owner: implementer

- [x] T-034 | spec:001 | phase:4 | priority: normal | created: 2026-05-29 | last_touched: 2026-05-29 | parallel: yes | est: 4m | completed: 2026-05-29
      summary: Reconcile budgets — make .claude/routines/overnight-build.yml the single source for wall-clock/cost/turn budgets; update docs/AUTOPILOT.md to reference the YAML keys rather than restating numeric values (AC-12)
      files: docs/AUTOPILOT.md, .claude/routines/overnight-build.yml
      accept: grep -qE 'overnight-build\.yml' docs/AUTOPILOT.md && grep -qE 'wall_clock|cost_cap|turn' .claude/routines/overnight-build.yml
      owner: implementer

- [x] T-035 | spec:001 | phase:4 | priority: normal | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-028, T-031, T-032, T-033, T-034 | parallel: no | est: 3m
      summary: Phase 4 exit gate — run check-model-consistency.sh and confirm dream skill, uncharacterized-paths.txt fixture, AUTOPILOT/overnight-build reconciliation all in place
      files: .claude/scripts/check-model-consistency.sh
      accept: bash .claude/scripts/check-model-consistency.sh && test -f .claude/skills/dream/SKILL.md && grep -q '## ' .claude/skills/dream/SKILL.md && grep -q 'uncharacterized-paths.txt' .claude/scripts/setup.sh
      owner: implementer

- [x] T-036 | spec:001 | phase:4 | priority: normal | created: 2026-05-29 | last_touched: 2026-05-29 | parallel: yes | est: 3m
      summary: Add JSON Schema for consecutive-aborts.json under .claude/templates and ensure setup.sh writes initial state file when missing (defensive bootstrap)
      files: .claude/scripts/setup.sh, .claude/templates/consecutive-aborts.schema.json
      accept: jq -e '.required[]' .claude/templates/consecutive-aborts.schema.json | grep -q count && grep -q 'consecutive-aborts.json' .claude/scripts/setup.sh
      owner: implementer

#### Phase 5 — claw-code adoptions (AC-16..AC-21)

- [x] T-037 | spec:001 | phase:5 | priority: normal | created: 2026-05-29 | last_touched: 2026-05-29 | parallel: yes | est: 4m
      summary: Author lane-event-schema.json — JSON Schema draft 2020-12 for {ts, stream_id, event in {lane.started, lane.red, lane.green, lane.blocked, lane.finished}, payload object}
      files: .swarms/templates/lane-event-schema.json
      accept: jq -e '.["$schema"] | test("2020-12")' .swarms/templates/lane-event-schema.json && jq -e '.properties.event.enum | length >= 5' .swarms/templates/lane-event-schema.json
      owner: implementer

- [x] T-038 | spec:001 | phase:5 | priority: normal | created: 2026-05-29 | last_touched: 2026-05-29 | parallel: yes | est: 4m
      summary: Write swarm-events smoke test — spawn single mock stream end-to-end, assert JSONL events appear in .swarms/events/<stream-id>.jsonl with schema-valid lane.started + lane.finished
      files: .claude/scripts/test/swarm-events-smoke.sh
      accept: bash -n .claude/scripts/test/swarm-events-smoke.sh && grep -q 'lane.finished' .claude/scripts/test/swarm-events-smoke.sh
      owner: implementer

- [x] T-039 | spec:001 | phase:5 | priority: normal | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-037, T-038 | parallel: no | est: 4m
      summary: Modify post-bash-log.sh to emit lane.red/lane.green/lane.blocked JSONL events to .swarms/events/<stream-id>.jsonl (append-only, O_APPEND atomicity); honor schema
      files: .claude/hooks/post-bash-log.sh
      accept: grep -qE 'lane\.(red|green|blocked)' .claude/hooks/post-bash-log.sh && grep -q '.swarms/events/' .claude/hooks/post-bash-log.sh
      owner: implementer

- [x] T-040 | spec:001 | phase:5 | priority: normal | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-037 | parallel: yes | est: 3m
      summary: Modify subagent-stop.sh to emit lane.finished JSONL event when a swarm stream subagent stops
      files: .claude/hooks/subagent-stop.sh
      accept: grep -q 'lane.finished' .claude/hooks/subagent-stop.sh && grep -q '.swarms/events/' .claude/hooks/subagent-stop.sh
      owner: implementer

- [x] T-041 | spec:001 | phase:5 | priority: normal | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-039 | parallel: yes | est: 4m
      summary: Modify session-heartbeat.sh — compute WORKSPACE_FP via portable md5/md5sum, namespace session writes under .claude/sessions/$WORKSPACE_FP/; write .swarms/streams/<id>/state.json with worker-state-machine transitions (spawning|trust_required|ready_for_prompt|prompt_accepted|running|finished|failed)
      files: .claude/hooks/session-heartbeat.sh
      accept: grep -qE 'WORKSPACE_FP|md5sum|md5 ' .claude/hooks/session-heartbeat.sh && grep -qE '\.swarms/streams/.\*state\.json' .claude/hooks/session-heartbeat.sh && grep -qE 'ready_for_prompt' .claude/hooks/session-heartbeat.sh
      owner: implementer

- [x] T-042 | spec:001 | phase:5 | priority: normal | created: 2026-05-29 | last_touched: 2026-05-29 | parallel: yes | est: 4m
      summary: Implement branch-freshness.sh + wire as first step of verify.sh — warn (do not block) when branch diverges from main >50 commits or >7 days; honor SKIP_BRANCH_CHECK=1
      files: .claude/scripts/branch-freshness.sh, .claude/scripts/verify.sh
      accept: test -x .claude/scripts/branch-freshness.sh && bash -n .claude/scripts/branch-freshness.sh && grep -q 'branch-freshness.sh' .claude/scripts/verify.sh && grep -q 'SKIP_BRANCH_CHECK' .claude/scripts/branch-freshness.sh
      owner: implementer

- [x] T-043 | spec:001 | phase:5 | priority: normal | created: 2026-05-29 | last_touched: 2026-05-29 | parallel: yes | est: 4m
      summary: Author anti-slop-reviewer agent — eight-class triage (actionable-bug, actionable-docs, actionable-feature, duplicate, spam, generated-slop, security-sensitive, not-reproducible); frontmatter model:sonnet per §V
      files: .claude/agents/quality/anti-slop-reviewer.md
      accept: test -f .claude/agents/quality/anti-slop-reviewer.md && grep -qE '^model:[[:space:]]\*sonnet' .claude/agents/quality/anti-slop-reviewer.md && grep -cE 'actionable-bug|actionable-docs|actionable-feature|duplicate|spam|generated-slop|security-sensitive|not-reproducible' .claude/agents/quality/anti-slop-reviewer.md | awk '{exit ($1 < 8)}'
      owner: implementer

- [x] T-044 | spec:001 | phase:5 | priority: normal | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-043 | parallel: no | est: 3m
      summary: Wire anti-slop-reviewer into claude-review.yml as additional reviewer pass; skip when PR has label human-author; first 30 days advisory (comment-only)
      files: .github/workflows/claude-review.yml
      accept: grep -q 'anti-slop-reviewer' .github/workflows/claude-review.yml && grep -q 'human-author' .github/workflows/claude-review.yml
      owner: implementer

- [x] T-045 | spec:001 | phase:5 | priority: normal | created: 2026-05-29 | last_touched: 2026-05-29 | parallel: yes | est: 4m
      summary: Write test for validate.sh --json — assert default text mode unchanged, --json emits valid JSON with schema_version, categories[], summary{passed,warned,failed,overall}
      files: .claude/scripts/test/validate-json.sh
      accept: bash -n .claude/scripts/test/validate-json.sh && grep -qE 'schema_version|--json' .claude/scripts/test/validate-json.sh
      owner: implementer

- [x] T-046 | spec:001 | phase:5 | priority: normal | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-045 | parallel: no | est: 5m
      summary: Add --json flag to validate.sh — text mode unchanged for back-compat; --json emits {schema_version:1, generated_at, categories:[{name,status,checked,failures,warnings}], summary}
      files: .claude/scripts/validate.sh
      accept: bash .claude/scripts/validate.sh --json | jq -e '.schema_version == 1 and (.summary.overall | test("^(pass|warn|fail)$"))' && bash .claude/scripts/test/validate-json.sh
      owner: implementer

- [x] T-047 | spec:001 | phase:5 | priority: normal | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-046 | parallel: no | est: 3m
      summary: Modify harness-validate.yml to consume validate.sh --json and render per-category annotations on PR
      files: .github/workflows/harness-validate.yml
      accept: grep -q 'validate.sh --json' .github/workflows/harness-validate.yml
      owner: implementer

#### Phase 6 — Atomicity & docs (AC-22..AC-25)

- [x] T-048 | spec:001 | phase:6 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | parallel: yes | est: 4m
      summary: Write atomic-write self-test — exercise write_atomic with stdin and inline content, assert mv -n collision returns 1, assert successful write returns 0, assert tmp file in same dir as target
      files: .claude/scripts/test/atomic-write.sh
      accept: bash -n .claude/scripts/test/atomic-write.sh && grep -q 'write_atomic' .claude/scripts/test/atomic-write.sh
      owner: implementer

- [x] T-049 | spec:001 | phase:6 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-048 | parallel: no | est: 4m
      summary: Implement .claude/scripts/lib/atomic-write.sh — sourced library exposing write_atomic <target> [<content>] using mktemp in same dir + mv -n; returns 0/1/2 per spec contract; library exempt from executable-bit requirement
      files: .claude/scripts/lib/atomic-write.sh
      accept: test -f .claude/scripts/lib/atomic-write.sh && bash -n .claude/scripts/lib/atomic-write.sh && bash .claude/scripts/test/atomic-write.sh
      owner: implementer

- [x] T-050 | spec:001 | phase:6 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-049 | parallel: no | est: 5m
      summary: Migrate direct-redirect state writers in .claude/scripts and .claude/hooks to source atomic-write.sh + call write_atomic/replace_atomic (replace_atomic for overwrite-mode state per the AC-22 semantics decision); ensure workflow-state.sh write covered
      files: .claude/scripts, .claude/hooks
      accept: test -z "$(grep -rnE '[^>2] *> *[^ ]*\.json([^a-zA-Z]|$)' .claude/scripts/ .claude/hooks/ | grep -vE 'lib/atomic-write\.sh|\.tmp|<<|EOF|JUSTIFIED:|echo |Usage:|:[0-9]+:[[:space:]]\*#' )"
      owner: implementer

- [x] T-051 | spec:001 | phase:6 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-050 | parallel: yes | est: 4m
      summary: Harden workflow-state.sh — when invoked outside a git repo, emit {phase:null,next:null,streak:0,warned_at:0} state file via write_atomic and empty additionalContext; smoke-test in non-git tmp directory
      files: .claude/hooks/workflow-state.sh, .claude/scripts/test/workflow-state-no-git.sh
      accept: bash -n .claude/hooks/workflow-state.sh && bash -n .claude/scripts/test/workflow-state-no-git.sh && bash .claude/scripts/test/workflow-state-no-git.sh
      owner: implementer

- [x] T-052 | spec:001 | phase:6 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | parallel: yes | est: 4m
      summary: Write test for audit-doc-claims.sh — seed a fake doc referencing a non-existent gate; assert script exits non-zero; assert real-gate refs pass
      files: .claude/scripts/test/audit-doc-claims.sh
      accept: bash -n .claude/scripts/test/audit-doc-claims.sh && grep -qE 'enforced by|blocked by|gated by' .claude/scripts/test/audit-doc-claims.sh
      owner: implementer

- [x] T-053 | spec:001 | phase:6 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-052 | parallel: no | est: 5m
      summary: Implement audit-doc-claims.sh — scan docs/**/\*.md, CLAUDE.md, .claude/CLAUDE.md, .claude/skills/**/SKILL.md for "enforced by"/"blocked by"/"required by"/"gated by" claims; verify each named gate exists as exec script, workflow YAML, or hook
      files: .claude/scripts/audit-doc-claims.sh
      accept: test -x .claude/scripts/audit-doc-claims.sh && bash .claude/scripts/test/audit-doc-claims.sh
      owner: implementer

- [x] T-054 | spec:001 | phase:6 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-053 | parallel: yes | est: 3m
      summary: Wire doc-claims-audit.yml workflow on PR — run audit-doc-claims.sh, fail if any orphan claim
      files: .github/workflows/doc-claims-audit.yml
      accept: test -f .github/workflows/doc-claims-audit.yml && grep -q 'audit-doc-claims.sh' .github/workflows/doc-claims-audit.yml
      owner: implementer

- [x] T-055 | spec:001 | phase:6 | priority: P1-spec | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-006 | parallel: yes | est: 5m
      summary: Complete security-invariants.sh — add tests for every remaining invariant in .claude/CLAUDE.md §VII + §X and root CLAUDE.md "Security invariants" (secrets deny-list, disableBypassPermissionsMode, MCP version pinning, gitleaks present, destructive op blocks, sandbox in auto, evidence-gate required)
      files: .claude/scripts/test/security-invariants.sh
      accept: bash .claude/scripts/test/security-invariants.sh && grep -cE 'INVARIANT-?[0-9]+' .claude/scripts/test/security-invariants.sh | awk '{exit ($1 < 10)}'
      owner: implementer

#### Phase 7 — Regression safety + observation (AC-26..AC-27)

- [ ] T-056 | spec:001 | phase:7 | priority: cleanup | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-010, T-018, T-026, T-035, T-047, T-055 | parallel: no | est: 4m
      summary: Run full validate.sh against post-hardening tree; expect zero new failures vs pre-hardening baseline (pre-existing python3+pyyaml warning permitted); capture diff to verify/2026-05-29-phase7/validate-baseline-vs-hardened.txt
      files: .claude/scripts/validate.sh
      accept: bash .claude/scripts/validate.sh
      owner: implementer

- [ ] T-057 | spec:001 | phase:7 | priority: cleanup | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-056 | parallel: yes | est: 5m
      summary: Run paired 8-hour autopilot regression — baseline (pre-phase1 checkout) vs hardened (post-phase6) with identical canonical overnight prompt; compute .classifier_deny_count diff; assert hardened count <= 2x baseline
      files: verify/2026-05-29-phase7-regression
      accept: bash .claude/scripts/local-overnight-build.sh --regression-pair --baseline-ref pre-phase1 --hardened-ref HEAD --out verify/2026-05-29-phase7-regression
      owner: implementer

- [ ] T-058 | spec:001 | phase:7 | priority: cleanup | created: 2026-05-29 | last_touched: 2026-05-29 | deps: T-057 | parallel: no | est: 4m
      summary: Emit verify/2026-05-29-phase7-regression/REPORT.md with classifier-deny counts, operator-intervention totals, AC-by-AC coverage table, and rollback recommendation if hardened > 2x baseline (auto_rollback_threshold.custom)
      files: verify/2026-05-29-phase7-regression/REPORT.md
      accept: test -f verify/2026-05-29-phase7-regression/REPORT.md && grep -qE 'classifier_deny_count|operator-intervention' verify/2026-05-29-phase7-regression/REPORT.md
      owner: implementer

## Spec 001 critical path

Phase 1: T-001 → T-002 → T-005 → T-007 → T-010 (security blockers; rewrites pre-bash-guard, registers constitution-guard hook, wires evidence-gate into ruleset, exits Phase 1)
End-to-end: T-001 → T-002 → T-005 → T-010 → T-014 → T-018 → T-022 → T-026 → T-035 → T-047 → T-055 → T-056 → T-057 → T-058

## Archive

Move completed batches here when the plan ships. Keep the file < 2000 lines. When this file exceeds 2000 lines, move ARCHIVE section to `tasks/archive/TASKS-<YYYY-Q>.md` (see `.claude/routines/quarterly-archive.yml`).
