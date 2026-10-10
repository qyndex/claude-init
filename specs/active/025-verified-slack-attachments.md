---
id: 025
slug: verified-slack-attachments
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Verified oversized report attachments

Authorized F-05 refinement: deliver complete reports above the 35,000-character message bound through an explicitly enabled Slack file adapter. Preserve the existing durable uncertain-send and exact readback contract; never truncate or infer successful delivery from upload completion.

## Acceptance criteria

1. **AC-1**: Actual hosted fixtures deliver a report above 35,000 characters with every PR retained in UTF-8 file bytes, bounded to 1,000,000 bytes. File receipts bind the immutable payload hash, unique filename/key, file ID, channel share timestamp and text hash. Read back exact bytes before confirming; fresh-disk repeats leave cursor/checkpoint unchanged.
2. **AC-2**: Require expected workspace/bot user, hosted non-external file, exact filename/size/uploader and intended channel/team/timestamp share. Reject altered bytes, foreign senders/channels, public URL sharing, ambiguous or multiple shares and missing history. File completion alone never proves delivery.
3. **AC-3**: Enable file delivery only with a boolean protected per-repository setting; absent/false keeps the normal adapter and oversized reports block before allocation. Use paginated history for recovery after lost completion responses on fresh disks. Inaccessible or absent history remains uncertain with no repeated allocation/upload/share; unshared partial uploads require operator reconciliation.
4. **AC-4**: Verify documented modern upload methods, API success envelopes and GET/POST semantics. Upload only to HTTPS files.slack.com/upload URLs without sending bot authorization; authenticated downloads bind the workspace/file path on that host. Reject redirects/foreign hosts, oversize bytes and malformed responses without logging credentials. Both reporting profiles expose disabled-by-default configuration. Existing hosted, receipt projection, Slack/digest, reporting preflight, feedback and structural regressions pass. Live scopes and actual channel file proof remain separate activation inputs.
