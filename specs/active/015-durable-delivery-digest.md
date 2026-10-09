---
id: 015
slug: durable-delivery-digest
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
complexity: L
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Durable delivery digest core

Authorized F-05 continuation. Prepare reports from paginated actual merged PRs and authenticated local provenance. Exercise delivery through a trusted adapter contract using disposable fixtures; live Slack transport and scheduling are separate activation work.

## Acceptance criteria

1. **AC-1**: Collect every target-branch merge in the cursor interval, including more than 50 and equal-time merges. Map tasks/specs only from matching authenticated delivery provenance; label missing evidence and never infer historical CI status from current checks or globally completed tasks.
2. **AC-2**: Preserve the cursor on collection or delivery outage. Persist immutable report bytes and one stable delivery key per interval/destination. Advance the cursor only with a matching remote message receipt; empty intervals remain explicit reports.
3. **AC-3**: Serialize delivery, persist uncertainty before external effects, and reconcile ambiguous sends by stable key. Never blindly resend an uncertain effect; require authoritative absence before permitting retry. Reject mismatched/conflicting remote receipts and exclude duplicate concurrent sends.
4. **AC-4**: Display Australia/Sydney times with DST-aware 08:00 cutoff calculation. Fixtures prove DST transitions, paginated catch-up, equal-time coverage, missing proof, failed collection, uncertain remote success, authoritative absence and concurrent delivery. No live Slack delivery or factory activation is claimed.
