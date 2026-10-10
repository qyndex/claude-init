---
id: 016
slug: slack-digest-runner
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
complexity: L
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Slack digest transport and morning runner

Authorized continuation of F-05. Build reusable Slack transport, due-time runner and missed-delivery status. Actual account activation requires the protected Slack channel/team IDs and runtime credential; tokens never enter repository files or chat.

## Acceptance criteria

1. **AC-1**: Slack requests use documented methods, check response success, validate workspace/bot/channel identity, and bind message metadata to stable digest key and exact payload hash. Errors/timeouts preserve uncertainty; no secret appears in output or fixtures.
2. **AC-2**: Paginated lookup authenticates the bot sender and exact report text/metadata. Wrong sender, changed text, conflicting metadata, multiple complete matching reports and incomplete pagination cannot certify delivery. Missing history never proves authoritative absence or permits automatic resend.
3. **AC-3**: Render every merge in a bounded single Slack post (which Slack may return as multiple authenticated fragments under spec 023) with evidence/task/spec links or explicit missing proof; escape untrusted titles/mentions and disable automatic formatting/unfurls. Oversized reports block without truncating PR coverage.
4. **AC-4**: A protected-config runner selects the latest due 08:00 Sydney cutoff, catches up from durable state, retries pending/uncertain delivery through the core and reports missed intervals through a read-only watchdog. Disabled/missing configuration blocks send. Fixtures cover DST, early invocation, missed delivery, remote ambiguity and existing digest regression.
