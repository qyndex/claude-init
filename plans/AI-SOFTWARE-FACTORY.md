# AI software factory improvement plan

Date: 2026-10-09
Status: implementation authorized by the operator on 2026-10-09; live merge/security authority changes require a decision on the concrete activation PR.

## Objective and recommendation

Extend claude-init into a local-first factory that delivers approved requirements through implementation, independent verification, deterministic merge eligibility, automatic merging, and one daily operator digest. Operator feedback enters the same versioned specification chain. Routine PR approval should not require the operator.

Preserve the existing spec/TDD workflow, specialist agents, worktrees, CI checks, evidence rig, task ledger, and feedback registry. Add enforceable contracts and coordination around them. Do not start with a replacement framework or a large dashboard.

Operator clarification (2026-10-10): this is a reusable harness for new and existing Git repositories. No single application or deployment platform is the factory target. Repository identity, stack commands, acceptance journeys, approved spec scope, GitHub App installation, report destination and deployment adapters belong to each adopting repository’s protected configuration. qyndex/claude-init is the initial harness validation repository; its account and Slack settings must not become installer defaults. Unsupported stacks or missing configuration must produce explicit readiness blockers rather than inferred success.

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
| Request intake | Claude Code context/keyword hints; explicit authenticated Slack feedback intake | Proposed spec050: stateful Scout-first disposition, approved-work matching, clarification/spec handoff and enforced action prerequisites; distinct from role/model routing |

Sources: .github/workflows/{evidence-gate,claude-review,merge-gate,auto-merge}.yml; .github/rulesets/main-protection.json; .claude/scripts/{collect-evidence,autonomous-ship,verified-merge,swarm-dispatch,fleet-reconcile,local-overnight-build,daily-briefing}.sh; .claude/agents/specialists/feedback-extractor.md; .claude/CLAUDE.md.

Specific enforcement inconsistencies to resolve: autonomous-ship.sh rejects non-pass checks, while other merge paths rely on native auto-merge and the ruleset; merge-gate.yml returns success for an in-progress daily batch; review format lint is warning-only. Security review omits synchronize, scanner execution failures can become green, and detached CI checkouts skip task acceptance. A current check query in daily-briefing.sh cannot establish historical status at merge. The overnight launcher writes a PID lock then starts a background session; the launcher lifetime is not the worker lifetime. Shared fleet read/modify/rename writes do not provide transaction isolation.

## Target delivery contract

Supported authenticated request → intake/Scout disposition → proposed specification or matched approved work → approved spec revision → dependency-ready task → isolated implementation → independent verification → trusted policy eligibility → serialized integration and merge → merge receipt → morning digest → operator feedback → spec amendment.

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

Reporting monitoring decision (2026-10-10, approved): GitHub-only alerts are the baseline for the claude-init pilot. Keep `FACTORY_REPORTING_WATCHDOG_ENABLED=false` in the protected `factory-reporting` environment; do not configure or activate Healthchecks. Implement a protected failure notification path and a separate scheduled overdue-digest check, using the confirmed delivery checkpoint and the 08:00 Australia/Sydney cutoff with DST and a configurable grace period (default 60 minutes). Send alerts and recovery notices to the configured reporting destination, `qyndex-alerts` for the pilot. Each adopting repository supplies its own destination.

Persist alert intent before sending, reconcile uncertain Slack effects before retrying, suppress duplicate incident alerts across runs, and issue one recovery notice after delivery is current and verified. Prove failed-run, missed-schedule, repeated-check, uncertain-send and recovery scenarios before declaring live alert readiness. These alerts remain to be implemented; existing reporting and the health probe alone do not establish notification delivery.

GitHub-only monitoring shares Actions availability with reporting and cannot guarantee an alert during an Actions-wide outage. A broken Slack credential or Slack outage can also prevent same-channel alerts; preserve failures in GitHub. Independently operated timers remain optional adopter capabilities for outage coverage, not pilot readiness prerequisites. Any future external integration requires a separate operator decision and verified activation.

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
| F-05: digest delivery | daily-briefing.sh, reconcile-shipped.sh, render-overnight-report.sh, receipt schema and report cursor | More-than-50/equal-time merges covered with accurate spec/task mapping; Sydney/DST windows; outage catch-up; merge-time facts; delivery retry without duplicate reports; GitHub-only failure/overdue alerts with durable deduplication and recovery; independent monitoring optional |
| F-06: operator feedback | feedback command/registry, post-ship-close-feedback.sh, amendment and decision contracts | Feedback produces traced amendments; superseded work invalidated; partial multi-spec delivery cannot close feedback; delivered and accepted stay distinct; hotfix intake idempotent |
| F-07: routing, adoption and rollout (A21–A23) | Repository configuration contract, runtime/stack capability matrix, routing adapter, versioned installer ownership, evidence privacy/retention, metrics/docs | New and existing repository fixtures onboard without qyndex-specific defaults; repeated install is idempotent; customized upgrades preserve user content and fail on partial errors; unsupported stacks block explicitly; quota recoverable; redacted retained proof |
| F-08: reusable production delivery (A11) | Protected per-repository deployment adapter contract, environment references, service-bound SLOs, deployment/rollback receipts | Harness adapter contract passes isolated deployment and failure/rollback drills; each adopting repository must separately configure and prove its real target before production enablement; missing adapters/metrics block release; credentials isolated; enabled separately from auto-merge |

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

2026-10-09 continuation: PR #50 merged at `148238ad`; the operator explicitly approved temporarily pausing quota-blocked Claude workflows and removing only their two required contexts. Restoration remains required before autonomous authority is enabled. Spec 010 implements protected proof producers and custom candidate-head receipts; see [producer package](../docs/FACTORY-PRODUCERS.md). App registration awaits browser sign-in. The operator chose the existing subscription after its reset; no metered fallback is authorized. Live producer/shadow and F-04 through F-08 remain incomplete.

2026-10-10: PR #52 merged at `50a8e937`; App 5251754 is installed with expected permissions and selected repositories. The key and App ID are in the main-only authority environment. Review pause restoration remains required. Spec 011 implements transactional runtime claims and a durable reconciliation outbox, the foundation of F-04. Supervisor integration, migration of shared writers and live shadow proof remain outstanding. No factory authority is enabled.

2026-10-10 scope clarification: production endpoints are inputs supplied during repository adoption, not prerequisites for building this harness. F-08 validates reusable contracts and realistic isolated adapter drills; it cannot certify every future service. Repository-specific production readiness remains disabled until that repository proves actual deployment, health and rollback. PR #53 merged the F-04 transactional state foundation at `9d02c7b7`; supervisor and shared-writer migration remain open.

2026-10-10: PR #54 merged supervisor and shared-writer integration at `9e2d0aa9`. Spec 012 proves foreground ownership, heartbeat renewal, descendant shutdown, detached launch, concurrent fleet/ledger writers, dependency-preserving GC and an actual overnight timeout fixture. All current PR checks passed. F-04 remains open for approved-ledger import, remaining direct writers, service isolation and abrupt-death recovery adapters. Factory authority remains disabled.

2026-10-10: PR #55 merged spec 013 at `45383d80`. All PR checks passed; acceptance evidence proves approved dependency closure imports, atomic rollback, archive-aware IDs, retained helper values, unified task/memory/GC locks and concurrent inherited TCP/private-directory resources. Protected GitHub receipt ingestion, abrupt supervisor-death reconciliation and unsupported external-service adapters remain F-04 readiness blockers. Factory authority remains disabled.

2026-10-10: PR #56 merged at `22391eab` after all seven required checks passed. Spec 014 adds authenticated single-task coordinator receipt ingestion and guardian cleanup/fencing after abrupt supervisor death. Acceptance evidence proves 4/4 ACs with real process-tree drills and synthetic GitHub responses. Live independently reviewed receipts, external adapter fencing and later digest/feedback/adoption packages remain pending. Factory authority remains disabled.

2026-10-10: PR #57 merged spec 015 at `28db5cab` after all seven required checks passed. The F-05 digest core proves 4/4 ACs: paginated/equal-time merges, receipt-based task mapping, Sydney/DST cutoffs, immutable batches and uncertain-send reconciliation with independent-process exclusion. A real read-only preparation drill collected six merged PRs with honest missing-evidence status. Live Slack transport/scheduling, watchdog and delayed-index coverage audit remain pending. Factory activation remains disabled.

2026-10-10 continuation: PR #58 (spec 016 Slack transport/runner/watchdog) merged at `55f91379`; PR #59 (spec 017 late-merge coverage) merged at `e17289b3`. All required checks passed for each. Dedicated self-hosted Actions reporting was selected; channel C0C7T1Y29K5 and a main-only factory-reporting environment are prepared. Host/team/group and bot/policy credentials remain activation inputs. Spec 018 is being implemented; no reporting enablement or Slack send has occurred.

2026-10-10: PR #60 merged spec 018 protected persistent reporting Actions at `a64cd571b4efff56dcdf903f2ae14bba93a01388` after all seven required checks passed. Reporting remains disabled pending dedicated runner host/group, Slack team/bot and read-only organization policy credential. No live delivery or registration occurred.

2026-10-10: PR #61 merged spec 019 feedback core at b33569c63b5183467ee0e0208f5d0ac6946aa0b2 with all seven required checks passing.

2026-10-10: PR #62 merged spec 020 strict installer source at 4965c7f9d2e8b577c53d96f0a7752d786cd07e0a with all seven required checks passing.

2026-10-10: Operator approved a claude-init reporting pilot and then selected GitHub-hosted Actions with durable state, replacing the pilot self-hosted-host prerequisite. Team T0B2VADDUG4 and channel C0C7T1Y29K5 are reporting environment variables; no master enablement or sends occurred. Durable backend selection remains pending.

2026-10-10: PR #63 merged hosted reporting spec 021 at `a896dc06` with all seven required checks passing. Live GitHub bootstrap created protected data-only branch factory-reporting-state (ruleset 24826406), verified stale concurrent writer rejection and fresh checkpoint recovery, and stored pilot configuration. Master reporting remains unset pending Slack bot credentials and live identity/delivery proof. No Slack report was sent.

2026-10-10: PR #64 merged live reporting bootstrap evidence and the main ruleset selector repair after all seven required checks passed. Actual workflow fixtures cover reordered policies, missing/duplicate matching main protection and missing contexts; live validation finds all seven main contexts. Reporting is disabled while the operator creates/installs the Slack bot and stores its environment token. Real installer upgrade audit reproduced successful overwrite of a customized command; manifest ownership and transactional upgrade remain the next adoption repair.

2026-10-10: PR #65 merged reporting preflight and exact history receipt readback at `dd7b0bc3` with all seven required checks passing. Read-only positive and wrong-workspace negative probes run before delivery; confirmed state survives blocked readback. The operator-provided Slack token is available through an effective organization secret, with no token extraction. Live pilot and repeat-run verification are in progress; autonomous merge authority remains disabled.

2026-10-10: PR #66 merged safe Slack diagnostics at `3a82cb40` after all seven required checks passed. Live hosted run 38016158102 authenticated the expected workspace but history returned `not_in_channel`; preflight stopped before sending or changing the initial checkpoint. Reporting enablement was removed automatically. Operator must invite the app matching the stored bot token to qyndex-alerts before live delivery/repeat-run proof can proceed. [Local live status](../docs/audits/2026-10-10/reporting-live/status.json).

2026-10-10: PR #67 merged spec 022 at `ccbe745b` after all seven required checks passed. Protected settled policy approval enables contents-only reporting to verify GitHub rules with hidden bypass lists; reporter receives no administration credential. Live run 38017581266 passes private Slack history and identity checks but records an uncertain 34-PR catch-up send. Reporting is automatically disabled; preserve checkpoint `50a3e8aa` and reconcile before retry. PR #68 adds fixed receipt diagnostics with refreshed specs 016/021/022 evidence. Autonomous merge authority remains disabled.

2026-10-10 live activation: PRs #68–71 merged with all seven required checks passing. Spec 023 recovers the original two-message Slack catch-up after exact whole-report, bot and metadata validation. Runs 38019626144 and 38019653271 prove confirmed receipt and unchanged not-due repeat; checkpoint `333104acce138924243515a24b0071c28e356f7a`, 34 historical merged PRs, no resend. Reporting enabled for 08:00 Sydney via GitHub-hosted Actions; public live audit is being published in PR #72. Historical authenticated proof and remaining factory packages stay open; merge authority and proof producers remain disabled.

2026-10-10: PR #72 published the successful live activation audit and readiness-plan update, merged after all seven required checks passed. Reporting remains enabled; independent producers and merge authority remain disabled.

2026-10-10: PR #73 merged spec 024 at `41ffe89d` with all seven required checks passing. Fresh hosted reporting projects authenticated coordinator delivery proof without runtime task authority, preserves merge-time spec identities and continues to label unproven historical merges missing. Spec 025 verified oversized attachments is in implementation; live scopes/readback and the remaining F-05 through F-08 work remain open.

2026-10-10: PR #74 merged spec 025 at `cf185931` with all seven required checks passing. Verified oversized file delivery retains complete reports and no-resend uncertainty; live file scopes/readback remain pending, so opt-in file delivery stays disabled. Spec 026 independent watchdog implementation is underway; normal reporting remains enabled.

### F-05 watchdog implementation merged (026)

PR #75 merged at 122611702f3c3c10620456a17c8599dfde00d16a after all seven required gates passed. Read-only checkpoint/receipt health and opt-in heartbeat adapter are implemented. External timer and same-channel outage/recovery alert drill remain unconfigured; live reporting stays active.

### F-05 live attachment grants confirmed (027)

PR #76 merged after all seven required checks. Protected reporting run 38030371759 verified installed files:read and files:write grants, correct workspace/bot and private-channel history. Attachment opt-in is enabled in factory-reporting; report returned not-due without sending another digest. Actual file receipt verification remains pending the isolated canary.

### Pilot monitoring preference revised

The operator declines Healthchecks.io or another additional monitoring provider. GitHub-only failure and overdue-digest alerts are the approved pilot baseline; independently operated outage coverage remains optional. Keep the existing heartbeat integration disabled. Same-channel Slack credential/outage failures and Actions-wide outages cannot guarantee Slack alert delivery.

### F-05 isolated file canary (028)

PR #77 merged at 11a13811b091d33d7aedcbd5216bb63bb7d2867b after all seven required checks. The protected live canary run 38030784364 failed without establishing a receipt. Do not claim live file delivery or blindly allocate again. Fixed non-sensitive failure diagnostics are under review in PR #78; subsequent dispatch must reconcile the original share or block. Daily reporting state is untouched by the canary.

### Monitoring baseline approved and attachment activation status

The operator selected GitHub-only alerts, with independent monitoring optional. Next implementation must provide protected GitHub failure/overdue checks, durable duplicate suppression and recovery notices to the configured Slack destination, documenting shared GitHub/Slack outage limitations. No third-party monitoring account or heartbeat is required.

PR #78 merged at 0267f79a3c8a83298060c7053abc179c8e799ecb after required checks. Live reconciliation run 38031153769 found no authoritative existing canary receipt and stopped at allocation-fence; it did not allocate another file. Attachment opt-in is false pending reconciliation; normal reporting remains enabled. Installed file grants are proven, live file delivery is not. Preserve prior run history; do not reset the fence to manufacture proof.

2026-10-10: PR #79 merged GitHub-only reporting alerts. Protected monitor is enabled; live labelled drill 38032511382 sent one alert, recovery 38032644344 sent one recovery, repeat 38032841379 sent none. Digest cursor and batch count remained unchanged. Healthchecks stays disabled. Private authenticated feedback ingress is next; independent merge authority remains disabled.

2026-10-10: PR #80 merged authenticated private Slack feedback at 3e755cd with all seven required checks passing. Exact delivered-receipt binding, private capture, immutable edits and hotfix urgency pass fixtures. Live ingress awaits protected operator identity and isolated coordinator provisioning. Authenticated amendment/acceptance transitions are next.

2026-10-10: PR #81 merged authenticated exact-version feedback decisions at c721a7bc with all seven required checks passing. Durable command recovery and transactional stale-version fencing pass fixtures. Legacy migration is next; live private operator control remains disabled pending provisioning.

2026-10-10: PR #82 merged private approved legacy feedback migration at b03850f with all seven required checks passing. Original metadata/history stays private; approved promotion starts open and does not infer delivery from historical shipped status. Transactional adopter ownership is next.

2026-10-10: PR #83 merged transactional adopter ownership at 198accd with all seven required checks passing. Protected runtime routing is in progress; live routing remains disabled until authenticated capacity and worker isolation are verified.

2026-10-10 operator decision: use encrypted feedback state on the adopting repository's state branch, processed by GitHub Actions. Keep the encryption key in a main-only GitHub environment; publish no plaintext feedback or operator command bodies. Validate authenticated encryption and repository binding before opening recovered state, preserve Git compare-and-swap recovery, and leave feedback intake disabled until the protected Slack operator allowlist and encrypted coordinator are configured. Healthchecks remains disabled and GitHub-only monitoring remains the pilot baseline.

2026-10-11: The operator supplied Slack member ID U0B3L0TRCTA directly, removing the email-lookup dependency. Use this ID as the explicit pilot allowlist in the main-only factory-reporting environment. No additional Slack email-directory scopes are needed. Encrypted hosted feedback storage and its recovery verification remain to implement before live intake activation.

2026-10-11: PR #84 merged encrypted private SQLite checkpoint codec at a886441 after all seven required checks passed. Real AES-GCM, authenticated context, private temporary storage, tampering and lost-ack replay tests pass. Hosted intake integration is in progress as spec 035; it remains disabled pending merged workflow, key/bootstrap provisioning and live preflight.

2026-10-11: PR #85 merged hosted encrypted feedback at 16e9d6c with all seven required gates passing. Key/allowlist/start/bootstrap are prepared; intake stays disabled because automatic approval review requires explicit approval of the private-Slack-to-encrypted-public-state flow. No live feedback capture ran. All 90 maintained macOS suites passed in the disposable spec-035 checkout. Worker credential filtering is spec 036 in PR #86; native OS/container isolation remains open.

2026-10-11: Spec 036 merged as PR #86 at d4c90633 after all seven required checks passed. Dedicated implementation credentials and deny-by-default worker environments are verified; same-user filesystem isolation remains an open rollout gate.

2026-10-11: Spec 037 merged as PR #87 at 19c160cf after all seven required checks passed. Protected role/model routing, approved-ledger bindings and explicit private SQLite connection cleanup are verified locally. Live capacity and OS isolation remain rollout gates; external daemon-effect fencing is the next prerequisite.

Spec 038 durable worker effects merged in PR #88 at 8503762a0ae4146c4e37f3afa12cf4593041d3dd after all seven required checks passed. Immutable intent and typed cleanup observations fence retry and verification until external effects are resolved. Actual daemon isolation is tracked in spec 039.

### Live encrypted feedback pilot — approved and activated 2026-10-11

Operator approval enabled main-only FACTORY_FEEDBACK_ENABLED. Runs 38105153848 and 38105185846 succeeded: zero eligible messages captured, identical encrypted checkpoint 03970ba75ca574c88e1b38fb5c6ee9d63e782c7b, ciphertext-only envelope valid and existing public reporting blobs unchanged. Intake does not approve amendments or activate merge authority. No eligible real feedback has been captured yet.

Spec 039 merged in PR #89 at d72ba160c4daafdce445411586b1e00ef158c119 after all seven required checks. Actual final-head Linux Docker drill and 95 maintained shell suites passed. Offline isolation is verified; provider egress, dedicated production workers and authenticated subscription/reviewer rollout remain separate gates.

Spec 040 merged in PR #90 at ae99ee3927f68af0e88914d2db9abeb4bd3624b6 after all seven required checks. Neutral examples and pinned dependencies now participate in transactional package ownership. The real Docker retry drill observes inherited task-lock release before retry. Private output/retention is next spec041.

Spec 041 merged in PR #91 at 99528e3b54ca9248613c46ba63b2f5d526bbfacc after all seven required checks passed, including final-head Linux isolation and maintained-suite proof. Production contract work follows; independent live reviewer and worker rollout remain separate activation gates.

PR #92 merged spec 042 at 18ef654dec222cedf9f5d3b7b2e2a61a6ea35ac5; PR #93 merged spec 043 at f04b28dad6189251c49b88605cd38300a8af25af. Each passed all seven required checks. Production core and real isolated HTTP rollout/rollback recovery are implemented; each adopter must prove its actual target and durable backend before activation. Full workflow baseline cleanup is PR #94; its initial Linux lint failure is being corrected, so it remains draft. Native Claude Max now authenticates, but capacity and live independent shadow proof remain unproven. Worker location and fenced oversized file decisions are pending.

### Current readiness — 2026-10-11

This table supersedes earlier pending activation notes; dated entries above remain historical records. Code completion and live autonomous rollout are distinct.

| Package | Current evidence | Remaining activation gate |
| --- | --- | --- |
| F-00 | Scanner/evidence/acceptance repairs, maintained macOS/Linux checks and full workflow ShellCheck/actionlint regression | Generic baseline complete; PR #94 merged after all seven required checks |
| F-01–F-03 | Protected approved-spec contracts, exact-candidate evidence/receipt authentication, unified request-only merge routes; dedicated App installed | Genuine independent subscription review, restored paused checks, trusted shadow proof and concrete authority activation decision |
| F-04 | Transactional claims, supervisor recovery, durable external-effect fencing and actual offline Linux Docker isolation | Online native worker isolation/provider-egress setup; operator host decision pending |
| F-05 | Live 08:00 Sydney GitHub-hosted digest, durable checkpoint and GitHub-only failure/overdue alerts | Oversized Slack file pilot remains allocation-fenced; keep disabled or explicitly approve separate canary reconciliation; Healthchecks stays disabled |
| F-06 | Authenticated allowlist, amendment/acceptance contracts and approved live encrypted feedback intake | Both live runs captured zero eligible commands; actual feedback-driven delivery proof belongs to the controlled vertical slice |
| F-07 | Transactional new/existing adoption, neutral disabled references, capability/routing fixtures, bounded private artifacts/retention | Local native CLI now authenticates as Claude Max; usable capacity and independent live review remain unproven after the agreed reset |
| F-08 | PR #93 merged at f04b28dad6189251c49b88605cd38300a8af25af: protected core, actual HTTP progressive/SLO/rollback drills, durable uncertain-effect reconciliation and neutral disabled distribution | Each adopter supplies and proves its real protected provider, known-good baseline, durable backend and target health before enabling production |

PR #91 merged bounded private artifacts; PR #92 merged the always-refusing placeholder deploy fence; PR #93 merged the production core. All seven required checks passed on each exact candidate, including the maintained Linux suite and actual offline container drill. Fixture/manual harness merges do not constitute autonomous delivery receipts or the twenty-delivery rollout threshold.

Next live sequence: resolve worker/attachment decisions; after existing subscription capacity resets, prove separate protected reviewer/verifier runs, restore paused review/security checks, run shadow eligibility, obtain the concrete authority activation decision, deliver one approved controlled feature through merge/digest/feedback, then collect twenty genuine eligible deliveries before broadening autonomy. No metered fallback, provider switch, invented production service or fabricated proof is authorized.

Spec 044 merged in PR #94 at d29e16c344e611bf68db9137c52685b92dc65257. All 100 maintained macOS tests passed on canonical isolated source c6c03e9; final-head Linux run 38110819868 passed the full harness and actual offline container drill. All seven required checks passed on 8d7adc40d0d1909436c6a791030baa2acf8ce06c.

Approved encrypted feedback revalidation on merged spec-043 main succeeded in run 38110996228: captured zero eligible commands and retained checkpoint 03970ba75ca574c88e1b38fb5c6ee9d63e782c7b. Native quota, isolated online worker location and fenced attachment decisions are pending; authority/producers/production remain disabled.


Spec 045 merged in PR #95 at 8374075855cb7ded3b9465a34203ffc51ff525de after all seven required checks passed on 417916fcf611a78f9a106722f53e00ed524f121c. Final Linux run 38119184325 passed the maintained suite and actual offline Docker drill. Hosted review now bounds stdin/output, uses fresh scoped sessions and validates observed protected model usage. Claude review remains paused until Tuesday; no model or authority activation occurred. Spec 046 follows to repair policy-bound ruleset generation and updated-head security triggers.


### Implementation complete through spec 046 — 2026-10-11

PR #96 merged at 60b93a313f5a57760d2ad8602e0d88850b713b8c after all seven required final-head checks passed; Linux Harness Validate run 38120623168 succeeded. All 102 maintained macOS suites passed, preserving two initial dependency failures and successful pinned-crypto reruns. T-171 baseline CI record is reconciled. No additional mandatory pre-Tuesday source package remains. Claude review stays paused until Tuesday. Genuine protected reviewer/verifier receipts, restored checks, shadow proof, the concrete authority decision, controlled delivery/feedback and the twenty-delivery rollout sample remain live gates. Per-adopter online isolation and production proof remain configuration requirements; optional fenced attachments and Healthchecks remain disabled.


### Activation review package prepared — spec 047

PR #97 merged at 1aefcbeda51e382bde8c76300fccbb46a968ba44 with all seven required final-head checks passing, including Linux Harness Validate 38127709550 and its dedicated actual Docker isolation drill. docs/activation/2026-10-11 contains source-bound shadow policy/ruleset proposals, observed non-secret workflow/environment metadata, reproducible structural preflight, proposed spec/plan 048 and ten shadow cases. The proposed pilot and T-222 are not approved/reserved; check IDs and promote exact final bytes only through the concrete operator decision. Historical package checks tolerate future activation and runtime revisions; real transactional adopter installation preserves adopter-owned activation data and makes no source-pilot readiness claim. Live default-branch policy bytes remain unchanged/disabled; Claude review/security remain paused until Tuesday. No model request, authority enablement, live shadow or delivery receipt is claimed.

### Proposed pilot sandbox feasibility (049)

Spec049 adds exact proposed pilot argv execution in the digest-pinned Python verifier sandbox. Actual Linux run 38132880404 on 56b123985fac1f48bd436e5a4603ef5aca7e24e2 passed all three positive and individually defective cases plus nonroot/offline/read-only/host-exclusion assertions; native artifact retained. This is preparation feasibility, not authenticated candidate verification, approved spec048, shadow authority or delivery proof. Claude remains paused until Tuesday and live authority/producers remain disabled. PR #98 merged at 71844c2a2164528430b65b01940aa81f5f161d92 with all seven required final-head checks passing. Final Linux run38133154461 passed the maintained suite and both native Docker drills on b6162eca3c5b81f4bdbbcf0a34cb565cbc16d6a4; final-head pilot artifact verified.

### Pilot and conditional shadow approval — 2026-10-11

The operator explicitly approved both spec048 and shadow-only activation. The exact approved specification and plan are promoted and T-222 is reserved, still open. docs/activation/2026-10-11/policy.shadow.approved.json binds final approved spec bytes; shadow-approval.json records Tuesday 13 October Sydney, actual capacity/model proof, refreshed source/rule before-images and merge_enabled=false conditions. Live factory/policy.json and switches are unchanged, so no producer or authority is activated. Approval registration is documentation-only and does not prove spec048 delivery ACs. Its prepared quickstart remains a later single-file candidate. PR #98 sandbox feasibility is merged at 71844c2a2164528430b65b01940aa81f5f161d92; final Linux run38133154461 passed all maintained checks and both native Docker drills. Genuine shadow proof precedes a separate merge-mode decision.

Approval registration PR #99 merged at 7e5815da517d9db103c5283543d08318883e7e6a with all seven required final-head checks passing, including Linux38136502444. The required evidence gate demands committed proof files while the approved one-document scope excludes them; actual local gate/scope conflict reproduced. A proposed narrow amendment for eight exact proof paths is awaiting operator decision. No gate is weakened and live authority remains disabled.

### Pilot proof scope integration — 2026-10-11

Approval registration PR #99 merged at 7e5815da517d9db103c5283543d08318883e7e6a with all seven required checks, including Linux38136502444. The exact one-document scope conflicted with the required committed-evidence gate. After an actual gate/scope reproduction, the human approved eight exact proof paths (option1A). Spec048 and the approved shadow policy are amended together; approval record retains previous binding and added paths. Only the quickstart feature and its eight fixed proof files are permitted; no gate, runtime, live policy or workflow switch is changed. T-222 remains open, review paused until Tuesday, and merge mode requires separate approval after genuine shadow proof.

Proof-scope amendment PR #100 merged at 10026982e8d9e6b46bcfa0c3ee65218a32b7df9e with all seven required final-head checks passing, including Linux38137915612. The eight-proof-path decision is resolved. Online implementation-worker activation, optional fenced attachments and the source of the twenty genuine deliveries remain discussed rollout choices; they do not block preparing the controlled documentation candidate.

### Recommended rollout choices accepted — 2026-10-11

The human instructed continuing with the recommended decisions: retain optional oversized Slack attachments disabled, defer online-worker activation to each adopter that needs and proves isolated online execution, and accumulate twenty useful separately approved authenticated deliveries naturally rather than inventing changes. First prove the controlled quickstart delivery/digest/authenticated-feedback/amendment cycle. These choices do not waive per-adopter isolation or production proof, the Tuesday subscription-capacity gate, genuine shadow cases or the separate merge-mode decision. The quickstart pilot is prepared through interactive implementation; T-222 stays open until actual authenticated delivery.

### Controlled quickstart draft prepared — 2026-10-11

PR #101 is draft on factory/spec-048/adopter-quickstart, head4fa31d2f6bbeeeb19bc4af745e3f6d34344b2cef and protected base10026982e8d9e6b46bcfa0c3ee65218a32b7df9e. Its exact nine-path diff contains the approved document and eight proof files, with actual missing-document assertion red, worktree green, all three exact AC commands and a complete local collector PASS. Local evidence binds source2a032ea and independent_attestation=false; T-222 remains open. Read-only review found no actionable findings. All seven required final-head checks passed; Linux38139128012 succeeded, including the maintained suite and both native Docker drills. PR #101 remains draft/open with no auto-merge request. These are preparation checks, not authenticated protected reviewer/verifier or delivery receipts. No draft document is copied into the primary source mirror or claimed delivered. After Tuesday actual capacity/model proof, publish the reviewed shadow configuration on protected main, refresh/rebase candidate/evidence and run genuine separate producer/shadow gates before presenting a merge-mode decision.

### Monday readiness recheck — 2026-10-12

Live read-only recheck confirms main10026982e8d9e6b46bcfa0c3ee65218a32b7df9e, draft/open PR #101 head4fa31d2f6bbeeeb19bc4af745e3f6d34344b2cef, all seven required checks passing and no auto-merge request. Review/security are disabled_manually; both authority/producer switches are absent (off). Default-branch live policy SHA256ee5756f3e44ee0bf7e729dc8ee94647e66c6278f84fabf4af4fd8dbb7ca4e3f5 remains unchanged/disabled. Fresh GET-only ruleset planner output matches the earlier additive proposal; approved spec digest and complete runtime pins match actual protected main. No model, Slack send, rule write or activation occurs. T-222/spec048 is the only open factory task: Tuesday13October capacity/model proof must precede protected producer/shadow execution, then separate merge-mode approval and real delivery/digest/authenticated-feedback amendment. Deferred online workers and disabled optional attachments require no present operator decision; collect twenty real useful deliveries naturally. All presently executable preparation is complete.

### F-09 — automatic request intake (new scope, spec050 review) — 2026-10-12

The operator identified a missing capability after implementation readiness: ordinary incoming messages are not automatically governed by a Scout-first decision chain. Earlier completion statements apply to the prior scope; this new request adds a proposed package, not an already completed feature.

Spec050 at specs/active/050-request-intake-router.md and docs/SCOUT-INTAKE-REVIEW.md are proposed review artifacts. The user confirmed the initial scope as every installed Claude Code prompt plus the existing explicit authenticated Slack feedback bridge, lightweight answer/status routing and read-only Scout assessment for changes/uncertainty. New or materially changed requirements require human scope approval; current approved work may resume under existing gates. A valid intake disposition is required at governed action boundaries; keyword hints alone are insufficient, and routing never grants protected eligibility.

All four clarification decisions are resolved: Claude Code plus existing authenticated Slack feedback; approve new/changed scope and resume approved work automatically; lightweight every-prompt intake with Scout when needed; automatically start permitted handoffs. Spec050 is status review, not approved. After review and exact spec approval, author a technical plan and tasks. Prove the actual Claude Code entry and guarded handoffs first, then the existing authenticated Slack bridge and neutral adopter coverage. Generic Slack/GitHub/Codex/other-IDE intake requires separately approved adapter scope. Reuse private durable state, existing protected role/provider policy and amendment/receipt contracts; no online worker, provider switch, monitoring service or live authority is introduced by this proposal.

This package is distinct from the already approved pilot048: do not alter its source scope, pause, live-policy pins or count local Scout fixtures toward genuine deliveries. Review remains paused until Tuesday; spec050 drafting makes no model call or activation. No implementation task IDs are reserved or marked complete, and no approved technical plan is claimed.

### Spec050 approval and technical entry decision — 2026-10-12

The human approved spec050. The draft technical plan050 and proposed ADR0005 now describe a private controller, guarded console entry, bounded tool-free Scout, authenticated Slack integration and adopter coverage. Acceptance identifiers were mechanically normalized to the existing canonical bold-ID format without changing acceptance requirements. One material entry decision remains: launch the guarded factory console once per session, or require a stronger proven adapter for the ordinary native UI. Official UserPromptSubmit payloads cannot prove human origin and include generated callbacks. No implementation tasks are reserved; no model call, pilot scope change or activation occurred. This approval supersedes the preceding spec-review status.

### Spec050 guarded-console decision — 2026-10-12

The human selected the guarded factory console. Plan050 is approved and ADR0005 accepted. Proceed with source implementation and offline fixtures in phase order; model calls and live activation remain separately gated. Bare native sessions remain advisory. Existing pilot048 and its exact approval scope are unchanged.


### Current continuation — 2026-10-16

Spec050 merged as PR #104 at f2e14119001141748a410f86d2ffb7cb50f7be19 after all seven required checks passed. Its full offline acceptance passed 11 suites and 14/14 criteria; this does not certify live native intake or activate factory authority. Earlier proposed/paused entries above are historical.

The canonical next task is T-273: finish the operator-selected exact Claude Sonnet 5.5 reviewer pin before refreshing protected runtime hashes. Current local CLI 2.1.300 authenticated as first-party Claude Max, and the bounded tool-free exact-model probe returned available=true. Quota remains unknown and reported client cost is an estimate, not subscription spend. This is local capacity evidence, not an authenticated hosted review verdict.

Remaining sequence: merge the verified reviewer configuration through the operator route; refresh source-bound shadow policy, runtime pins and live rule before-images; prove separate protected verifier/reviewer runs on the exact controlled pilot candidate; restore paused checks under the existing conditional approval; run positive and negative shadow cases with merge_enabled=false; present genuine shadow evidence and the exact merge-mode revision for the separate human decision. T-222 remains open until actual authenticated delivery, followed by morning digest and authentic feedback/amendment delivery. Twenty useful real eligible deliveries are required before broadening autonomy.

Online workers remain per-adopter and independently gated. Optional oversized attachments and Healthchecks stay disabled. Production remains target-specific and disabled without actual health/SLO/rollback proof. No live switch, policy or rule was changed by this continuation record.


### Reviewer readiness completed; shadow refresh prepared — 2026-10-16

PR105 merged at cf3b2fff928169973494fc15eb86a0176aa2dd1f with all seven required checks passing. T-273 pins Sonnet5.5 and validates exact observed model usage; a deterministic test-only counter race found by Linux CI is fixed. The separate bounded live local Claude Max probe succeeded; it is not an independent hosted verdict. Claude PR Review and Claude Security Review are restored to active after the existing date/capacity conditions, with no required-check bypass.

The refreshed shadow package in docs/activation/2026-10-16 binds the actual merged runtime. Spec048 scope, commands and image remain unchanged; merge_enabled remains false. Its proposed policy, preserved live rule before-image, additive proposal and metadata preflight are reviewable together. This preparation does not enable repository producer/authority switches or apply live rules. Genuine exact-candidate producer runs and shadow cases remain next; merge mode still needs the separate post-shadow decision.

### Shadow attempt and producer provenance repair — 2026-10-16

The operator selected option A approving PR106's scanner-policy change and the
shadow-only continuation. PR106 merged at
d036af6740cb8e4b9cf56a640ff796f617b191ee with required checks passing. The refreshed
pilot PR101 reached candidate 78c690b78c856369d8e2e2f0efa35e9ec71132bf with its
approved nine-path scope and fresh local acceptance evidence.

Genuine verifier run38813649635 and reviewer run38813649657 failed safely before
acceptance/model execution: their REST head_sha identifies the candidate, while
the existing code expected the protected base. Historical run associations can
report updated PR base/head values and cannot establish executed-source identity.
T-274 repairs the existing Spec010 provenance contract; its local fixtures cannot
substitute for genuine signed proof. The reviewable proposal and adoption tradeoff
are in docs/activation/2026-10-16/producer-provenance-decision.md. The proposed
GitHub-native attestation approach and solely the proof-signing permissions were
approved by the operator on 2026-10-16 (option A). Private/internal repositories
require Enterprise Cloud for that backend; unsupported adopters fail closed.
This decision does not authorize merge mode or production.

The pilot is back in draft, producers are paused, authority remains unset, and
merge_enabled remains false. No additive live ruleset has been applied. Reporting
and approved encrypted feedback remain enabled. After the repair is reviewed,
merged and pinned, resume genuine producers, then shadow cases and the separate
merge-mode decision. T-180 and T-222 remain unresolved.
