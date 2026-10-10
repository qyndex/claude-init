---
id: 016
slug: slack-digest-runner
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
spec: specs/active/016-slack-digest-runner.md
---

# Slack runner plan

Keep credentials outside the repository and read them only in the real HTTP client. Authenticate workspace and bot with auth.test. Send plain escaped digest text plus non-sensitive key/hash metadata; reconcile paginated channel history by sender, metadata and exact rendered text. Never claim absence from history. Validate response identity and remote text before confirming delivery.

A local cron/service may invoke the runner periodically; Sydney due-time selection handles DST and missed days. Add status-only watchdog and a disabled generic configuration template. Do not install schedules or send to an unconfigured account. Live activation can follow once the operator supplies non-secret IDs and a securely stored credential.
