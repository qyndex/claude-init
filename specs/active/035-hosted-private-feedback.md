---
id: 035
slug: hosted-private-feedback
status: approved
owner: "@codex"
created: 2026-10-11
updated: 2026-10-11
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Authenticated encrypted hosted feedback intake

Authorized F-06 scope connects approved encrypted-state architecture to authenticated Slack intake. No amendment or merge is self-approved.

## Acceptance criteria

1. **AC-1**: Capture allowlisted authenticated feedback against exact confirmed Slack digest receipts, commit only encrypted SQLite, preserve public reporting state and start feedback open without tasks or approval.
2. **AC-2**: Lost Git acknowledgement recovers from authoritative ciphertext without duplicate feedback, Slack sends or unchanged checkpoint churn.
3. **AC-3**: Disabled intake, wrong keys, missing exact remote receipts and invalid allowlists fail without publishing partial observations. The main-only workflow passes secrets only to trusted intake, publishes no private artifacts and defaults disabled.
4. **AC-4**: Actual Git compare-and-swap fences stale encrypted writers. Creating a sidecar alongside reporting requires an exact protected bootstrap SHA; later missing state cannot silently reset. Both workflows share serialized concurrency.
