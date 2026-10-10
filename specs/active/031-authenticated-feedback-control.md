---
id: 031
slug: authenticated-feedback-control
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
complexity: S
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Authenticated feedback approval and acceptance

Authorized F-06 scope: preserve operator decisions as authenticated source events and route approved feedback through the full specification chain. Candidate text cannot mint approval.

## Acceptance criteria

1. **AC-1**: Authenticate allowlisted Slack commands against protected workspace and private runtime namespace. Approve only an exact canonical amendment hash and requested version with independently protected approved spec/task bindings; preserve immutable command sources and idempotent replay. Capture and control pollers coexist.
2. **AC-2**: Explicit acceptance names the exact amendment version and requires full matching delivery provenance. Local merged markers or partial proof cannot accept a feature. Repeated acceptance retains the original event even after audit events.
3. **AC-3**: Persist command intent before transitions and recover after a committed amendment loses its confirmation without another version. Enforce expected version inside the core transaction so stale/conflicting approvals cannot commit another version.
4. **AC-4**: Reject edited commands, stale acceptance, missing/changed proposals, disabled or foreign runtime/configuration and conflicting source identities. Preserve private original feedback and unchanged implementation/review/merge gates; live operator control remains disabled until private principal and protected operator configuration exist.
