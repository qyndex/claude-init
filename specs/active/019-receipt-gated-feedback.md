---
id: 019
slug: receipt-gated-feedback
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
complexity: L
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Receipt-gated operator feedback core

Implement F-06 behind the trusted local operator boundary. Preserve the signal and source delivered report; version amendments before implementation. Existing markdown feedback remains a historical registry, never merge authority. Live Slack intake authentication and projection adapters follow this core.

## Acceptance criteria

1. **AC-1**: Intake preserves exact operator text, reporter, classification, source reference and delivered digest/PR identity. Undelivered/foreign/unlisted source features and conflicting replay reject; identical source replay is idempotent.
2. **AC-2**: Versioned amendments require impact analysis, protected approval of the entire amendment digest, and immutable task/spec revision mapping. Superseded pending work is blocked and fenced atomically; dispatched effects become uncertain and blocked tasks cannot dispatch new external effects. Completed delivery history is retained.
3. **AC-3**: Delivery requires every current amendment task to be merged with matching authenticated receipt/provenance. Partial multi-spec delivery, local markers or older amendment deliveries cannot close feedback. Explicit sourced operator acceptance remains a separate idempotent state/event.
4. **AC-4**: The legacy post-ship entry point cannot mark markdown shipped or move records based on a local spec marker; without configured trusted state it fails visibly. Regression fixtures prove intake replay, approval, fencing, partial/all receipts, version changes and acceptance history; runtime/digest/receipt regressions pass.
