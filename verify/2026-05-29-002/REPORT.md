# Spec 002 — Audit Remediation — Final Evidence Report

**Spec:** specs/active/002-audit-remediation.md  
**Date:** 2026-05-29  
**Phases completed:** 1–8 (T-059 through T-110, T-093 operator-blocked)  
**AC-40: Evidence bundle emitted by collect-evidence.sh 002**

## Exit gate results

| Gate                            | Result           | Artifact                                            |
| ------------------------------- | ---------------- | --------------------------------------------------- |
| Phase 1 validate.sh             | ✓ 0 failures     | `verify/2026-05-29-002/T-066-validate-baseline.log` |
| Phase 2 validate.sh             | ✓ 0 failures     | `verify/2026-05-29-002/phase2-validate.log`         |
| Phase 3 validate.sh             | ✓ 0 failures     | `verify/2026-05-29-002/phase3-validate.log`         |
| Phase 4 validate.sh             | ✓ 0 failures     | `verify/2026-05-29-002/phase4-validate.log`         |
| Phase 5 validate.sh             | ✓ 0 failures     | `verify/2026-05-29-002/phase5-validate.log`         |
| Phase 6 validate.sh             | ✓ 0 failures     | `verify/2026-05-29-002/phase6-validate.log`         |
| Phase 7 validate.sh             | ✓ 0 failures     | `verify/2026-05-29-002/phase7-validate.log`         |
| validate-exit.log (AC-38)       | ✓ 0 failures     | `verify/2026-05-29-002/validate-exit.log`           |
| harness-doctor --json (AC-39)   | ✓ 0 failures     | `verify/2026-05-29-002/doctor-exit.json`            |
| collect-evidence.sh 002 (AC-40) | ✓ bundle emitted | `verify/2026-05-29-002-audit-remediation/`          |

## AC coverage summary

| Phase                                      | ACs          | Tasks        | Status                          |
| ------------------------------------------ | ------------ | ------------ | ------------------------------- |
| Phase 1 — Active code bugs                 | AC-1..AC-7   | T-059..T-066 | ✓ all done                      |
| Phase 2 — Gaps (workflow + loop detection) | AC-8..AC-13  | T-067..T-073 | ✓ all done                      |
| Phase 3 — Context + lifecycle              | AC-14..AC-20 | T-074..T-081 | ✓ all done                      |
| Phase 4 — Memory hardening                 | AC-21..AC-25 | T-082..T-088 | ✓ all done                      |
| Phase 5 — Security gap closures            | AC-26..AC-30 | T-089..T-094 | ✓ done (T-093 operator-blocked) |
| Phase 6 — claw-code adoptions              | AC-31..AC-36 | T-095..T-102 | ✓ all done                      |
| Phase 7 — Constitution compaction          | AC-37        | T-103..T-107 | ✓ all done                      |
| Phase 8 — Exit gates                       | AC-38..AC-40 | T-108..T-110 | ✓ all done                      |

## Operator-blocked task

**T-093** (AC-26): Narrow `Write(./**)` blanket in `settings.json` to per-dir allows +
extend constitution-guard deny-list to cover `tasks/TASKS.md` and `specs/active/`.

Blocked because `settings.json` and `pre-edit-constitution-guard.sh` are constitution-class
files — the auto-mode classifier hard-blocks self-modification of permission config.

**To complete T-093 manually:**

```bash
# 1. Narrow Write blanket in settings.json
FORCE_CONSTITUTION_EDIT=1 $EDITOR .claude/settings.json
#    Replace "Write(./**)" with per-dir entries: Write(src/**), Write(tests/**),
#    Write(specs/**), Write(plans/**), Write(tasks/**), Write(docs/**),
#    Write(verify/**), Write(.swarms/**), Write(.claude/memory/**),
#    Write(.claude/memory.proposed/**), Write(.claude/state/**),
#    Write(.claude/hooks/.log/**)

# 2. Add tasks/TASKS and specs/active to constitution guard deny-list
FORCE_CONSTITUTION_EDIT=1 $EDITOR .claude/hooks/pre-edit-constitution-guard.sh
#    Add to the case block:
#      tasks/TASKS.md)                          deny=1 ;;
#      specs/active/*)                          deny=1 ;;
```

## Files changed (key)

- `.claude/hooks/stop-verify.sh` — coordinator NEXUS enforcement (AC-3)
- `.claude/hooks/pre-bash-guard.sh` — exit 2 on deny paths, evasion patterns (AC-1, AC-5)
- `.claude/scripts/validate.sh` — force-bypass check, model-doc-consistency, constitution-size (AC-6, AC-7, AC-37)
- `.github/workflows/daily-batch.yml`, `iac-scan.yml`, `harness-validate.yml` — SHA pins (AC-2)
- `CLAUDE.md` — model routing corrected (AC-7)
- `.claude/settings.json` — removed gh issue/api read permissions (AC-20)
- `.claude/hooks/user-prompt-context.sh` — removed duplicate spec/plan injection (AC-18)
- `.claude/hooks/workflow-state.sh` — 8-phase detection (AC-19)
- `.github/workflows/stale-spec-check.yml` — weekly stale spec cron (AC-14)
- `.github/workflows/quarterly-archive.yml` — quarterly spec archive with ref rewrite (AC-15)
- `.swarms/templates/handoff.yaml` — tdd_state block (AC-25)
- `.claude/scripts/memory-gc.sh` — last_accessed eviction (AC-22)
- `.claude/skills/dream/SKILL.md` — contradiction detection step (AC-24)
- `.claude/hooks/subagent-stop.sh` — tdd_state auto-populate (AC-25)
- `.mcp.json` — context7 pinned (AC-29)
- `.claude/hooks/pre-write-secret-scan.sh` — PII scrubber covers OVERNIGHT_REPORT + verify/ (AC-30)
- `.claude/agents/core/coordinator.md` — ready_for_prompt gating (AC-31)
- `.claude/hooks/post-bash-log.sh` — lane.started, error.kind, retryable (AC-32)
- `.claude/scripts/requeue-failed.sh` — JSONL lane event reader (AC-32)
- `.github/workflows/pr-review.yml` — anti-slop triage pass (AC-36)
- `.claude/skills/constitution-compact/SKILL.md` — 300-line cap discipline (AC-37)
- `.claude/routines/constitution-compact-cron.yml` — quarterly cron (AC-37)
- `.claude/scripts/harness-doctor.sh` — --json health check (AC-35)
- `.claude/memory.proposed/constitution-diff.md` — constitution is 206/300 lines, no action needed
