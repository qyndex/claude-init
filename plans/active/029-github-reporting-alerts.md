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
spec: specs/active/029-github-reporting-alerts.md
---

# GitHub-only alert implementation plan

T-203: extend protected report JSON with a strict optional alert journal, retaining backward-compatible old checkpoints and preserving journal on every hosted digest snapshot. Add exact Slack alert reconciliation, durable pre-send intents, prolonged-incident deduplication and verified recovery. Validate failed GitHub runs independently of event payload. Add a protected default-off scheduled/workflow-run/manual workflow and a labelled notification drill. Prove uncertainty, storage failures and malicious input; merge only after required exact-head gates. Enable monitor and verify drill/recovery/repeat with unchanged digest cursor. Keep the third-party heartbeat explicitly disabled. GitHub/Slack shared outages remain documented limits.
