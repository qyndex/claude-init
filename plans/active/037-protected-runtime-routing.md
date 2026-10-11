---
id: 037
slug: protected-runtime-routing
status: approved
owner: "@codex"
created: 2026-10-11
updated: 2026-10-11
complexity: M
objective: KR-PLATFORM
service_tier: T2
spec: specs/active/037-protected-runtime-routing.md
---

# Routing implementation plan

T-211 introduces protected role/model routing, a bounded native subscription probe and an approved-ledger entry point. Pin trusted controller/probe/runtime files outside implementation authority, validate detected stacks and reject implicit provider fallback. Persist capacity decisions separately from worker outcomes; report client estimates as conversation scoped and actual spend as unknown. Prove dedicated role credential forwarding and rejection through real CLI fixtures. Close private SQLite connections explicitly rather than relying on context-manager transaction semantics. Refresh specs 013 and 034 evidence. This does not activate native workers, independent review, live feedback intake or automatic merge authority; isolated worker execution and real capacity are subsequent gates.
