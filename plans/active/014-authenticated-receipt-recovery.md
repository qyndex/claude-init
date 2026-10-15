---
id: 014
slug: authenticated-receipt-recovery
spec: specs/active/014-authenticated-receipt-recovery.md
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-16
---

# Authenticated receipt and worker recovery

Authenticate coordinator artifacts through GitHub API run/workflow metadata, historical source pins, archive digest and actual merged PR identity. Read the policy at the pinned run revision and bind the task mapping/spec hash. Write delivery and provenance in one local transaction; never accept a candidate-provided file as receipt input. Pin the coordinator checkout to the Actions source SHA.

Wrap the actual worker in a separate guardian owning the worker process group and inherited resource descriptors. The supervisor alone owns the liveness pipe writer. EOF after supervisor death triggers bounded worker cleanup before fencing/requeue; cleanup failure blocks recovery. Preserve an attempt outcome and uncertain outbox actions. Test live disposable process trees and fake authenticated GitHub responses with real ZIP digests.

The initial receipt contract accepts one explicitly approved task per delivery. Automated fixtures cover artifact/source/PR negatives, immutable replay, a real SIGKILL process tree, duplicate exclusion and fenced retry. Live receipt ingestion and simultaneous guardian death remain separate readiness work.

## Approved durable receipt continuation — 2026-10-16

Approved option A and retention A extend AC-1/2 and add AC-5–8. Guardian AC-3/4 and existing T-187 remain unchanged. No runtime implementation or activation is claimed by this planning change.

### Architecture and authority

Load fixed `factory/receipt-trust.json` separately from `factory/policy.json`; profiles never hash themselves and never mutate canonical source policy. Each profile has unique immutable ID, active/revoked state, exact canonical source-policy digest and complete exact emitter runtime closure (merge workflow, coordinator, activation preflight, evidence contract, provenance and bounded helpers). Fetch immutable run-head source bytes as bounded data after checking GitHub repository/workflow/event/default branch/run attempt/success. Reject missing dependencies and unknown schema fields. Explicit legacy source mode has no mismatch fallback. Both modes enforce current revocations; retained reported facts acquire a withdrawn-trust annotation instead of deletion. Current task/spec checks stay separate from historical merge-time projection.

Use the existing state branch/protected writer, not a new service. Append content-addressed compact proof records and deduplicated policy/spec/runtime material plus segmented indices; retain original bounded receipt artifact bytes and origin metadata sufficient for reconstruction. The bootstrap explicitly binds repository, branch and coverage origin. Writer trust is inherited from reviewed GitHub API authentication and the protected writer; arbitrary copied JSON/blob digests are insufficient origin proof. Protect the new profile and archive writer under existing authority paths. No additional workflow signing permissions.

### Data and bounded API contracts

Profile schema version 1: repository, profiles (id/status/policy_sha256/runtime hashes), explicit legacy revisions. Archive schema version 1: repository, origin, record identity run_id/attempt/artifact_id, archive/receipt digest, profile identity/hash, source SHA, policy/spec/runtime material references, authentication facts and immutable delivery. Discovery schema version 1: audited coverage boundary, per-run attempts, unresolved journal, continuation cursor, last complete reconciliation and coverage status/reason. APIs remain GitHub GET for run/source/artifact reads and existing non-forced branch CAS for writes; reject identity conflicts before projection. No new package dependency.

Conservative fail-closed implementation budgets: receipt ZIP 4 MiB, individual retained record 1 MiB, shared source object 1 MiB, index segment 256 records/1 MiB, per invocation 100 run pages of 100 and 100 new artifacts, aggregate downloaded bytes 32 MiB. Validate decompressed size/member counts using existing bounded archive conventions. Reaching any limit persists a resumable unresolved boundary and reports incomplete coverage; never prune or imply success. Budgets limit each operation, not lifetime history. Append additional bounded segments indefinitely. Exhausted storage/write errors block coverage claims and alert through existing reporting.

Discovery combines existing protected coordinator completion signals with paginated periodic reconciliation. Persist every observed run/attempt needing resolution, including failed/in-progress runs subject to later reruns. Revisit unresolved attempts before moving completeness boundary; recognize new attempts for old run IDs. Use overlapping created-time reconciliation only as optimization, never as sole completeness evidence. Retain non-delivery outcomes after authenticating/classifying their receipt so expired shadows do not block forever. Cold start/backfill is restartable; absent artifacts before approved origin are labelled outside coverage, absent required artifacts after origin are explicit gaps. An operator-reviewed initial boundary is required before first unattended merge; no automatic origin reset.

### Sequential phases and exit criteria

1. Content trust: strict profile parsing, immutable source equivalence, revocation/current-task separation; AC-1/2/5 fixture tests reject all authority changes and accept two ordinary source commits. Existing receipt behavior remains explicit legacy mode.
2. Retained proof: bounded archive authentication, origin/bootstrap and append-only CAS preservation; AC-6/8 tests reconstruct after artifact expiry and reject tampering/conflicts/private leakage.
3. Complete discovery: resumable indices, reruns/late visibility/backfill and budget exhaustion; AC-7 tests exceed 1,000 historical runs with bounded new work, restart and expose missing history.
4. Integration: hosted digest and alerts use profiles/archive/discovery; docs/preflight distinguish local completion from actual retained-proof/CAS/coverage activation. Cross-layer tests preserve guardian AC-3/4. No live activation in implementation tasks.

### Risks, rollback and observability

Archive writer compromise remains a distinct trust risk: document it, protect writer/profile paths and never describe unsigned retained JSON as portable cryptographic proof. Revocation applies at read time and retains immutable withdrawn facts. CAS conflicts re-read/reconcile at most three attempts then fail closed, preserving encrypted envelopes byte-for-byte. Privacy/store mismatch blocks writes. Roll back to paused reporting/merge-disabled operation; explicit legacy imports remain available for audited history, not automatic fallback. Never delete retained records during rollback. Emit bounded counts of scanned/pending/authenticated/revoked records, completeness reason, CAS retries and archive bytes; exclude tokens, provider output, Slack plaintext and private payloads from public logs.

### Verification and references

Every following task requires fail-first behavioral fixtures and actual acceptance before completion. No current implementation PASS is asserted. References: `docs/FACTORY-DIGEST.md` retained-proof limitation; `.claude/scripts/factory-receipts.py`; `.claude/scripts/factory-git-state.py`; `.claude/scripts/factory-coordinator.py`; ADR-0007 `.claude/memory/decisions/0007-content-approved-durable-delivery-receipts.md`. Operator approval was communicated in this session on 2026-10-16; retention is indefinite compact proof and 90-day detailed Actions artifacts.

### Task DAG, scope and acceptance mapping

Execute sequentially T-275 → T-276 → T-277 → T-278 (phase 1), T-279 → T-280 → T-281 → T-282 → T-283 (phase 2), T-284 → T-285 → T-286 → T-287 (phase 3), T-288 → T-289 → T-290 (phase 4). All are pending; five-minute slices require further decomposition if implementation proves larger. Each named test script is future scoped acceptance, not currently available or passing.

Scope: `factory/receipt-trust.json`; `.claude/scripts/factory-receipts.py`, `factory-receipt-archive.py`, `factory-receipt-discovery.py`, `factory-git-state.py`, `factory-preflight.py`; the two existing reporting workflows; the sixteen `test/factory-receipt-*.sh` acceptance scripts listed in TASKS; `docs/FACTORY-DIGEST.md` and `docs/FACTORY-ADOPTER-SETUP.md`. Protect fixed new profile and archive-writer paths. Extend current data-only allowlist explicitly from README/reports to exact bounded archive object/index/discovery paths; never allow arbitrary executable paths. Existing state and encrypted feedback files survive every CAS unchanged.

AC mapping: AC-1 T-275/276/279; AC-2 T-278/283; AC-3/4 unchanged completed T-187 plus regression T-290; AC-5 T-277; AC-6 T-279/280/282/283; AC-7 T-284/285/286/287; AC-8 T-281/282/283/288/289/290. Final integration acceptance runs each constituent receipt test and existing guardian/recovery suites; it cannot mark earlier tasks done on declarations alone. Pending scripts must behaviorally cover malformed schemas, dependency omissions, revocation, real CAS conflict/restart, private fixture rejection and no runtime task mutation.

Public Git history cannot provide deletion guarantees; only approved public facts may be archived there indefinitely. Indefinite means no automatic compact-proof pruning. Detailed Actions retention remains 90 days. First unattended merge remains blocked until reviewed coverage bootstrap and actual retained-proof/CAS verification; profile metadata alone is insufficient. Live application of that bootstrap remains an operator activation gate, not permission to fabricate historical coverage.
