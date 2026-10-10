---
id: 021
slug: hosted-reporting-checkpoints
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
complexity: L
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# GitHub-hosted reporting with branch checkpoints

Operator selected hosted Actions and the public claude-init repository itself for this pilot's state. Each adopter owns its reporting configuration/store. Replace the pilot's persistent-host dependency with data-only Git state while leaving both delivery profiles disabled until live identity/configuration drills pass.

## Acceptance criteria

1. **AC-1**: Typed JSON checkpoints contain only digest cursors, immutable origins, batches and receipts. Reject foreign identity/schema, unknown fields/tables, default-branch state, incomplete tree/blob integrity, and state branches without active no-bypass rewrite/deletion protection. Private source repositories cannot publish public state. Missing state may bootstrap only at an explicit exact empty branch revision; later absence never resets the cursor.
2. **AC-2**: Checkpoints use immutable blob/tree/commit objects and non-force reference updates from the observed parent. Unique commit nonces prevent identical concurrent writers sharing one successful reference update. A stale or failed writer is fenced before send and requires a fresh authoritative restore; no automatic rebase/overwrite occurs.
3. **AC-3**: Uncertain state is durably checkpointed before a Slack send; confirmed receipt/cursor is durable before acknowledging success. Fresh temporary runners restore typed state and reconcile lost Slack or storage acknowledgements without duplicate sends. Storage outages prevent send/advance. Local unrelated tables never enter public snapshots.
4. **AC-4**: A disabled trusted-default-branch hosted workflow uses a protected reporting environment, exact source SHA and isolated temporary projection, with no merge App key or candidate event. Explicit mutually exclusive profile guards prevent simultaneous hosted/self-hosted delivery. Fixtures, actionlint and digest/Slack/coverage regressions pass; documentation names per-adopter setup, public data boundary and remaining live prerequisites.
