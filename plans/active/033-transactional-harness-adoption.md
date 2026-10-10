---
id: 033
slug: transactional-harness-adoption
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
complexity: M
objective: KR-PLATFORM
service_tier: T2
spec: specs/active/033-transactional-harness-adoption.md
---

# Versioned ownership and recovery plan

T-207: replace eval/overwrite reconciliation with a Python adapter behind the existing shell entry point. Preflight every tracked managed path and prior ownership fingerprint before writes. Keep source code/template ownership distinct from seeded project ledgers. Journal exact before/after state privately outside the repository; use atomic replacement, guarded rollback/recovery and an OS target lock. Installer invokes pinned source local prerequisite checks instead of target setup; external activation remains separate. Update old installer fixture to actual reconciliation and verify every required source/root/boolean guard. Update adoption guidance and fail missing-gate handoff. Merge with fresh spec 020 and 033 bundles; per-adopter capabilities/routing and privacy follow next.
