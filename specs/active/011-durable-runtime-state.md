---
id: 011
slug: durable-runtime-state
status: approved
owner: "@codex"
human_owner: "@operator"
created: 2026-10-10
updated: 2026-10-10
complexity: L
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Durable local runtime state

Authorized by the operator's instruction to continue the approved factory plan. This is the transactional foundation of F-04; worker supervision and migration of existing shared writers remain separate integration work. tasks/TASKS.md remains product task authority.

## Acceptance criteria

1. **AC-1**: Concurrent processes claiming the same queued task yield one owner. Claims retain approved revision and dependencies, block unfinished dependencies, and monotonically fence expired owners.
2. **AC-2**: Heartbeats and legal state transitions require a matching unexpired owner/token. Expired claims recover after process restart; paused execution rejects new claims, cancelled tasks reject stale workers, and retries are bounded.
3. **AC-3**: External actions enter a durable idempotent outbox atomically with the worker transition. A crash or lease expiry after dispatch yields an uncertain action requiring reconciliation, never automatic duplicate execution. Reconciled outcomes and merge receipts survive restart.
4. **AC-4**: Invalid revisions, dependencies, state transitions, action keys and conflicting receipts fail without partial writes. Runtime state does not edit the task ledger or claim unattended factory activation.
