# Gap-Fix Ledger — 2026-06-12

All **63 gaps** from the 10-dimension audit (`docs/research/harness-gaps-10dim.md`, commit `63ba879`)
implemented and proven. Proof rig: `verify/2026-06-12-gap-fixes/test-gap-fixes.sh` — **164/164 passing**
(re-prove after install with `INSTALLED=1 bash verify/2026-06-12-gap-fixes/test-gap-fixes.sh`).

**Fix classes:**
- **direct** — edited in the live tree (agent-writable paths)
- **staged** — constitution-class file; copy under `staged/<repo-path>`, operator installs via `staged/install.sh`

| Gap | Sev | Fix | Class | Proof (rig tests) |
|---|---|---|---|---|
| G1 | high | cost-report.sh computes cache_read/creation tokens + cache_hit_rate → cost-summary.json; budget.sh statusline shows `cache:N%`; doctor warns < `CACHE_HIT_MIN` | direct | G1 ×3 |
| G2 | med | pre-edit-constitution-guard.sh denies `.claude/skills/*` (memory.proposed staging path still allowed) | staged | G2 ×3 |
| G3 | low | validate.sh checks `ENABLE_TOOL_SEARCH=true` + `CLAUDE_CODE_AUTO_COMPACT_WINDOW` set | direct | G3 ×2 |
| G4 | low | user-prompt-context.sh buckets dirty count (clean/dirty(1-9)/dirty(10+)); workflow-state.sh drops the streak integer | staged | G4 ×3 |
| G5 | low | docs/RESEARCH.md TTL passage made actionable; context-budget skill "Cache facts" section | direct | G5 ×2 |
| G6 | high | pre-spawn-cost-gate.sh registered under `Agent\|Task` matcher in settings.json; validate.sh matcher-coverage check (the one EXPECTED pre-install validate failure) | staged | G6 ×3 |
| G7 | med | outputStyle "Concise" in settings.json; context-monitor.sh per-turn growth warning (`CONTEXT_MONITOR_DELTA_WARN`) | staged | G7 ×2 |
| G8 | med | token-budget skill created at `.claude/skills/token-budget/SKILL.md`; validate.sh dangling-skill-ref check | direct | G8 ×2 |
| G9 | med | context-monitor.sh NEW hook — transcript-size fill estimate, 60/80% once-per-session warnings | staged | G9 ×3 |
| G10 | med | memory-gc.sh header matches real wiring; gc-nightly.yml step 4 runs `memory-gc.sh enforce` | direct | G10 ×2 |
| G11 | low | pre-spawn-cost-gate.sh 16KB + 90%-cap tiers hard-DENY under CLAUDE_AUTOPILOT=1 / overnight run-lock ("ask" auto-resolves in Auto Mode) | staged | G11 ×2 |
| G12 | high | auto-dream-check.sh appends candidate note to dream prompt (draft via skill-creator, mark consumed:true) | staged | G12 ×2 |
| G13 | high | dream-review --approve/--revert preserve skills/ via mktemp shuffle; auto-dream-check.sh skills_keep mirror | direct+staged | G13 ×3 |
| G14 | med | regen-skill-registry.sh emits `.claude/state/skill-triggers.tsv` from quoted frontmatter phrases (176 triggers / 44 skills); router consumes it | direct+staged | G14 ×3 |
| G15 | med | triggers.yml merged into skill-triggers.tsv by regen; dream-review --approve-skill runs regen | direct | G15 ×2 |
| G16 | med | session-start-context.sh regenerates REGISTRY.md + TSV each session; validate.sh row-count freshness check | staged+direct | G16 ×2 |
| G17 | med | skill-use-log.sh NEW hook on Skill matcher → skill-use.jsonl; doctor adherence check | staged+direct | G17 ×3 |
| G18 | low | task-signature-detector.sh awk rewrite: ≥5 count AND ≥2 sessions AND ≥0.8 clean ratio (plus latent apostrophe-quoting bug fixed — candidates now actually emit) | staged | G18 ×3 |
| G19 | low | validate.sh enforces description ≤ maxSkillDescriptionChars; warns on missing when_to_use | direct | G19 ×2 |
| G20 | med | skill-router.sh operational arms: incident→/incident-start, harness-doctor, triage, deps-audit, adopt | staged | G20 ×3 |
| G21 | med | "/atlas refresh" dropped from session-start-context.sh; validate.sh hook-injected-command resolution check | staged+direct | G21 ×2 |
| G22 | med | validate.sh requires `disable-model-invocation: true` on all commands | direct | G22 ×1 |
| G23 | med | session-start-context.sh injects DREAM-PENDING banner when awaiting_review=true | staged | G23 ×2 |
| G24 | low | router hints for user-only commands framed "suggest the user run X" | staged | G24 ×2 |
| G25 | crit | instinct-extract.sh NEW — offset state, ≥50-observation gate, Haiku merge → instincts/active.yml; wired into auto-dream-check.sh + dream skill | direct+staged | G25 ×4 |
| G26 | high | instinct-promote.sh NEW — global store, candidate→global on 2nd distinct project; /instinct command | direct | G26 ×3 |
| G27 | high | subagent-stop.sh archives full NEXUS YAML to `.claude/memory/handoffs/<YYYY-MM>/` | staged | G27 ×2 |
| G28 | med | (with G12) dream prompt consumes _candidates.jsonl; consumed:true marking | staged | G28 (under G12 tests) |
| G29 | med | dream skill step 8 runs memory-promote.sh + learn-from-success.sh in-repo | direct | G29 ×1 |
| G30 | med | learn-from-success.sh `startswith("claude-opus")`; agent frequency from subagent.jsonl | direct | G30 ×2 |
| G31 | med | skill-router.sh matches instinct triggers from active.yml (confidence ≥0.5 gate) | staged | G31 ×2 |
| G32 | low | subagent-context.sh injects memory-recall for spec/plan paths; implementer.md recall blockquote | staged | G32 ×1 |
| G33 | high | (with G27) handoff archive + dream gathers `.claude/memory/handoffs/` + subagent.jsonl | staged+direct | G33 ×1 |
| G34 | high | architect/reviewer/debugger/security agents route memory content through NEXUS handoff (read-only agents can't Write); validate.sh guard | staged+direct | G34 ×4 |
| G35 | med | read-volume-nudge.sh NEW on Read matcher — delegation nudge every 8 reads/session | staged | G35 ×3 |
| G36 | med | = G6 (same matcher fix) | staged | G6 tests |
| G37 | med | subagent-stop.sh renders followup_tasks as checkboxes → findings-to-tasks.sh (lock-safe, idempotent) | staged | G37 ×2 |
| G38 | low | subagent-stop.sh soft tier logs missing_handoff_soft + "WARN (soft)" additionalContext | staged | G38 ×2 |
| G39 | crit | adr-new.sh NEW (auto-number, template transform, provenance stamp, reindex); ADRs 0001-0003 backfilled; validate.sh non-vacuous check; plan/ship skill hard rules | direct | G39 ×6 |
| G40 | high | adr-gate.yml NEW CI gate (surfaces in `.claude/adr-surfaces.txt` require decisions/ change or ADR ref); subagent-stop.sh warns on architect handoff with empty adrs_referenced | staged+direct | G40 ×6 |
| G41 | high | lint-exception-check.sh: security disables (# nosec, # noqa: S*, eslint-disable*security) require resolvable `ADR: NNNN` within 3 lines or decisions/ file in diff | direct | G41 ×2 |
| G42 | med | /adr-walk `--reverify <id>` stamps last_verified + reindexes; chain walk implemented (cycle-guarded) | direct | G42 ×3 |
| G43 | med | adr-new.sh stamps written_by + source_session from current-session.json | direct | G43 ×2 |
| G44 | low | template + adr-new.sh carry `subsystem:` grouping key | direct | G44 ×2 |
| G45 | low | session-start-context.sh staleness from content dates (last_verified else Date), not mtime; resolution path = `/adr-walk --reverify` | staged | G45 ×4 |
| G46 | high | CI gating reviewer → Sonnet 4.6 (cross-model vs Opus implementer); §V documents the rule; check-model-consistency.sh fails on drift | staged+direct | G46 ×4 |
| G47 | med | lint-trailers.sh NEW (Confidence/Scope-risk enums required, Not-tested warned; WIP/bots skipped); commitlint.yml step | direct+staged | G47 ×5 |
| G48 | med | stop-verify.sh requires PASS verdict + feature match; bypass advertisement dropped; blocks logged to .claude/state for doctor | staged+direct | G48 ×6 |
| G49 | med | evidence-gate.yml re-EXECUTES verify.sh smoke (+ journey + spec-match when rig exists) on head; divergence fails | staged | G49 ×2 |
| G50 | low | anti-slop wire-in date recorded (2026-05-29); doctor flags expired 30-day ramp still advisory; duplicate anti-slop job deduped to pr-review.yml; review citation/multi-pass format lint step | direct+staged | G50 ×5 |
| G51 | crit | spec-match.sh jq: tags count only from spec objects with ok==true / all tests passed; status-blind grep fallback replaced with loud UNPROVEN warning | direct | G51 ×2 |
| G52 | high | = G49 (CI re-runs the journey itself when e2e rig exists) | staged | G49 tests |
| G53 | high | evidence.json stamps commit + generated_at; gate requires evidence in PR diff, commit ancestor of head, spec matches PR-touched spec; spec-match wildcard fallback dropped | direct+staged | G53 ×5 |
| G54 | med | story-test-map.sh matches story-N.* / @story-N per story; cross-checks passing status vs results.json | direct | G54 ×3 |
| G55 | med | verify.sh E2E journey gate: runs playwright + spec-match for approved specs with e2e/<id>/ (SKIP_E2E_JOURNEY operator-gated) | direct | G55 ×3 |
| G56 | low | = G48 (verdict + feature-match in stop-verify.sh) | staged | G56 ×2 |
| G57 | low | evidence-gate.yml docs-only hatch: no-ac.json honored ONLY when diff touches exclusively docs-class paths | staged | G57 ×1 |
| G58 | high | loop-iteration.sh empty-backlog → IDEATE instruction + ideation-pending flag; overnight-build.yml END-OF-RUN ideation branch (propose-only, human promotes) | direct | G58 ×5 |
| G59 | med | feedback-score.sh NEW deterministic scorer (severity×ARR×renewal); feedback-triage.yml weekly routine; /feedback triage feeds scorer output to the clusterer | direct | G59 ×4 |
| G60 | med | doctor "feedback intake wiring" check (env keys actually set, not just servers present); active/closed .gitkeep seeds; ADOPTION.md wiring section | direct | G60 ×4 |
| G61 | med | scorer warns when >50% entries lack arr_band; /feedback documents ARR as operator-supplied | direct | G61 ×3 |
| G62 | low | roadmap-architect.md step 5b researcher brief mandate for net-new initiatives + Done-means item | staged | G62 ×2 |
| G63 | low | /okrs draft reads _triage-latest.md; /feedback link appends into refs array (awk, never clobbers) | direct | G63 ×3 |

## Known states until install

1. `bash .claude/scripts/validate.sh` fails with exactly ONE failure (G6 matcher-coverage) — this is the
   enforceability gate working; it clears when `staged/.claude/settings.json` installs.
   **Install BEFORE pushing** or `harness-validate.yml` CI will fail.
2. 3 validate warnings (security.md / debugger.md memory-write claims, /atlas dangling hint) also clear on install.
3. `check-model-consistency.sh` fails on the live tree (CI reviewer still Opus) until
   `staged/.github/workflows/claude-review.yml` installs.

## Bonus fixes found during implementation

- `task-signature-detector.sh`: apostrophe inside the single-quoted jq program silently broke every
  candidate emit — the root cause of the permanently-empty `_candidates.jsonl`.
- Stale `agent-*` workflow worktrees polluted validate (140 warnings) — removed; validate prunes `.claude/worktrees`.
- ADR template lacked top-level lifecycle frontmatter (`status:`/`created:`) — added so memory-GC and
  validate's lifecycle check work on generated ADRs.
