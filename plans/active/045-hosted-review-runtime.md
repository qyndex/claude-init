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


## Operator-selected reviewer update — 2026-10-14

The operator explicitly requested Claude Sonnet 5.5 and confirmed the Claude Max subscription is active. T-273 pins the local reviewer agent, the three hosted review paths and protected producer invocation/modelUsage validation to `claude-sonnet-5-5`. Other local agent roles retain their existing selection. The constitution and root routing mirror must agree on the reviewer family; current operational producer documentation must state the exact pin. Historical approvals, receipts and preparation logs remain unchanged.

Acceptance tests use actual bounded fake reviewer subprocesses and strict negative model results: old, foreign, mixed, missing or invalid usage cannot produce a successful reviewer verdict. Protected source pins must be refreshed from the actual merged runtime revision before shadow activation. A successful local subscription probe is capacity/model evidence, not an independent hosted verdict or merge-mode approval. No merge authority or production deployment is activated by this configuration change.

The official model identifier is documented at https://platform.claude.com/docs/en/models/sonnet-5-5/overview . The existing bounded live probe returned available=true for that exact model on Claude Max with CLI2.1.299; reported client estimates remain distinct from subscription spend. Existing AC-1/AC-2 subprocess isolation and OAuth-only protected pilot behavior remain unchanged.

The architecture agent table must mirror the explicit reviewer model. The documentation consistency parser currently only recognizes major version4 rows; T-273 extends that parser so major5 reviewer rows participate in drift detection. A fixture must prove both a matching5.5 routing pair and rejection of a conflicting5.5 pair while retaining other4.x rows, preventing an empty-map false pass.

The /review skill also declares an Opus model override today. T-273 updates that invocation to the same explicit Sonnet5.5 pin, preserving the separately assigned security agent and other local roles. Acceptance checks both the reviewer definition and actual review skill selection.
