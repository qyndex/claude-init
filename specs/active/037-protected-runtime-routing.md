---
id: 037
slug: protected-runtime-routing
status: approved
owner: "@codex"
created: 2026-10-11
updated: 2026-10-11
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Protected runtime routing

Implement authorized F-02/F-04 routing and private state boundaries. Subscription use remains explicit; capacity and client estimates do not substitute for engineering proof.

## Acceptance criteria

1. **AC-1**: A private protected profile pins executable/probe hashes, full model IDs, native authentication metadata and required role capabilities. Bounded real subprocess probes select only configured equivalent fallbacks, forward dedicated role credentials and never grant independent verification authority.
2. **AC-2**: A routed foreground worker persists private model/token observations and conversation-scoped client estimates, keeps actual subscription spend unknown and advances only to verifying. Approved ledger policy binds profile hash, repository and task role and forbids caller command bypasses.
3. **AC-3**: Exhausted or unavailable capacity records a durable blocker and starts no worker or task attempt; explicit reset metadata is preserved without inventing quota. Foreign runtime namespaces fail before probing. Private encrypted checkpoint SQLite handles close before publication and temporary cleanup.
4. **AC-4**: Unsupported stacks/extensions, absent capabilities, wrong authority location, unsafe private modes, profile/role overrides and changed executable pins block. Candidate fsmonitor hooks never execute during metadata inspection. Ledger, supervisor and encrypted-feedback regressions pass; live model capacity and OS isolation remain explicit unproven rollout gates.
