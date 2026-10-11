---
id: 038
slug: durable-worker-effects
status: approved
owner: "@codex"
created: 2026-10-11
updated: 2026-10-11
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Durable external worker effects

Authorized F-04 prerequisite for isolated container workers. Killing a local Docker client does not establish that the daemon stopped its container. Persist intent before dispatch and retain uncertainty until the trusted adapter observes cleanup.

## Acceptance criteria

1. **AC-1**: Persist immutable, idempotent external effect identity before dispatch, bound to current task owner/fence and repository namespace. Reject altered IDs, foreign namespaces and stale owners without partial updates.
2. **AC-2**: Unresolved external effects prohibit expired-lease reclaim, transition to verification/delivery and guardian requeue. Unknown cleanup can block a task while retaining its unresolved effect; native tasks without external effects preserve existing behavior.
3. **AC-3**: Only an exact typed adapter/identity absence observation releases the external-effect fence. Confirmations are idempotent, concurrent reclaim yields one owner, and old owners cannot dispatch after reclaim. This local trusted-adapter observation never constitutes independent engineering proof.
4. **AC-4**: Effects survive store reopen and failed recovery, can be reconciled after cancellation/blocking without restoring task authority, and do not block unrelated tasks. Runtime, ledger, supervisor, abrupt-death receipt recovery and encrypted hosted-feedback regressions pass. Actual container/daemon cleanup is the next adapter spec and remains unproven here.
