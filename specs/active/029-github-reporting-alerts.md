---
id: 029
slug: github-reporting-alerts
status: approved
owner: "@codex"
created: 2029-10-10
updated: 2029-10-10
complexity: S
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# GitHub-only reporting alerts

Approved operator decision: use GitHub-only failure and overdue-digest alerts to the configured reporting Slack destination. Independent outage coverage is optional; Healthchecks stays disabled. No per-adopter identity is hardcoded.

## Acceptance criteria

1. **AC-1**: Detect missed 08:00 Sydney digest after configurable grace using protected checkpoint and exact remote delivery health. Persist alert journal before send, suppress a prolonged incident across repeats, preserve journal across actual hosted digest updates and send one recovery after current verified delivery.
2. **AC-2**: Preserve immutable alert intent and exact bot/metadata/text/receipt binding. Lost acknowledgement or checkpoint response is reconciled on fresh invocation; absent or altered history never triggers blind resend. A labelled manual verification drill is idempotent per GitHub run and never asserts a real outage.
3. **AC-3**: Validate actual failed run against configured repository, protected default branch and hosted reporting workflow; require completed failure/timed-out schedule/manual run. Disabled, foreign and invalid-clock inputs block. Repeated failure events do not duplicate incident notices.
4. **AC-4**: Versioned bounded data-only optional alert journal rejects unknown fields, invalid receipts, duplicate identities and unjustified recovery. Default-off main-only Actions workflow serializes with reporting, responds to completed reporting runs and polls overdue health without any monitoring provider. Local hosted/watchdog/reporting/policy and workflow regressions pass; live labelled drill, recovery and unchanged repeat are required before claiming notification activation.
