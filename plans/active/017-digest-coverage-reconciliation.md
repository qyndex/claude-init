---
id: 017
slug: digest-coverage-reconciliation
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
spec: specs/active/017-digest-coverage-reconciliation.md
---

# Coverage reconciliation plan

Add an immutable stream origin to the existing SQLite core. Backfill from the earliest report's from boundary, or initial cursor for a stream with no report. Read confirmed report payloads to build a PR/merge identity set inside the prepare transaction. Scan all paginated merged PRs within origin/cutoff, exclude reported identities and mark unreported merges older than or equal to the current cursor as late discoveries. Reject contradictions rather than silently rewrite coverage. Keep report bytes, uncertainty and cursor confirmation unchanged.

Exercise migration and late-discovery fixtures with disposable SQLite and transports. The eventual coverage guarantee requires merges to remain visible in a later complete GitHub API scan; outage/retention failures stay blockers.
