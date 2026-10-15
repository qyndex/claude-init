---
id: 045
slug: hosted-review-runtime
status: shipped
owner: "@codex"
created: 2026-10-11
updated: 2026-10-15
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Bound and authenticate hosted reviewer execution

Authorized remaining protected reviewer readiness. Keep live Claude review paused until Tuesday; no model calls or authority activation in this change.

## Acceptance criteria

1. **AC-1**: Reviewer subprocess reads a bounded prompt from private file-backed stdin, streams bounded stdout/stderr and terminates its owned process group on timeout or excess output, without invoking a live model in acceptance tests.
2. **AC-2**: Hosted reviewer runs in a fresh neutral HOME/config/TMPDIR with scoped CLI flags, no session persistence or inherited GitHub/authority/provider override credentials. The pilot workflow selects subscription OAuth explicitly and has no API credential fallback.
3. **AC-3**: Review succeeds only with a successful structured result reporting the exact protected model and valid bounded usage. Missing/foreign models, invalid token counts, nonfinite costs, errors and PASS with unresolved findings are rejected.
4. **AC-4**: Trusted runtime pins include the bounded helper dependency; existing producer acceptance and full workflow lint pass. Documentation records Tuesday review deferral and distinguishes fixture proof from live independent review.
