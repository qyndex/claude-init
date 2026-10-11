---
id: 041
slug: private-worker-artifacts
status: approved
owner: "@codex"
created: 2026-10-11
updated: 2026-10-11
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Bounded private worker artifacts

Authorized F-07 privacy/retention scope. Raw worker/model output belongs only in private controller storage. Runtime counts do not establish independent verification or authenticated delivery.

## Acceptance criteria

1. **AC-1**: Bound trusted subprocess stdout/stderr during streaming reads and terminate owned process groups on overflow/timeout. Git inventory, routing probes, native CLI observations and Docker acknowledgements use bounded collection; partial/oversized observations cannot establish readiness or cleanup.
2. **AC-2**: Guardian-owned collection caps worker logs, preserves liveness/timeout cleanup and requires complete EOF before success. Actual flooding and descendant-held output cannot advance to verification; normal complete output remains compatible and private.
3. **AC-3**: Protected owner-only canonical artifact policy/storage yields only sanitized aggregate runtime counts. Foreign/unbound stores, unsafe paths and arbitrary raw output cannot be exported. Metrics explicitly do not certify engineering delivery.
4. **AC-4**: Retention defaults to dry-run and deletes only expired terminal attempt namespaces with exact metadata, confirmed cleanup, released task locks and no unresolved external effects/actions. Preserve active/uncertain/unknown/symlink/hardlink state and SQLite receipts. Actual filesystem, recovery, routing and Linux container regressions pass.
