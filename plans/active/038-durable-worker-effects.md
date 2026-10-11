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
spec: specs/active/038-durable-worker-effects.md
---

# External-effect fencing plan

T-212 adds transactional worker-effect intent and cleanup observations to the private runtime store. Gate claim, verification/delivery transitions and requeue on absence of unresolved effects. Permit a trusted cleanup adapter to reconcile exact prior effects after blocked/cancelled recovery without reviving a task. Preserve immutable repository/namespace/fence provenance and prove concurrent reclaim. Refresh spec 011 runtime acceptance evidence. Subsequent spec 039 integrates real offline Linux containers and daemon reconciliation; no production or native-agent isolation is claimed by this store contract.
