---
id: 036
slug: worker-environment-boundary
status: approved
owner: "@codex"
created: 2026-10-11
updated: 2026-10-11
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Implementation worker environment boundary

Authorized F-04/F-07 credential isolation prevents accidental inheritance of coordinator authority. This is a necessary boundary, not proof of same-user filesystem isolation.

## Acceptance criteria

1. **AC-1**: Build worker environment from an explicit ordinary runtime allowlist; drop GitHub/App/Slack/encryption/cloud/provider credentials, proxies and interpreter/loader injection. Unknown environment variables are not inherited.
2. **AC-2**: Only explicitly dedicated implementation subscription credentials map into worker Claude OAuth. A real supervised worker through the guardian receives its assigned namespace and no coordinator credentials; success advances only to verifying.
3. **AC-3**: If no dedicated implementation credential is supplied, do not borrow existing coordinator/reviewer OAuth or API keys. Actual worker runs remain bounded and never claim engineering/merge authority.
4. **AC-4**: Real timeout cleanup and lease fencing remain intact; supervisor, receipt/guardian and ledger/resource regressions pass. Guides retain native same-user filesystem isolation as an unproven gate and do not enable autonomous workers/merge authority.
