# E2E-Delivery Fix Campaign — Ledger

Source plan: `docs/research/harness-e2e-audit.md` (raw: `verify/2026-06-12-e2e-harness-audit/raw-audit.json`)
Pattern: direct fixes where writable; constitution-class files staged under `staged/` + `install.sh`; dual-mode rig `test-e2e-fixes.sh` (staged vs `INSTALLED=1`).

Status: `[ ]` pending · `[~]` in progress · `[x]` done+rig-proven · `[s]` skipped (reason)

## Phase 1 — Auto-mode safety

- [x] P1.1 failure-recovery-1 — task-status.sh CLI + tasks-lib primitive; spec-write carve-out; rewrite agent instructions
- [x] P1.2 security-automode-1,5 — PreToolUse matcher for filesystem-MCP writes; validate.sh invariant; §X wording
- [x] P1.3 hooks-engineering-1,2 security-automode-4 — re-scope pre-bash-guard patterns; secret-scan FP fixes
- [x] P1.4 hooks-engineering-3 security-automode-2 — pipe-to-shell + var-indirection; dep-freshness npx/uvx/bunx/pnpx/pipx
- [x] P1.5 hooks-engineering-4 greenfield-5 — fail-closed jq discipline in hooks + setup.sh + validate.sh
- [x] P1.6 autopilot-3 — stop_hook_active parsing; escalation instead of livelock
- [x] P1.7 brownfield-2 — pre-edit-legacy-guard.sh; human-only adopt approve
- [x] P1.8 security-automode-3 — drop Write/Edit from researcher + feedback-extractor; parent-persisted output

## Phase 2 — Verification/merge spine

- [ ] P2.1 greenfield-2,3 tdd-loop-2 — DECISION: un-ignore verify/**/{red,green}.log; setup.sh selective block; canonical check-tdd-ledger.sh; evidence-gate SKIP removal
- [ ] P2.2 tdd-loop-1,4 — unforgeable ledger (header parse, exit codes, timestamps, timeout, red_reason)
- [ ] P2.3 e2e-rig-2 ci-gates-3 — evidence-gate toolchain install (composite action); BYO services; unmute playwright install
- [ ] P2.4 e2e-rig-1 — webServer block in playwright evidence config
- [ ] P2.5 e2e-rig-3 — AC id normalization (spec-match, story-test-map, collect-evidence anchored grep)
- [ ] P2.6 greenfield-4 e2e-rig-4 — stack-aware AC proof; standalone evidence config; rig bootstrap; verifier/tester Write; path typo
- [ ] P2.7 stack-portability-1..4 — stack engine pass (verify.sh detect-stacks consumption, test-unit/integration rewrite, Python PM ladder, coverage polarity)
- [ ] P2.8 greenfield-1 — template-clean step in setup.sh (factory dev state stays out of new projects)
- [ ] P2.9 ci-gates-1,2 — required checks in main-protection.json; setup.sh ruleset apply offer; live-ruleset drift checks
- [ ] P2.10 brownfield-6 — characterization exemption in check-tdd-ledger.sh; stronger char-gate

## Phase 3 — Mechanize the loop

- [ ] P3.1 spec-pipeline-2 tdd-loop-3 — next-task.sh canonical picker; wire into loop-iteration + /implement + workflow-state
- [ ] P3.2 autopilot-2,5 — loop-control producer (post-write-roadmap diff) + consumer (/loop invokes loop-iteration); run metadata
- [ ] P3.3 autopilot-1 — idle/shipped phase + session-scoped streak in workflow-state.sh
- [ ] P3.4 spec-pipeline-1 — analyze marker producer + enforcement + dangling-consumer check
- [ ] P3.5 spec-pipeline-3 tdd-loop-5 — task grammar alignment + accept-discipline escalation
- [ ] P3.6 spec-pipeline-4,5 — validate.sh specs/plans lint; id allocation incl. archive
- [ ] P3.7 failure-recovery-3 — orphan reconciler ([~] → [!] on dead heartbeat); requeue-failed extensions
- [ ] P3.8 autopilot-4 — morning-operator banners + check-overnight-fired registration

## Phase 4 — Swarm, brownfield, release

- [ ] P4.1 swarm-1 — SWARM_ROOT shared-root helper in hooks; dispatch copies briefs
- [ ] P4.2 swarm-2 failure-recovery-2 — fix verified-merge line-continuation; lint-silent-failures rule
- [ ] P4.3 swarm-3 — PR lifecycle in verified-merge (create/checks/merge, exit 41)
- [ ] P4.4 swarm-4 — fleet-reconcile.sh; worktree teardown; doctor stale-worktree check
- [ ] P4.5 swarm-5,6 — handoff dialect unification; lane-guard hook; TASKS.md single-writer
- [ ] P4.6 brownfield-1 — fail-closed legacy manifest (roots, catch-all globs, gate-1 refusal)
- [ ] P4.7 brownfield-3,4,5 — reconcile .github; backup hygiene + revert; import-issues error capture
- [ ] P4.8 release-deploy-1,5 — DEPLOY_WIRED gate; SHIPPED producer; deployment_status resolution
- [ ] P4.9 release-deploy-2,3,4 — auto-merge workflow; ramp-check driver; rollback-flag.sh
- [ ] P4.10 release-deploy-6 failure-recovery-4 ci-gates-4,6 — release-please authority; autofix GH_TOKEN; API-key preflights; concurrency groups
## Phase 5 — Robustness + docs truth

- [ ] P5.1 greenfield-6 — setup.sh transactional validate
- [ ] P5.2 hooks-engineering-5 — dep-freshness latency (concurrent probes, cache, offline flag)
- [ ] P5.3 failure-recovery-5,6 — log/lock hygiene (gc-logs jsonl, size backstop, requeue lock rc)
- [ ] P5.4 ci-gates-5 e2e-rig-5 — actor allowlist; artifact polish
- [ ] P5.5 docs-truth-2..5 — doc-truth sweep (boolean form ban, routine matrix, regenerated trees, [s] legend)
- [ ] P5.6 docs-truth-1 — wire check-doc-consistency into validate.sh; widen audit-doc-claims
- [ ] P5.7 stack-portability-5,6 — workspace dimension; runner-arm consistency
