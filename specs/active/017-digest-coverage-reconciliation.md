---
id: 017
slug: digest-coverage-reconciliation
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
complexity: L
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Digest coverage reconciliation

Continue F-05 after the Slack runner. Reconcile unreported actual merged PR identities across the configured reporting origin, including merges discovered after their original cursor interval. Keep cursor/delivery rules unchanged and live activation separate.

## Acceptance criteria

1. **AC-1**: Persist the immutable initial reporting origin and derive reported PR/merge identities only from confirmed report batches. A later prepare scans paginated target-branch merges back to that origin; unreported older merges appear with an explicit late-discovery marker.
2. **AC-2**: Already-confirmed PRs never repeat in later coverage. Failed/pending/uncertain reports do not reserve coverage as delivered. Contradictory merge identities and malformed prior reports block preparation without changing the cursor or pending batch.
3. **AC-3**: Existing databases migrate origin from the earliest persisted batch or current initial cursor. Changing CLI start cannot expand/reset an established stream. Merges before the configured origin remain outside coverage; every eligible late merge is included even at a previously delivered equal-time cutoff.
4. **AC-4**: Fixtures prove delayed discovery after delivery, failed-send recovery, equal-time catch-up, immutable-origin migration and no duplicate reports. Digest and Slack runner regressions pass; Slack output labels late discoveries explicitly. No live activation is claimed.
