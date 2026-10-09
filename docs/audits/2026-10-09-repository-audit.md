# Repository audit — AI software factory readiness

Date: 2026-10-09, Australia/Sydney. Scope: `qyndex/claude-init`, working checkout, plus read-only live GitHub configuration and selected recent failed runs.

## Decision

**Extend the harness, but repair its verification and coordination before enabling unattended delivery.** The spec workflow, specialist agents, hooks, tests, evidence rig, memory plane and reporting are useful foundations. A green result currently does not reliably mean that the intended candidate was tested, all required acceptance criteria were proved, or an independent reviewer accepted it. The factory needs enforceable delivery contracts around those components, rather than more agent prompts.

This audit updates [the implementation plan](../../plans/AI-SOFTWARE-FACTORY.md). It does not change executable code, branch rules, deployment settings or schedules.

## Scope and method

The [inventory](2026-10-09/inventory.json) records hashes and classification for **all 1,099 tracked files** at the audited commit, using working-tree contents. It includes five initiative STATE files already modified by the user. Newly created plan/audit documents and ignored runtime/cache files are outside that baseline. Routing categories contain 324 instruction/configuration/document files, 290 operational files and 485 historical evidence/archive files.

All tracked bytes were inventoried; tracked JSON and shell files received syntax checks. Maintained scripts, hooks, workflows, settings, templates, specialist instructions, routines and installation/adoption paths were assessed for delivery, security and recovery behavior. Historical logs, screenshots and archives were inspected as evidence and by structure; **they were not all individually re-executed or manually reviewed line by line**. Inventory coverage is not semantic proof of every file.

Tools: macOS system Bash 3.2.57, jq 1.7.1, Actionlint 1.7.12 and ShellCheck 0.11.0. The inventory records the exact audited Git HEAD; source files were checked against those hashes after report creation and none changed.

The 53 shell test suites ran in a disposable copy, keeping their mutations out of this checkout. Additional safe fixtures substituted failing tools and synthetic specifications. No paid model run, destructive command, real merge or deployment was executed. Existing tests passing does not demonstrate complete isolation, race safety or production readiness. Tests ran on macOS; Linux behavior was inspected in workflows but the entire suite was not rerun on Linux.

## Verification results

| Check | Result | Evidence |
| --- | --- | --- |
| Tracked-file inventory | 1,099 files hashed | inventory.json |
| JSON / shell syntax | No failures in tracked JSON or `bash -n` checks | Per-file inventory checks |
| Harness validator | 79 passed checks, 1 warning, 1 failure, across 23 categories | [validate.json](2026-10-09/validate.json) |
| Workflow lint | 4 invalid expressions; 10 embedded-shell diagnostics | [actionlint.txt](2026-10-09/actionlint.txt) |
| ShellCheck, warning threshold, tracked shell outside verify/ | No diagnostics | [shellcheck.json](2026-10-09/shellcheck.json); excludes workflow embedded shell |
| Shell test suites | **42 passed, 11 failed** | [tests.tsv](2026-10-09/tests.tsv), [individual logs](2026-10-09/test-logs/test-security-invariants.sh.log) |
| Injected scanner failure | Exit 42 becomes successful local check | [failure-injection.json](2026-10-09/failure-injection.json) |
| Unsupported contract | Reported “all contracts satisfied”, exit 0 | Same fixture output |
| No-AC evidence emission | jq error, zero-byte evidence.json, PASS and exit 0 | Same fixture output |

Nine failing suites primarily reflect stale patch-promotion or marker expectations: boot-autoheal, boot-inject-hot, dream-cost-gate, pivot-trace, reverse-drift, ship-verify-sync, spec004-reconcile, subagent-recall-scope and subagent-spec-resolution. Preserve their intended assertions while replacing obsolete patch application; do not merely suppress them.

`security-invariants` has one obsolete assertion about a `.permissions.sandbox.enabled` setting and one actual miss for quoted destructive SQL. `oq-aging` has five failed assertions caused by the same escalation defect. Trace confirmed that 2026-10-01 to 2026-10-09 spans Sydney's daylight-saving transition: elapsed seconds divide to seven whole days, so the `>7` condition is false. Define calendar-day versus elapsed-time semantics explicitly and test both DST boundaries.

Validator failure: malformed YAML frontmatter in `.claude/memory.proposed/decisions/0004-autonomous-green-gated-merge.md`. Its warning identifies a task acceptance command that only lists existing proof files. Actionlint rejects `hashFiles` at **job-level** conditions in `iac-scan.yml:18,33,43,55`; move detection into a checkout-backed step or explicit detection job.

The [reproduction script](2026-10-09/reproduce-audit.py) reruns tracked-file inventory/syntax checks and the three safe failure-injection fixtures into `/tmp`; it does not regenerate live GitHub snapshots or rerun all 53 suites. The original suite logs are retained alongside the summary.

## Live configuration: correction to the earlier plan

[The active ruleset](https://github.com/qyndex/claude-init/rules/19653920) applies to main/master, has no bypass actors, requires an up-to-date branch and linear history, and requires these nine checks: `lint-test`, `review`, `security-review`, `harness-validate`, `evidence-gate`, `adr-gate`, `commitlint`, `lint-exception-audit`, `check-daily-batch`. It requires zero human approvals.

**Both the stored ruleset's actual check list and live rules require review/security.** The stored `_comment` incorrectly calls them advisory. The earlier plan followed that comment; that conclusion is corrected. Live configuration is additionally stricter on stale-review dismissal and review-thread resolution than the stored template. Reapplying the template would weaken those controls. Neither configuration pins the listed checks to an expected integration ID.

Snapshot evidence: [ruleset](2026-10-09/live-ruleset-detail.json), [environments](2026-10-09/live-environments.json), [Actions permissions](2026-10-09/live-actions-permissions.json), [workflow permissions](2026-10-09/live-workflow-permissions.json). There are **zero deployment environments**; default workflow permissions are read, all Actions are allowed, SHA pinning is not required, and Actions may approve PR reviews. These are snapshots, not permanent guarantees or proof of all organizational policies/secrets.

Selected live failures corroborate operability gaps: [evidence gate run](https://github.com/qyndex/claude-init/actions/runs/37782217701) fails for missing PR Evidence Bundle; [stale dependency run](https://github.com/qyndex/claude-init/actions/runs/37869937067) fails when no artifacts exist and `/tmp/all-artifacts` was never created. An intentionally empty scan set needs an explicit successful no-applicable-stack outcome, not a failed rollup.

## Findings and required repairs

P1 means repair before trusting unattended merging or the affected release path. P2 means repair before scaling/adopting that capability. These priorities describe factory readiness; they are not claims that a remote exploit or erroneous production merge occurred. Static findings below are code-path conclusions unless a test or live run is cited.

### Verification, evidence and review

**A01 — P1: merge verification tests the wrong checkout.** `verified-merge.sh:118,122,154` changes to `$WORKTREE` then invokes scripts under `$ROOT`; `verify.sh:10–11` and `local-pr-check.sh:24–25` immediately return to their own script root. A passing coordinator can authorize a broken candidate. Make candidate root an explicit validated argument and assert SHA/path before every gate. After mediation rerun heavy and contract checks as well as smoke. Test a passing coordinator against a deliberately failing worktree and the reverse.

**A02 — P1: failing or missing scanners become green.** `local-pr-check.sh:66–74` combines invocation with `|| echo`, treating installed tools' nonzero results as success; reproduced with exit 42. `semgrep.yml` tolerates scan errors and its severity step does not fail for absent output. Daily-batch has advisory scanner paths; dependency review and CodeQL also use error tolerance. Separate applicability, unavailable tool, infrastructure error and clean scan; only clean or trusted not-applicable passes. Validate severity numerically rather than lexicographic strings. Fixtures must include crash, timeout, malformed output, no output and a high-severity finding.

**A03 — P1: evidence emission and freshness are unsafe.** `collect-evidence.sh` reuses date/spec output directories without clearing old runner results, ignores runner exit status, and derives verdict from potentially old output. A zero-AC count emits `0\n0`, fails jq and still exits 0 with PASS; reproduced. Use per-attempt directories, atomic validated finalization, explicit runner status and approved expected ACs. An AC-tagged passing test is an association, not proof of meaningful assertions. Use independently exercised behavior and approved applicability.

**A04 — P1: evidence gate checks a weak manifest contract.** `evidence-gate.yml` accepts an ancestor commit, chooses one changed bundle, does not validate a complete schema/expected AC set, and permits broad maintenance exemptions including policy/workflow code. Missing fields can look like empty unproven lists. Some journey/applicability paths skip. Bind all affected specs and expected ACs to final candidate, spec revision, verifier identity, policy and artifact digests. Missing or malformed proof must block; policy edits cannot exempt themselves.

**A05 — P1: required agent checks do not enforce a review verdict.** `claude-review.yml` can complete its invocation successfully without a machine-validated approve/block decision; review-format lint is warning-only and searches historical reviews. `claude-security.yml` omits `synchronize` while its context is required live: later commits can remain missing current security proof. Conditional skipping of release/Dependabot/draft also affects its embedded deterministic scanner. Run deterministic scanning unconditionally when applicable, with trusted applicability outputs; validate separate current-candidate review/security verdicts and blocking findings. A different model alone is not an independent execution or authority boundary.

**A06 — P1: verification exemptions are agent-accessible and CI proof is incomplete.** `verify.sh` uses a writable `allow-skip-gates` marker; comments do not make it human-only. `VERIFY_CI` skips gates on the premise that they run elsewhere, without an enforced equivalence contract. Detached checkouts skip task acceptance. Failed stack detection can degrade to no applicable tests, and shell-only harness verification does not execute the 53 shell suites. Define a per-stack/per-change required-check matrix and trusted waiver identity. Unknown stack, missing runner, unexecuted acceptance, invalid coverage or missing equivalent CI job must block.

**A07 — P2: contracts, integration and TDD offer weaker proof than claimed.** `contract-tests.sh` passes missing analysis and unsupported contract types (the latter reproduced); supported checks mostly grep source. `test-integration-coverage.sh` counts test filenames rather than executions. `check-tdd-ledger.sh` defaults enforcement to T-111, so fresh adopted projects' initial tasks are grandfathered; absent ledger paths and some metadata patterns weaken enforcement. Replace heuristic presence checks with executed contracts, require explicit applicability and mandatory attempt-linked red/green metadata, and make legacy exceptions repository-specific.

### Merge, deployment and credentials

**A08 — P1: merge paths have inconsistent eligibility and no common candidate pin.** `auto-merge.yml`, Dependabot auto-merge, `autonomous-ship.sh` and `verified-merge.sh` rely on differing decisions. Autonomous-ship checks the existence of a ruleset rather than applicable active policy and exposes `AUTOSHIP_SKIP_RULESET`. A label is not authority. Create one trusted evaluator used by all routes; validate target rules and producer identity, and match the expected head/integration candidate at merge. Native required checks remain necessary but do not validate an LLM's verdict or all evidence semantics.

**A09 — P1: daily-batch freshness is not candidate verification.** `merge-gate.yml` accepts an in-progress batch and relies on a recent global run, without binding its result to PR changes or integrated SHA. Failure repair can be blocked by the same failed-main batch it is repairing. Require the relevant completed proof or trusted change-scoped applicability, with a protected way to validate remediation against the candidate rather than weakening the rule.

**A10 — P1: rollback can target another change and cannot use the normal protected route.** `verified-merge.sh` pulls main best-effort then reverts local HEAD and directly pushes main. Record the actual merged SHA, verify it in an isolated checkout, and open an exact rollback PR through protected checks. Never infer rollback identity from whichever commit is newest. Exercise a concurrent subsequent merge and a failed pull.

**A11 — P1: canary workflow has no enforceable production protection.** `canary-deploy.yml` has no `environment: production`, and live environments are empty. A `DEPLOY_WIRED` flag does not turn placeholder echo/sleep ramps into deployment. Missing Prometheus values default toward zero; the queried CANARY_SERVICE can differ from selected service. Require real deployment receipts, environment-scoped credentials/policy and service-bound SLO data; missing series must halt. Keep production rollout outside merge eligibility until those checks exist. GitHub environment protections apply to jobs referencing the environment: [official documentation](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments).

**A12 — P1: workflow input is inserted into shell code.** `memory-rollup-weekly.yml:34` interpolates the manual `week` input into a shell string in a write-capable job. Pass it through `env` and validate an ISO-week grammar before use. This is a static injection path, not evidence of exploitation. Keep PR code execution isolated from merge and deployment credentials.

**A13 — P2: bot/release and dependency paths need explicit proof.** Release jobs rely on bot author/branch exemptions and GITHUB_TOKEN close/reopen behavior; release-only diff validation is not a universal prerequisite to those exemptions. Dependency auditing lacks consistent installed-project scanning (notably pip-audit), package-manager setup and path coverage. Use a scoped GitHub App where required, validate bot diffs before exemption, and route all changes through the same policy. Current GitHub documentation says GITHUB_TOKEN-created opened/synchronize/reopened PR runs require approval; other token-generated events generally do not launch workflows, with dispatch exceptions. Verify this behavior in a disposable pilot rather than assuming a token event creates an unattended CI run: [official event documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows).

### Durable orchestration and truthful reporting

**A14 — P1: file atomicity is not coordinated ownership.** Atomic rename is useful, and tasks-lib/memory locks are real improvements. Fleet and other shared read/modify/write paths are not all behind one transaction. next-task selection does not reserve ownership. The lock helper reclaims through check-then-delete without fencing, and the convention that all callers share root-relative locks is not enforced. The exact contention failures were not reproduced here. Add transactional claims, owner/lease/attempt IDs, fencing and consistent state roots; stress concurrent claims/writes and kill holders before relying on parallel execution.

**A15 — P1: launcher locks do not supervise workers.** Local overnight lock ownership is tied to the launcher PID and cleared when it exits after spawning; remote run markers have different stale/retry semantics. Prompt time and cost instructions are not external budget enforcement. Use a supervisor whose lifetime matches the worker, bounded repairs, capability probes, checkpointed quota waits and externally enforced limits. Worktrees also need isolated ports, services/databases and credentials.

**A16 — P1: task and spec status can claim delivery before merge.** Task status has no expected-owner/version condition. Spec synchronization infers shipped from `[x]/[s]` without authoritative merged receipts; skipped/shipped marker semantics conflict across readers. ID minting scans TASKS.md, not separately archived task files, allowing reuse after GC; dependencies on removed completed tasks lose authoritative resolution. Create durable identity/completion indexes and distinct implemented, verified, merged, accepted states. Serialize GC with mutations and archive by completion time, not the first date found.

**A17 — P1: shipped reconciliation can misattribute or miss delivery.** `reconcile-shipped.sh:70` caps history at 50 without pagination or an explicit base filter; API failure becomes empty success. It associates each PR with globally completed specs rather than that PR's immutable task/spec mapping. A timestamp-only watermark and advancing beyond unseen records can lose coverage. Use paginated target-branch reconciliation, receipt IDs and stable timestamp/PR cursors; persist only after complete successful processing. Test more than 50 merges, equal timestamps, outage and unrelated specs.

**A18 — P1: morning digest is neither a complete time window nor historical proof.** `daily-briefing.sh:50` matches UTC mergedAt date prefixes against a local date, excluding overnight work around Sydney boundaries. Later live check queries cannot establish status at merge. Existing morning routine defaults to 07:00 UTC, not Sydney. Extend the existing report/routine with a durable last-delivered cursor, timezone-aware cutoff, immutable receipts, feature/AC grouping, explicit missing evidence, delivery acknowledgment and retry. The operator must not review a report PR to receive their morning digest.

**A19 — P2: feedback and hotfix processing need idempotent closure.** Feedback closure can close a multi-spec item when any linked spec matches; shipped and accepted are conflated. Hotfix cooldown searches after fingerprint although last_touched is earlier, and input fingerprints are treated as regex. Poll/ingest use separate task creation paths and ignore some existing task identity, risking inconsistent deduplication. Validate text/IDs, preserve source events, close only all required delivered scope, and make task creation + dispatch a recoverable transaction.

### Security, adoption and maintenance

**A20 — P1: hooks are not an execution isolation boundary.** Quoted SQL bypass is demonstrated by security-invariants. pre-bash-guard strips quoted arguments before some destructive-command matching; shell filesystem commands can mutate files outside Write/Edit hooks. Lane guards and MCP guards cover selected tool families; missing allocation/unknown tool cases can allow operations. Human-only bypass comments and editable guard scripts do not establish authority separation. Retain hooks as useful policy feedback, but enforce filesystem/process/network and credential restrictions outside the implementer's control. Validate canonical paths, quoted commands, selected MCP tool schemas and encoded GitHub content without relying on regex as the sole boundary.

**A21 — P2: evidence and memory need privacy and retention policies.** API/HAR capture can retain raw sensitive bodies; filenames and ports collide between concurrent runs. User-state mirroring can capture unrelated projects, while restore uses a different config-root convention and weakly validates archives. Artifact retention differs across workflows, including a short evidence window. Redact before durable capture, scope snapshots to the project, validate restores, namespace outputs/services by attempt, and retain proof long enough for audit/feedback. No secret values are included in this audit.

**A22 — P2: installer/adoption paths are unsafe to call successful on partial failure.** Installer falls back from failed requested ref and warns through copy/setup errors. Reconciliation infers ownership by filename and uses eval-built commands; customization backups/copy failures do not consistently stop. Template cleanup hardcodes spec-001–003 although 004/005 exist, and broader ledger/initiative cleanup can affect user state. Use versioned ownership manifests, explicit customization conflicts, strict requested-ref resolution and transactional adoption. Test fresh install, upgrade, customized workspace, paths with spaces/apostrophes and injected copy failure.

**A23 — P2: stack and runtime claims need a tested capability matrix.** CI/setup-stack choose a first stack while local scripts can detect several; package-manager setup and advertised language coverage differ. Agent model consistency checks compare stored names, not live availability or supported CLI flags. Define supported combinations with clean disposable fixtures; unknown combinations block or receive an approved limited-scope mode. Central role routing comes after reliable proof, not before it.

**A24 — P1 baseline / P2 maintenance: current repository validation is not clean.** Repair malformed proposed ADR frontmatter, invalid workflow conditions, zero-artifact dependency rollup and the DST bug. Replace the nine stale tests with current-behavior assertions, repair real guard coverage, and keep Linux/macOS tests required rather than treating suites containing old patch references or security invariants as permanently advisory. Preserve historically relevant patch evidence without making its reapplication a current regression test.

## Plan changes and closure criteria

The revised plan adds **F-00 baseline repair**, strengthens F-02 with negative/failure-injection proof and trusted verdicts, strengthens F-03 with current-head security and live-policy reconciliation, and expands F-04–F-07 for archive identity, truthful reporting, adoption, privacy and stack support. Reuse existing reporting and locks where useful; do not rewrite working components solely to adopt a framework.

First deliverable should be a repair specification covering A01–A06, A09 and A24, plus an evidence schema prototype in shadow mode. Do not increase autonomy until deliberately failing candidates are rejected and every pilot merge produces a durable receipt. Then demonstrate one feature → separate verifier → eligible merge → morning digest → feedback amendment delivery, followed by recovery drills. Production canary remains a separate gated capability.

No claim is made here that all race conditions are reproduced, all third-party Actions/MCP packages are verified supply-chain safe, all ignored local state is valid, or real model/production runs are healthy. Those are explicit pilot and implementation checks. Re-audit the changed paths and live policy after repairs; passing today's tests alone is insufficient.
