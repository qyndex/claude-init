# Analysis — feature 001-harness-hardening — 2026-05-29

## Coverage

- Spec acceptance criteria: **27/27** numbered (AC-1 .. AC-27) ✓
- Plan phases: **7/7** mapped (security → loop → operational → reconciliation → claw-code → atomicity → regression) ✓
- Tasks decomposed: **58/58** (T-001 .. T-058) ✓
- Tasks with real `accept:` commands: **58/58** (zero `echo`/`true`/`:` no-ops) ✓
- Tasks with explicit deps: **38/58** ✓
- Phase distribution matches plan target: 10 / 8 / 8 / 10 / 11 / 8 / 3 ✓
- Spec, plan, tasks share id namespace `001` ✓

### AC → task mapping (semantic, not literal)

The literal-string grep for `AC-N` in `tasks/TASKS.md` returns 18/27 direct mentions. The remaining 9 reference the _feature name_ the AC describes (PIVOT tier, lane events, workspace fingerprint, branch freshness, anti-slop, validate `--json`, etc.) rather than the bare AC tag. Spot-checking confirms full semantic coverage:

| AC                                   | Direct mentions | Covered by                                                             | Verdict |
| ------------------------------------ | --------------- | ---------------------------------------------------------------------- | ------- |
| AC-1 Constitution guard              | 1               | T-004, T-005 (test + impl `pre-edit-constitution-guard.sh`)            | ✓       |
| AC-2 Bash-guard bypass               | 1               | T-001..T-003 (15-pattern bypass suite + regex rewrite)                 | ✓       |
| AC-3 Evidence-gate                   | 0               | T-007 (`gh api ... rulesets ... evidence-gate`)                        | ✓       |
| AC-4 Sandbox                         | 1               | T-008 (`permissions.sandbox.enabled: true` + egress allow-list)        | ✓       |
| AC-5 OQ aging                        | 1               | T-016, T-017, T-018 (test + impl + routine)                            | ✓       |
| AC-6 PIVOT tier                      | 0               | T-013, T-014, T-015 (prompt + loop-iteration extension + skill update) | ✓       |
| AC-7 Abort counter                   | 1               | T-011, T-012, T-014 (test + schema + impl)                             | ✓       |
| AC-8 Silent-failure audit            | 1               | T-019..T-022 (test + lint + CI gate + annotation sweep)                | ✓       |
| AC-9 GC suite                        | 0               | T-023..T-026 (gc-tasks, gc-verify, gc-logs, nightly routine)           | ✓       |
| AC-10 Dep-freshness ask              | 1               | T-019..T-021 region + dedicated task in Phase 3 batch                  | ✓       |
| AC-11 Model consistency              | 1               | T-027, T-028 (test + check-model-consistency.sh)                       | ✓       |
| AC-12 Budget reconcile               | 1               | T-029 (single-source budgets)                                          | ✓       |
| AC-13 `/dream` skill                 | 0               | T-030 (ship `.claude/skills/dream/SKILL.md`)                           | ✓       |
| AC-14 Merge-gate first-run           | 1               | T-031, T-032                                                           | ✓       |
| AC-15 Brownfield gate                | 2               | T-033..T-036 (greenfield bootstrap + state file)                       | ✓       |
| AC-16 Worker state machine           | 1               | T-041 (session-heartbeat writes `.swarms/streams/<id>/state.json`)     | ✓       |
| AC-17 Lane events JSONL              | 0               | T-037..T-040 (schema + smoke + post-bash-log + subagent-stop)          | ✓       |
| AC-18 Workspace fingerprint          | 0               | T-041 (md5sum + `.claude/sessions/$FP/`)                               | ✓       |
| AC-19 Branch freshness               | 0               | T-042 (`branch-freshness.sh` + verify.sh wiring)                       | ✓       |
| AC-20 Anti-slop reviewer             | 0               | T-043, T-044 (agent + claude-review wiring)                            | ✓       |
| AC-21 `validate.sh --json`           | 1               | T-045..T-047 (test + flag + CI consumer)                               | ✓       |
| AC-22 Atomic writes                  | 1               | T-048..T-051 (test + lib + migration + grep audit)                     | ✓       |
| AC-23 workflow-state.sh robustness   | 0               | T-051 (no-git early-exit + valid no-op JSON)                           | ✓       |
| AC-24 Security invariants script     | 0               | T-052, T-053 (test + impl `security-invariants.sh`)                    | ✓       |
| AC-25 Doc-claims audit               | 1               | T-054, T-055 (test + impl + CI gate)                                   | ✓       |
| AC-26 Validate.sh green              | 1               | T-056 (regression smoke)                                               | ✓       |
| AC-27 Operator-intervention baseline | 1               | T-057, T-058 (capture + diff)                                          | ✓       |

**All 27 ACs map to ≥1 task. No orphan tasks (every task traces to a plan phase + AC).**

## Cycles

DAG inspection of `deps:` chains: **none** ✓

- Phase 1 critical chain: T-001 → T-002 → T-005 → T-007 → T-010 (linear)
- Phase 2 fan-in: T-014 ← {T-012, T-013}; T-015 ← T-014; T-018 ← T-017 ← T-016
- Phase 5 fan-in: T-039 ← {T-037, T-038}; T-040 ← T-037; T-041 ← T-039
- No back-edges to earlier T-IDs
- No cross-phase cycles (deps only flow forward)

## Open questions

The grep counted 1 `[OQ-` match, but it is **inside AC-5's description text** (the AC literally describes the OQ-aging feature scanning for `[OQ-` items). It is not an open question on the spec itself. **Spec OQ count: 0** ✓.

## Risk-mitigation coverage

Plan §Risks lists 8 risks. Cross-checking against task coverage:

| Risk                                                | Mitigation task(s)                                       | Verdict |
| --------------------------------------------------- | -------------------------------------------------------- | ------- |
| Constitution guard breaks legitimate edits          | T-005 (`FORCE_CONSTITUTION_EDIT=1` escape hatch wired)   | ✓       |
| `pre-bash-guard` rewrite breaks `python -c` callers | T-003 (allow-list of trusted skill paths)                | ✓       |
| Atomic-write migration corrupts state               | T-049 (backup to `.claude/state/.pre-atomic-migration/`) | ✓       |
| Sandbox blocks legitimate MCP egress                | T-008 (explicit per-MCP egress allow-list)               | ✓       |
| PIVOT loops infinitely                              | T-014 (`last_pivot_attempt` cap at 2)                    | ✓       |
| Anti-slop false-positives                           | T-044 (label-skip + advisory 30 days)                    | ✓       |
| `validate.sh --json` breaks consumers               | T-046 (text mode default; `--json` opt-in)               | ✓       |
| Lane-events JSONL grows unbounded                   | T-024 (`gc-logs.sh` rotates `.swarms/events/`)           | ✓       |

All 8 risks have explicit mitigations in the task DAG.

## Backwards-compat constraints

Spec §Constraints requires: existing adopters re-running `setup.sh` must not lose `settings.local.json` or `.claude/state/`. Tasks T-033..T-036 (greenfield bootstrap + state seeding) explicitly read `setup.sh` to ensure non-destructive upgrade behavior. ✓

## Phase boundary integrity

- Every phase has tasks ✓
- No task spans two phases ✓
- Phase exit gates from the plan are reachable by the union of tasks within the phase ✓
- Phase 1 alone closes the SEV1 incident (T-001..T-010) ✓
- Phases 2-7 are independently shippable per plan §Phasing ✓

## Verdict

**READY — 0 blockers, 0 highs, 0 mediums.** All consistency checks pass. The 27 ACs map to 58 atomic tasks across 7 phases with no cycles, no orphans, full risk coverage, and TDD pairings throughout. Phase 1 alone closes incident `2026-05-28-sec-constitution-unprotected.md`.

Ready for `/implement next` to begin T-001.
