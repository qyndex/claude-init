---
id: 014
slug: authenticated-receipt-recovery
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

# Authenticated delivery receipts and abrupt-death recovery

Authorized continuation of F-04. Protected receipt ingestion is read-only against GitHub and updates local runtime projections. Live activation and real independently reviewed delivery remain separate readiness gates.

## Acceptance criteria

1. **AC-1**: Ingest only digest-verified receipt artifacts from successful, approved default-branch coordinator workflow runs and pinned transitive source revisions. Reject foreign repository/workflow/event/branch, missing pins, failed runs, expired/ambiguous/tampered archives and malformed receipts.
2. **AC-2**: Require a merged GitHub PR with matching repository, approved spec/task mapping, exact head, target branch and merge SHA. Source-run policy/spec bytes must match the receipt and current approved task revision. Preserve immutable authenticated provenance; conflicting/replayed receipts cannot change another delivery or partially complete tasks.
3. **AC-3**: A separate guardian detects supervisor death through an inherited liveness pipe, terminates the actual worker group including descendants, then fences and requeues that attempt with bounded retries. Interrupted external actions become uncertain. A stale guardian cannot alter a newer or cancelled claim.
4. **AC-4**: SIGKILL drills prove guardian cleanup, no duplicate live worker, retained interruption outcomes and successful fenced retry. Existing cancellation, timeout, detached startup and live resource fixtures continue passing. No local outcome can claim engineering verification or merge authority.
