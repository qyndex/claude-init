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
spec: specs/active/036-worker-environment-boundary.md
---

# Credential inheritance plan

T-210 replaces blanket environment copying in the supervised worker/guardian chain with ordinary runtime keys and one dedicated implementation OAuth mapping. Verify actual observed worker environments and timeout outcomes, then rerun supervisor, ledger/resources and abrupt-death receipt drills. Refresh affected specs 012/014 acceptance evidence. This does not isolate HOME, keychain, process visibility or same-user files; a separately verified isolated worker adapter/principal remains required before factory rollout.
