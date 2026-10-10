---
id: 023
slug: slack-split-receipts
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Exact Slack split receipt recovery

Refinement of the authorized F-05 pilot: the actual 6,007-character catch-up post appeared as two messages, while the API response/history adapter expected one. Preserve complete report coverage, immutable payload identity and durable uncertainty; never resend to work around a split response.

## Acceptance criteria

1. **AC-1**: A receipt certifies only the complete expected report reconstructed from 1–10 authenticated fragments. Every fragment binds the same bot, exact metadata/key/payload hash, nonempty text and numeric timestamp. Multi-fragment receipts retain all ordered message IDs in a versioned canonical JSON string within the existing opaque message_id field; single-message receipts remain compatible.
2. **AC-2**: Read all history pages and sort fragments by exact decimal timestamps. Reject duplicate timestamps, duplicates/overlaps, missing/extra/changed pieces, foreign senders, changed metadata and fragments spanning more than 60 seconds. Only exact concatenation or a preserved/dropped newline at fragment boundaries and the existing exact URL round-trip rules may reconcile text; labels/targets/content outside those rules remain invalid.
3. **AC-3**: A partial successful post response cannot confirm delivery alone. Read complete history; absent/incomplete history preserves uncertainty and prevents another send. Fixtures exercise the actual Slack binding and hosted runner, paginated reverse-order history and complete receipt readback.
4. **AC-4**: Actual hosted checkpoint fixtures cover response loss, unavailable history, fresh runner disks and repeat runs. Confirm only after full recovery; repeated invocation leaves the checkpoint/cursor unchanged and post count at one. Existing digest/Slack/policy/feedback regressions and structural validation pass; docs retain honest missing evidence and the 35,000-character bound. Live private-channel recovery and repeat proof remain necessary before activation is claimed.
