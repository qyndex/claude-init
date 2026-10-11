---
id: 039
slug: offline-worker-containers
status: approved
owner: "@codex"
created: 2026-10-11
updated: 2026-10-11
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Offline Linux worker containers

Authorized F-04 implementation following durable external-effect fencing. Use protected immutable Docker binary/image configuration and one candidate mount. This offline adapter does not provide provider networking or prove native Claude subscription availability.

## Acceptance criteria

1. **AC-1**: Validate protected bounded execution configuration and generate nonroot, read-only, capability-dropped, network-disabled containers with only the candidate mount. Exclude coordinator secrets, private runtime/attempt state, host HOME, sockets and hardlinks.
2. **AC-2**: Record immutable external intent before dispatch and actual container identity before start. Refuse foreign resources, unknown creation acknowledgements and unavailable cleanup; unresolved effects retain the retry/verification fence.
3. **AC-3**: Reconcile exact persisted daemon identities after guardian failure, cancellation or blocking without reviving task authority. Native execution and approved ledger/resource contracts remain compatible.
4. **AC-4**: Run an actual nonroot Linux Docker drill proving private-file/environment/process/network isolation, concurrent workers using the same internal port, timeout cleanup and parent-death cleanup/retry. CI records exact source SHA, pinned image/binary and explicit non-independent proof. Missing Docker must fail the enabled drill; local skipped drills provide no isolation evidence.
