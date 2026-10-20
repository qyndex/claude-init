---
id: 033
slug: transactional-harness-adoption
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-21
complexity: M
objective: KR-PLATFORM
service_tier: T2
spec: specs/active/033-transactional-harness-adoption.md
---

# Versioned ownership and recovery plan

T-207: replace eval/overwrite reconciliation with a Python adapter behind the existing shell entry point. Preflight every tracked managed path and prior ownership fingerprint before writes. Keep source code/template ownership distinct from seeded project ledgers. Journal exact before/after state privately outside the repository; use atomic replacement, guarded rollback/recovery and an OS target lock. Installer invokes pinned source local prerequisite checks instead of target setup; external activation remains separate. Update old installer fixture to actual reconciliation and verify every required source/root/boolean guard. Update adoption guidance and fail missing-gate handoff. Merge with fresh spec 020 and 033 bundles; per-adopter capabilities/routing and privacy follow next.

## Approved keep-local continuation — 2026-10-21

T-349 adds only explicit upgrade resolutions for the three project-facing configuration paths in Spec033 AC-5/6. First retain real rejecting tests against the current installer. Reuse its source packaging, path validation, ownership fingerprints, target lock, atomic writes and private journal; add versioned local-override metadata and exact resolution-plan/hash binding. Existing v1 behavior remains strict by default. A resolution transfers selected configuration to project ownership without changing its bytes/modes or permitting executable/process ownership release. Preserve reviewed upstream fingerprints and require renewal when they change. Protect transferred files with transaction guards so recovery never overwrites later local changes. Test both actual adopter override shapes in temporary repositories, schema compatibility, stale/unsafe inputs, rollback/idempotence/concurrency, and existing adoption regressions. Current full evidence remains separately scoped; no actual adopter/apply or live activation follows from local PASS.

Proposed CLI: `--resolution-plan <metadata-only JSON> --approve-plan-sha256 <exact SHA256>`, used with explicit `--upgrade`. A plan is one-shot against its exact current manifest; subsequent unchanged-source upgrades are idempotent without replaying the consumed resolution. This is not a generic --force or overlay engine.
