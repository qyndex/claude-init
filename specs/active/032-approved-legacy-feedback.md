---
id: 032
slug: approved-legacy-feedback
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
complexity: S
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Approved private legacy feedback migration

Authorized F-06 migration preserves original feedback and its customer metadata as untrusted data. Historical status cannot establish delivery or acceptance.

## Acceptance criteria

1. **AC-1**: Require protected operator approval of the full canonical manifest and each original source hash. Archive exact original bytes privately, retaining metadata, source path and approval; source files remain unchanged and replay is immutable.
2. **AC-2**: A separately approved promotion creates open source-bound feedback with original text, without fabricated digest/PR evidence or inherited shipped status. Existing approved amendment and delivery/acceptance contracts remain required; archive-only records can later be promoted with a new approved manifest.
3. **AC-3**: Prevalidate all sources before an atomic migration. Reject changed bytes, later invalid records and conflicting promoted sources without partial rows. Preserve earlier archive and feedback history.
4. **AC-4**: Reject disabled/foreign configuration or runtime namespace, duplicate/traversal/symlink sources and unsafe private modes. Restrict sources to explicit legacy feedback records. Expose counts/hash only; private customer data never enters public evidence. Live migration requires an actual operator-approved private manifest.
