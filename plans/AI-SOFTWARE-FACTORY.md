# AI software factory improvement plan

Date: 2026-10-09
Status: implementation authorized by the operator on 2026-10-09; live merge/security authority changes require a decision on the concrete activation PR.

## Objective and recommendation

Extend claude-init into a local-first factory that delivers approved requirements through implementation, independent verification, deterministic merge eligibility, automatic merging, and one daily operator digest. Operator feedback enters the same versioned specification chain. Routine PR approval should not require the operator.

Preserve the existing spec/TDD workflow, specialist agents, worktrees, CI checks, evidence rig, task ledger, and feedback registry. Add enforceable contracts and coordination around them. Do not start with a replacement framework or a large dashboard.

This plan uses the referenced conversation “AI Model Routing Coding” and the [2026-10-09 repository audit](../docs/audits/2026-10-09-repository-audit.md). The audit inventories all 1,099 tracked files, reviews maintained delivery/security/state paths, runs all 53 shell test suites in a disposable copy (42 pass, 11 fail), and checks live GitHub rules and deployment environments. Historical artifacts received inventory/structural coverage rather than individual semantic certification. The separate Arentic blueprint attachment was unavailable; this plan covers the harness, not that platform's full product scope.

The current harness is not ready for unattended evidence-gated delivery. Three injected failures returned success: scanner exit 42, unknown contract type, and zero-byte evidence JSON. Repair these and candidate-root verification before expanding autonomy. Existing user modifications to initiative STATE files are outside this plan change.

## Current foundation and verified gaps

| Area | Existing implementation | Required improvement |
| --- | --- | --- |
| Specification authority | specs/, plans/, tasks/TASKS.md; constitution's eight phases | Immutable approved revision, stable AC IDs, explicit amendment approval and scope |
| Evidence | collect-evidence.sh; evidence-gate.yml reruns smoke and optional journeys | Schema validation, complete AC set, trusted artifact provenance, exact head/base/spec/policy binding |
| Evidence freshness | Gate accepts ancestor commit; collector reuses attempt output and can return PASS after JSON emission failure | Unique attempt directories; propagate runner/emission failure; account for every spec; rerun after candidate changes |
| Independent review | claude-review.yml uses a different model and posts findings | Required structured verdict from a separate run; validate identity, findings and freshness |
| Merge enforcement | main-protection.json; autonomous-ship.sh; auto-merge.yml; verified-merge.sh | One eligibility contract used by every path; confirm applicable active live protection, required contexts and trusted check producers |
| Review protection | Both stored check list and live rules require review/security; stored advisory comment is wrong; zero approvals required | Enforce structured current-candidate verdicts; security must run on synchronize; preserve stricter live stale-review/thread controls |
| Exceptions | no-ac.json maintenance exemption includes .claude/ and .github/ | Gate/security/workflow changes cannot exempt or approve themselves; docs and harness changes still receive appropriate deterministic checks |
| Background execution | swarm scripts, fleet reconciliation, local overnight launcher | Atomic task claims, serialized shared writes, leases, supervisor and restart recovery |
| Integration | verified-merge.sh rebases, tests, mediates and merges | Verify actual worktree candidate; rerun all failed/applicable gates after mediation; serialize integration |
| Rollback | verified-merge.sh pulls main best-effort, reverts local HEAD and pushes directly | Identify recorded merge SHA, verify clean isolated checkout, use protected rollback route; do not revert a newer unrelated commit |
| Morning report | daily-briefing.sh, reconciliation and morning-briefing routine exist; routine defaults to UTC | Paginated correct task/spec mapping, Sydney cursor intervals, durable delivery and immutable merge receipts |
| Feedback | feedback-extractor, feedback command, registry and routines | Operator digest feedback linked to spec amendment, tasks, PRs, evidence and later delivery |
| Model routing | Agent frontmatter, constitution table and consistency checker | Central role routing, capability probes, bounded fallback, run attribution and quota handling |

Sources: .github/workflows/{evidence-gate,claude-review,merge-gate,auto-merge}.yml; .github/rulesets/main-protection.json; .claude/scripts/{collect-evidence,autonomous-ship,verified-merge,swarm-dispatch,fleet-reconcile,local-overnight-build,daily-briefing}.sh; .claude/agents/specialists/feedback-extractor.md; .claude/CLAUDE.md.

Specific enforcement inconsistencies to resolve: autonomous-ship.sh rejects non-pass checks, while other merge paths rely on native auto-merge and the ruleset; merge-gate.yml returns success for an in-progress daily batch; review format lint is warning-only. Security review omits synchronize, scanner execution failures can become green, and detached CI checkouts skip task acceptance. A current check query in daily-briefing.sh cannot establish historical status at merge. The overnight launcher writes a PID lock then starts a background session; the launcher lifetime is not the worker lifetime. Shared fleet read/modify/rename writes do not provide transaction isolation.

## Target delivery contract

Approved spec revision → dependency-ready task → isolated implementation → independent verification → trusted policy eligibility → serialized integration and merge → merge receipt → morning digest → operator feedback → spec amendment.

Separate three outcomes: engineering verified, merged, and product accepted. Staging validation and production release have distinct policies. A merge does not mark an entire specification delivered unless all its required tasks and integrated ACs pass.

### Evidence and review

Create a versioned JSON evidence schema with repository identity, PR number, head SHA, base SHA or integration candidate SHA, approved spec revision/hash, task and AC IDs, policy version/hash, implementer and verifier execution IDs, runtime/model IDs, CI run/attempt IDs, artifact locations/digests, commands/exit codes, results, findings, applicability decisions and timestamps.

Every run uses a new attempt directory; do not reuse previous runner output after a failed invocation. Evidence emission, parsing and schema validation must succeed before a PASS can be published. The approved spec determines the expected AC set; the implementation agent cannot omit criteria. Distinguish pass, fail, not tested and approved not applicable. Missing evidence, unavailable tools, unknown risk and malformed reports block eligibility. UI changes require realistic journey evidence; backend changes require contract/integration evidence; harness changes require script/workflow verification rather than a browser substitute.

Use externally stored CI artifacts or verifier-produced attestations for exact-head proof. Committing a manifest changes HEAD, so do not require a self-referential committed SHA. Existing committed bundles remain useful historical records, but final merge authorization comes from a trusted run against the final candidate. Bind a human-readable PR report to the same manifest and artifact links.

Verifier runs use separate execution identities and fresh candidate checkouts. They inspect the approved spec and code, run applicable tests, and produce machine-readable findings. A different model adds diversity but does not establish independence by itself. Implementer workspaces cannot alter the verifier's trusted configuration or mint its attestation. Verifiers have no merge credential. Test execution of untrusted PR code receives no privileged merge credential.

### Merge policy

One deterministic policy evaluator returns eligible or blocked with reason codes. It validates exact candidate identity, all approved ACs, trusted review verdict, absence of unresolved blocking findings, applicable CI checks, artifact integrity, risk policy, and live protection.

Implementation credentials cannot merge directly or alter branch protection. A narrowly scoped merge identity consumes the evaluator's result. Protect policy, workflow, credential and verifier changes through controls rooted outside the candidate PR. Editing a PR's own workflow or supplying no-ac.json must not weaken its gate. Validate the active rules actually apply to the target branch; the existence of any ruleset is insufficient. Disable operational environment bypasses such as test-only ruleset skips in production execution.

Initial autonomy proposal: docs/tests and bounded fixes auto-merge; ordinary features within approved contracts auto-merge after full proof; auth, payments, migrations and public contract changes require additional independent security/architecture proof and explicit policy coverage. Destructive changes and changes to the authority controlling merges enter the operator decision queue. The operator authorized autonomous production releases after additional automated deployment, SLO and rollback gates pass; production autonomy remains disabled until F-08 proves those controls. Risk derives from actual diff and dependency impact, not a label supplied by the implementer.

Prefer native merge queue if available and suitable for the repository; otherwise serialize integration with a leased coordinator. Each changed head or integration base invalidates affected evidence. Rebase, conflict resolution and mediation must repeat all applicable checks and independent review. Record actual merged SHA and eligibility evidence in a durable merge receipt.

### State and recovery

Keep tasks/TASKS.md authoritative during the initial rollout. Put runtime claims, attempts, leases and event receipts in a transactional local store behind a single writer. Runtime state is not a second product backlog. If task authority later migrates, make that a separate approved ADR and change all readers and the constitution together.

Suggested local implementation: SQLite transactions for run state plus an outbox for external actions. This is a proposed choice to validate in the reliability slice. Do not add a distributed workflow system until local recovery and volume demonstrate a need.

Run states: queued, claimed, implementing, verifying, repairing, merge-ready, merging, merged, blocked, cancelled. Store attempt IDs, owner, heartbeat, lease expiry and bounded retries. Use fencing tokens to reject stale workers; idempotency keys for PR creation, merge reconciliation, reports and feedback intake. Recovery checks remote effects before repeating them. Serialize shared task-ledger writes and GC; materialize fleet/report projections from authoritative state. Task IDs and dependency completion must survive archival. Distinguish implemented, verified, merged and product accepted; spec synchronization cannot infer delivery from local completed/skipped markers.

Run workers under a supervisor that survives launcher exit. Enforce time, quota and budget limits outside prompts. Provide pause-all, cancel, revoke and bounded repair (initial proposal: two repair attempts per candidate, then a durable blocker). Start with two implementation streams and one integration writer. Worktrees isolate files; ports, services, databases and credentials also need per-run isolation.

### Morning digest and feedback

Extend daily-briefing.sh, reconcile-shipped.sh and the existing morning-briefing routine. Paginate merged target-branch PRs and derive task/spec associations from their receipts, not all globally completed tasks. Use stable receipt IDs and a timestamp/PR cursor that cannot lose equal-time or more-than-50 merge batches. API failure must preserve the cursor and surface an operational failure. Reconcile actual merged PRs with local receipts; report missing evidence honestly. Use the interval from last successfully delivered cursor to the new cutoff, with Australia/Sydney display and daylight-saving-aware scheduling. Operator decision (2026-10-09): 08:00 Australia/Sydney to workspace `qyndex`, channel `qyndex-alerts`. No schedule or external delivery is created by this plan.

Group by delivered feature: observable user outcome, complete/partial AC coverage, merged PR list, evidence links, staging preview, known limits, blocked work and decisions. Every merged PR appears once in the report coverage; retries reuse a digest ID. Failed delivery preserves the cursor and retries; a watchdog exposes a missed report. Historical claims use immutable merge receipts, not a later live check query. Keep detailed PR evidence available without requiring the operator to read each PR.

Preserve operator feedback text and source digest/feature ID. Classify as defect, enhancement, changed requirement, priority change or acceptance. Produce impact analysis and a versioned amendment, then clarify → plan → tasks → analyze → implement → verify → review → merge. Clear feedback within authorized scope proceeds automatically; material ambiguity or changed guardrails creates a decision. Invalidate pending work based on superseded revisions. Track open, planned, delivered and accepted feedback without erasing earlier history.

### Runtime and model routing

Operator decision (2026-10-09): local implementation; trusted verification and merge authorization in GitHub Actions through a dedicated GitHub App. Provisioning remains a later package. Retain Claude execution first. Add a small runtime adapter contract: start, inspect, cancel, resume where supported, and collect structured outcome/usage. Introduce another provider only after the first end-to-end loop passes. Avoid duplicating orchestrator ownership across runtimes.

Central routing maps roles to capabilities and configured model IDs: planning/coordinating, implementation, independent review, security, browser verification and reporting. Validate available model/CLI capabilities at startup; do not assume the IDs and flags documented in this checkout are currently supported. Record fallbacks and reasons. Quota exhaustion checkpoints work and waits or selects an authorized equivalent; it never reduces verification requirements. Subscription limits and API spend are different measures: show available telemetry and mark unknown costs, rather than treating a dollar cap as subscription quota enforcement.

## Implementation sequence and acceptance tests

These are ordered work packages, not calendar commitments. Create numbered specs using the repository's existing workflow; proposed factory identifiers below are not task-ledger entries yet.

| Package | Scope and likely files | Exit evidence |
| --- | --- | --- |
| F-00: baseline repairs (A01–A03, A06, A09, A24) | Candidate-root verification; scanner/collector fail-closed behavior; current regression suites; ADR YAML, workflow conditions, DST and empty scan rollup | Broken worktree rejected despite healthy coordinator; crash/missing output rejected; valid evidence JSON mandatory; all maintained suites green on macOS/Linux; actionlint clean |
| F-01: authority (A04, A16, A20) | Approved revision/AC contract, required-check matrix, immutable task identity, trusted waiver boundary; reconcile stored/live rules | Every task names approved revision; archived IDs never reused; policy comments match live enforcement; implementer cannot mint waivers |
| F-02: evidence and independent review | collect-evidence.sh, new schema/validator, evidence-gate.yml, claude-review.yml, claude-security.yml | Exact-candidate proof and separate structured verdict; missing AC, fake PASS, stale/reused output, emission failure, tampered artifact, scanner failure and unresolved finding rejected; security reruns on each head |
| F-03: unified merge control | autonomous-ship.sh, auto-merge.yml, verified-merge.sh, merge-gate.yml, main-protection.json | All ordinary, dependency, release and rollback routes consume one policy; exact head pinned; in-progress/unrelated scans rejected; self-exemption and live-policy drift blocked |
| F-04: durable local execution | swarm-dispatch.sh, fleet-reconcile.sh, swarm-respawn.sh, local-overnight-build.sh, runtime store/supervisor | One owner per claim; stale worker fenced; all state writers/GC coordinated; archive dependencies preserved; supervised worker lifetime; isolated services; recovery without duplicate effects |
| F-05: digest delivery | daily-briefing.sh, reconcile-shipped.sh, render-overnight-report.sh, receipt schema and report cursor | More-than-50/equal-time merges covered with accurate spec/task mapping; Sydney/DST windows; outage catch-up; merge-time facts; delivery retry without duplicate reports |
| F-06: operator feedback | feedback command/registry, post-ship-close-feedback.sh, amendment and decision contracts | Feedback produces traced amendments; superseded work invalidated; partial multi-spec delivery cannot close feedback; delivered and accepted stay distinct; hotfix intake idempotent |
| F-07: routing, adoption and rollout (A21–A23) | Runtime/stack capability matrix, routing adapter, versioned installer ownership, evidence privacy/retention, metrics/docs | Quota recoverable; supported stacks verified; clean/customized upgrades preserve user content and fail on partial errors; redacted retained proof; optional second runtime |
| F-08: production delivery (A11) | Real deploy adapter, protected environment, service-bound SLOs, deployment/rollback receipts | Stub cannot claim deployment; missing metrics halt; production credential isolation and rollback drill pass; enabled separately from auto-merge |

Run F-00 first. Start F-04's shared-write locking and supervisor correction alongside authority/evidence work, but do not enable unattended parallel auto-merge until F-00 through F-04 pass. F-05 can be built against synthetic merge receipts while those controls are underway. Keep existing modified initiative STATE files untouched by this planning change.

## Pilot and rollout

1. Shadow mode: evaluate real PRs and generate reports without authorizing merges. Include deliberately defective candidates and stale/tampered evidence fixtures.
2. Controlled vertical slice: one approved noncritical feature, one implementation run, a separate verifier, trusted evidence attached to its PR, eligible merge, next digest, and one feedback-driven amendment delivered through the same chain.
3. Recovery drill: terminate workers before and after each external effect, expire leases, exhaust quota, change the integration base, fail artifact retrieval and simulate report delivery outage.
4. Bounded autonomy: enable low-risk merges with conservative concurrency. Proposed expansion threshold: 20 consecutive eligible deliveries with complete receipts, zero gate bypasses or duplicate effects, and successful recovery/reporting drills. Passing this sample is a rollout threshold, not a guarantee of defect-free software.
5. Expand approved feature classes; keep protected decisions exceptional and visible. Add an operator console after the daily operating loop works.

Measure first-pass independent verification, escaped defects/reverts, repair attempts, operator interruptions, recovery time, evidence completeness, missed digest intervals, feedback closure and quota/cost per verified feature. Merge count alone is not success.

## First deliverable

Implement F-00 as the first repair specification: “Trustworthy candidate verification and clean harness baseline.” Reproduce the audit failures first, then demonstrate that healthy coordinator/broken candidate, scanner crash, stale output, unsupported contract and malformed evidence cannot pass. Replace obsolete patch-promotion tests with current behavior assertions rather than making them advisory. Follow with F-01/F-02: “Independent, exact-candidate verification evidence.” Its demonstration should include a valid candidate that passes and invalid candidates that fail for missing ACs, self-review, stale head, changed base, forged verdict, untrusted producer and policy self-exemption. Then connect that proof to the unified merge gate before permitting autonomous delivery.

Open configuration decisions for implementation: morning delivery channel/time, approved high-risk change policy, where trusted verifier/merge identities run, artifact retention, and whether another model runtime is needed now. These decisions do not prevent beginning the evidence contract and shadow evaluator.

## Implementation progress

2026-10-09: operator approved starting the plan. Spec 006 (`specs/active/006-trustworthy-candidate-verification.md`) implements the first deterministic baseline repair slice. [Implementation record](../docs/BASELINE-REPAIR-006.md): the first baseline slice passed all 58 suites on macOS and Linux, plus focused macOS checks after Linux portability repairs. F-00 remains in progress for per-stack applicability, detached acceptance and trusted waiver/equivalent-CI controls. Actual GitHub candidate CI and independent merge authorization are not yet attested. No autonomous merge or deployment is enabled by this change.

2026-10-09 continuation: specs 007 and 008 implement detached task acceptance, rejection of candidate-writable/CI-claimed waivers, per-language test accounting, fail-closed stack detection and the strict candidate evidence validation core. See [implementation record](../docs/FACTORY-READINESS-007-008.md). F-00 remains open for complete coverage/applicability adapters; F-01/F-02 remain open for protected authority storage and authenticated coordinator receipts. The validator alone does not authorize merging. F-03–F-08 activation dependencies remain unchanged.

2026-10-09 activation: spec 009 prepares an authenticated, exact-head protected coordinator, private qyndex-factory App registration, disabled policy/preflight and request-only merge routes. Dangerous local rollback is removed. See [activation checklist](../docs/FACTORY-ACTIVATION.md). The operator selected a new private qyndex-factory App. Live App installation, protected verdict producers, policy approval and a successful shadow candidate are required before enabling merge authority; no production or Slack activation is claimed.
