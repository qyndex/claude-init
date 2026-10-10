---
id: 026
slug: independent-reporting-watchdog
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Independent reporting watchdog contract

Authorized F-05 refinement: a status check inside the reporting scheduler cannot notice that the scheduler never ran. Provide a read-only probe and an opt-in verified-delivery heartbeat for an independently operated alert timer. No VM, vendor account or notification integration is silently provisioned.

## Acceptance criteria

1. **AC-1**: Read the protected typed Git checkpoint without state writes and verify the latest confirmed report's exact Slack text/fragment or file receipt. Actual hosted fixtures prove both text and oversized file health with no extra post, allocation or checkpoint mutation.
2. **AC-2**: Derive expected 08:00 Australia/Sydney cutoff with DST and a bounded configurable grace period. Distinguish current, grace and missed status; missed delivery becomes nonzero health. Missing state, disabled/foreign configuration, naive/future clocks, weakened protection or unavailable/altered latest receipts never become healthy proof.
3. **AC-3**: Standalone probe supports an external scheduler with read-only Git state and Slack history/file access. The protected main-only hosted workflow can opt into heartbeat mode after successful delivery. Missing configuration, missed/grace delivery, or unverified receipt cannot signal heartbeat success. External provider account/timer/notification and a live missed-signal drill remain explicit activation requirements.
4. **AC-4**: Return bounded non-sensitive status fields and exit 0 for current/grace, 1 for missed, 2 for blocked. Heartbeat sends an empty POST only to a configured canonical HTTPS hc-ping.com UUID endpoint, with no query/userinfo/redirects, report data or bot/GitHub credentials. Require exact documented acknowledgement and suppress secret URLs/provider response bodies on failure. Local endpoint/negative and reporting regressions plus structural checks pass.
