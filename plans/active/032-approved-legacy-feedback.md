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
spec: specs/active/032-approved-legacy-feedback.md
---

# Legacy feedback migration plan

T-206: read explicitly allowlisted original feedback files as immutable bytes; require full-manifest protected approval and source hashes. Commit archive and optional open feedback promotion atomically in the isolated coordinator store. Never parse historical YAML into authority, inherit status, modify sources or invent delivery. Distinct approved manifests retain earlier archives; promoted source identity remains immutable. Verify source tamper, batch failure, promotion conflicts and filesystem boundaries, then merge through all required checks. No actual customer records are imported during implementation.
