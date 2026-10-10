---
id: 031
slug: authenticated-feedback-control
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
complexity: S
objective: KR-PLATFORM
service_tier: T2
spec: specs/active/031-authenticated-feedback-control.md
---

# Operator transition plan

T-205: add read-only authenticated top-level approval/acceptance polling against isolated coordinator configuration. Store immutable pending/confirmed command intents. Bind approval to a full proposal hash and explicit next version; bind acceptance to delivered current version. Add version checks inside core transactions and make accepted-event replay independent of later audit events. Keep each authenticated command independently durable; full page traversal and source validation precede transitions. Verify crash recovery, source conflicts and capture/control coexistence. Merge with complete evidence; no live policy or merge authority activation.
