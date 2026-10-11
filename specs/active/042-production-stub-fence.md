---
id: 042
slug: production-stub-fence
status: approved
owner: "@codex"
created: 2026-10-11
updated: 2026-10-11
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Fence placeholder production releases

Authorized F-08 first slice: a template workflow must not certify placeholder deployment. Real adapters and isolated rollout/rollback drills follow separately; no repository-specific target is required to build these contracts.

## Acceptance criteria

1. **AC-1**: The shipped canary stub fails immediately with DEPLOY_WIRED unset, false or true. It cannot allocate a GitHub Deployment, wait through placeholder ramps or publish success.
2. **AC-2**: The disabled workflow has read-only permissions and no deployment credential, platform invocation or success publication. Execute its actual shell body with fake external commands and prove zero effects for every flag state.
3. **AC-3**: Adopter documentation defines authenticated delivery, protected pinned adapters, durable intent before effects, service-bound SLO measurements, staged promotion, verified known-good rollback and uncertain-effect reconciliation. Distinguish these required contracts from implemented capability and leave production disabled pending real target proof.
