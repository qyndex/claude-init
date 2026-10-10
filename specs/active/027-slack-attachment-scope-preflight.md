---
id: 027
slug: slack-attachment-scope-preflight
status: approved
owner: "@codex"
created: 2027-10-10
updated: 2027-10-10
complexity: S
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Granted file scope preflight

Authorized F-05 activation refinement: verify grants on the installed bot before opting into file delivery. OAuth reinstall acknowledgement is not an upload receipt.

## Acceptance criteria

1. **AC-1**: Read authenticated auth.test x-oauth-scopes using the inherited attachment HTTP client without uploads, posts or token logging.
2. **AC-2**: Missing, partial and similar-name file grants fail closed; require exact files:read and files:write.
3. **AC-3**: Successful reauthentication replaces stale grants and authentication failures block preflight.
4. **AC-4**: Protected hosted workflow checks file grants only when attachments are enabled; legacy reporting remains usable without file permissions. Local scope, attachment, Slack and hosted regressions pass; live upload receipt remains separate.
