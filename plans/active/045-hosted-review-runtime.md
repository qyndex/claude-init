---
id: 045
slug: hosted-review-runtime
status: approved
owner: "@codex"
created: 2026-10-11
updated: 2026-10-11
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
spec: specs/active/045-hosted-review-runtime.md
---

# Hosted reviewer readiness

T-219 extends the shared bounded subprocess reader with file-backed stdin, preserves its existing default bounds, and uses it for tool-free hosted review. Review validates actual modelUsage before publishing a verdict. Fixed neutral environment and separate fresh CLI flags prevent inherited local sessions and runtime overrides. The pilot workflow pins OAuth; generic explicit API invocation remains available to separately configured adopters without fallback. Add helper to authenticated transitive runtime pins. Test actual local subprocess flood, timeout and prompt transfer alongside fake structured reviewer results; no Claude request, live deployment or merge authority activation.
