---
id: 043
slug: protected-production-core
status: approved
owner: "@codex"
created: 2026-10-11
updated: 2026-10-11
complexity: M
objective: KR-PLATFORM
service_tier: T2
spec: specs/active/043-protected-production-core.md
---

# Reusable release and recovery

T-217 adds a protected platform-neutral core using pinned subprocess adapters and private durable SQLite. Authenticated coordinator receipt is the only CLI proof source. Real loopback HTTP fixtures model progressive routing and a failing version, lost acknowledgements and rollback restoration; synthetic core receipts are explicitly not live GitHub attestations. Durable backend and real platform proof remain each adopter's activation prerequisites. Do not wire an ephemeral hosted job as a durable release controller.
