# E2E-Delivery Fix Campaign — Ledger

Source plan: `docs/research/harness-e2e-audit.md` (raw: `verify/2026-06-12-e2e-harness-audit/raw-audit.json`)
Pattern: direct fixes where writable; constitution-class files staged under `staged/` + `install.sh`; dual-mode rig `test-e2e-fixes.sh` (staged vs `INSTALLED=1`).

Status: `[ ]` pending · `[~]` in progress · `[x]` done+rig-proven · `[s]` skipped (reason)

## CAMPAIGN COMPLETE — 2026-06-12

All 40 plan items across 5 phases done and rig-proven. Final proof run:

- **Rig (staged mode)**: `bash verify/2026-06-12-e2e-fixes/test-e2e-fixes.sh` → 22 suites, **361 pass / 0 fail**, 0 suite-level failures.
- **validate.sh**: exactly the **12 by-design pre-install REDs** (4 ephemeral-verb, 2 alwaysLoad-MCP-matcher, 1 claude.yml actor-guard, 4 handoff-dialect refs, 1 §V model-doc drift) + 2 environment warnings. All 12 flip green after staged install.
- **Operator install**: `APPLY=1 bash verify/2026-06-12-e2e-fixes/staged/install.sh` (52 files: constitution, settings.json, 15 hooks, 9 agents, 13 skills, 14 workflows, ruleset, 2 script libs). Dry-run by default. Post-install proof: `INSTALLED=1 bash verify/2026-06-12-e2e-fixes/test-e2e-fixes.sh` expects validate.sh fully green.
- **Repo self-check**: `SKIP_COVERAGE=1 SKIP_TDD_LEDGER=1 SKIP_STORY_MAP=1 SKIP_INTEG_COV=1 bash .claude/scripts/verify.sh` → PASS. shellcheck on all touched scripts: only pre-existing SC2164 boilerplate.

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

- [x] P2.1 greenfield-2,3 tdd-loop-2 — DECISION: un-ignore verify/**/{red,green}.log; setup.sh selective block; canonical check-tdd-ledger.sh; evidence-gate SKIP removal
- [x] P2.2 tdd-loop-1,4 — unforgeable ledger (header parse, exit codes, timestamps, timeout, red_reason)
- [x] P2.3 e2e-rig-2 ci-gates-3 — evidence-gate toolchain install (composite action); BYO services; unmute playwright install
- [x] P2.4 e2e-rig-1 — webServer block in playwright evidence config
- [x] P2.5 e2e-rig-3 — AC id normalization (spec-match, story-test-map, collect-evidence anchored grep)
- [x] P2.6 greenfield-4 e2e-rig-4 — stack-aware AC proof; standalone evidence config; rig bootstrap; verifier/tester Write; path typo
- [x] P2.7 stack-portability-1..4 — stack engine pass (verify.sh detect-stacks consumption, test-unit/integration rewrite, Python PM ladder, coverage polarity)
- [x] P2.8 greenfield-1 — template-clean step in setup.sh (factory dev state stays out of new projects)
- [x] P2.9 ci-gates-1,2 — required checks in main-protection.json; setup.sh ruleset apply offer; live-ruleset drift checks
- [x] P2.10 brownfield-6 — characterization exemption in check-tdd-ledger.sh; stronger char-gate

## Phase 3 — Mechanize the loop

- [x] P3.1 spec-pipeline-2 tdd-loop-3 — next-task.sh canonical picker; wire into loop-iteration + /implement + workflow-state
- [x] P3.2 autopilot-2,5 — loop-control producer (post-write-roadmap diff) + consumer (/loop invokes loop-iteration); run metadata
- [x] P3.3 autopilot-1 — idle/shipped phase + session-scoped streak in workflow-state.sh
- [x] P3.4 spec-pipeline-1 — analyze marker producer + enforcement + dangling-consumer check
- [x] P3.5 spec-pipeline-3 tdd-loop-5 — task grammar alignment + accept-discipline escalation
- [x] P3.6 spec-pipeline-4,5 — validate.sh specs/plans lint; id allocation incl. archive
- [x] P3.7 failure-recovery-3 — orphan reconciler ([~] → [!] on dead heartbeat); requeue-failed extensions
- [x] P3.8 autopilot-4 — morning-operator banners + check-overnight-fired registration

## Phase 4 — Swarm, brownfield, release

- [x] P4.1 swarm-1 — SWARM_ROOT shared-root helper in hooks; dispatch copies briefs — lib/swarm-root.sh (pwd -P); staged post-bash-log/session-heartbeat/subagent-stop; swarm-dispatch post-spawn brief copy; 5/5 test-swarm-root.sh
- [x] P4.2 swarm-2 failure-recovery-2 — fix verified-merge line-continuation; lint-silent-failures rule — comments moved above continuations; new awk continuation rule (found+fixed session-end.sh:42); covered by test-verified-merge.sh
- [x] P4.3 swarm-3 — PR lifecycle in verified-merge (create/checks/merge, exit 41) — gh pr create/checks --watch/merge with escalate 41; absolute $LOG fix; worktree+branch teardown; 10/10 test-verified-merge.sh
- [x] P4.4 swarm-4 — fleet-reconcile.sh; worktree teardown; doctor stale-worktree check — fail-safe vs daemon restart, --respawn cap; swarm-respawn.sh extraction; doctor stale-worktree warn; 9/9 test-fleet-reconcile.sh
- [x] P4.5 swarm-5,6 — handoff dialect unification; lane-guard hook; TASKS.md single-writer — handoff-*.yaml everywhere + validate.sh [handoff-dialect]; staged pre-lane-guard.sh 10/10 test-lane-guard.sh; coordinator single-writer contract
- [x] P4.6 brownfield-1 — fail-closed legacy manifest (roots, catch-all globs, gate-1 refusal) — adopt-archaeology.sh monorepo roots + per-dir catch-all + per-ext root globs + UNPROTECTED banner; adopt-state.sh approve-1 refusal before marker consumption; 17/17 test-adopt-gate.sh
- [x] P4.7 brownfield-3,4,5 — reconcile .github; backup hygiene + revert; import-issues error capture — reconcile-claude-dir.sh: .github no-clobber + collision/CI/husky [OQ]s, MANIFEST.txt, backup-time gitignore, --revert <ts>; archaeology CI/hook inventory; import-issues-once.sh auth preflight + loud failure (no sentinel); /adopt auto un-muted + Phase-3 refusal + Phase-6 _verify_gates; ADOPTION.md stale refs fixed; 38/38 test-adopt-completeness.sh
- [x] P4.8 release-deploy-1,5 — DEPLOY_WIRED gate; SHIPPED producer; deployment_status resolution — staged canary-deploy.yml (fail-closed gate, PROM_URL error, real Deployment + statuses); staged issue-lifecycle.yml sha→merged-PR issue resolution; doctor deploy-stub check (fail on wired+STUB); staged release.md concrete-signal steps 8-9; DEPLOY-INTEGRATION.md §5 lifecycle signal; 18/18 test-deploy-gate.sh
- [x] P4.9 release-deploy-2,3,4 — auto-merge workflow; ramp-check driver; rollback-flag.sh — rollback-flag.sh (4 provider adapters, identifier validation, exit 0/2/3); ramp-check.sh (soak/gate/ramp/kill/SHIPPED-dispatch/loud-tasks) + staged ramp-check.yml cron; staged auto-merge.yml (label/overnight opt-in, draft guard); staged hotfix-ingest first-responder; /rollback-flag delegates to script; ship/release/§XI auto-vs-interactive policy; dead deploy.yml refs fixed; 37/37 test-flag-ramp.sh
- [x] P4.10 release-deploy-6 failure-recovery-4 ci-gates-4,6 — release-please authority; autofix GH_TOKEN; API-key preflights; concurrency groups — .release-please-manifest.json seeded; setup.sh stack-typed config + API-key preflight; doctor checks; staged ship/release "merge the release-please PR"; staged autofix GH_TOKEN + no-PR fail/label, DATE_LABEL dropped; staged claude-review/claude-security fail-fast preflights + concurrency, security branches:[main], pr-review draft guard; 30/30 test-ci-plumbing.sh
## Phase 5 — Robustness + docs truth

- [x] P5.1 greenfield-6 — setup.sh transactional validate — rc captured, plugins always reached, final re-validate + exit non-zero at END; covered in test-dep-cache.sh
- [x] P5.2 hooks-engineering-5 — dep-freshness latency — staged hook: per-session decision cache (asks never cached), concurrent 5s probes, curl --max-time (timeout-wrapper absent on stock macOS = latent always-fail-closed bug fixed), DEP_FRESHNESS_OFFLINE operator escape; 15/15 test-dep-cache.sh
- [x] P5.3 failure-recovery-5,6 — log/lock hygiene — gc-logs.sh rotates *.jsonl (memory/.cache + .swarms) + resets instinct offset; staged session-end gc backstop; doctor oversized-log warn; requeue-failed rc-75 + flip re-grep before ✓; 13/13 test-hygiene.sh (gc-suite 12/12 intact)
- [x] P5.4 ci-gates-5 e2e-rig-5 — actor allowlist; artifact polish — staged claude.yml author_association allowlist on all 4 trigger arms; validate.sh comment-trigger+write actor-guard invariant (live claude.yml = new by-design pre-install RED); collect-evidence find-glob for per-worker video/trace; staged evidence-gate always() verify/ upload; playwright HAR-clobber caveat; 13/13 test-actor-artifact.sh
- [x] P5.5 docs-truth-2..5 — doc-truth sweep — ONBOARDING:249 boolean-false advice → truthful remove-the-string mechanism; AUTOPILOT:117 string form; OPERATOR-MANUAL:184 [s]=skipped(+reason:); validate.sh bans (boolean bypass form + [s]-shipped gloss in docs/, docs/research/ exempt); install-overnight-tasks.sh record() + gc-nightly/oq-aging/quarterly-archive + generic loop (appetite/atlas/constitution-compact/feedback-triage) + opt-in pollers (INSTALL_FEEDBACK_POLL/INSTALL_SENTRY_POLL); harness-doctor routine-installs enumeration; AUTOPILOT Routine Installation Matrix (12 rows) + OPERATOR-MANUAL pointer; ARCHITECTURE agent table fixed (coordinator/feature-stream opus→sonnet) + 5 missing agents added (18/18 = frontmatter); README tree agent lines + honest truncation markers (58 skills/25 hooks/36 workflows); 27/27 test-doc-truth.sh
- [x] P5.6 docs-truth-1 — check-doc-consistency.sh wired into validate.sh as [model-doc-consistency] (was an orphan claiming to be wired) + extended to diff ARCHITECTURE.md agent table vs live frontmatter; surfaced REAL drift: §V missing anti-slop-reviewer → fixed in staged constitution (12th by-design pre-install RED); audit-doc-claims.sh widened: active-voice claims ("X.sh enforces/blocks/fails/gates/rejects/halts") + extensionless required-check names resolved against main-protection.json contexts + docs/research/ excluded; widened scan surfaced AUTOPILOT:157 stale required-check list (ci/claude-code-review/…) → fixed to live contexts; repo scan green (25 claims resolve); 22/22 test-doc-claims.sh
- [x] P5.7 stack-portability-5,6 — detect-stacks.sh workspace dimension (turbo>nx>pnpm>lerna>npm-workspaces>go.work>cargo-[workspace], task-runner-first precedence); verify.sh Node block: workspace-aware test aggregation (turbo run test / nx run-many / pnpm -r / npm --workspaces; detected-but-uninstalled runner = FAIL not skip) + per-package coverage merge (covered/total sums via jq -s, zero summaries = FAIL, single-pkg gate bypassed when ws≠none); test-unit.sh runner-aware flags (--run vitest / --ci jest — was hardcoding --run for all runners, broke jest repos); lint.sh bun.lockb unified + 5 counted tool-missing arms (gradle/mvn, tflint/terraform, hadolint, shellcheck, sqlfluff) with LINT_TOOL_MISSING_OK=1 waiver; repo verify.sh still PASS; 36/36 test-stack-portability.sh
