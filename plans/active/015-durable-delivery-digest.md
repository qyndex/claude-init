---
id: 015
slug: durable-delivery-digest
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
spec: specs/active/015-durable-delivery-digest.md
---

# Digest core implementation

Add a separate reusable reporting adapter rather than infer historical merge facts from the legacy daily briefing. Hold a SQLite write transaction during collection/prepare, persist canonical report bytes, and serialize delivery with an OS lock. Trusted transport supplies send and authoritative stable-key lookup. A crash after recording uncertainty requires lookup before retry. Protected repository configuration supplies start time and destination; qyndex account settings are not installer defaults.

Tests use a real SQLite database, paginated GitHub-shaped responses and disposable remote transport fixtures. A live Slack adapter and actual scheduled delivery remain pending; the core CLI prepares reports only.
