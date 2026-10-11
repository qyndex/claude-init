---
id: 039
slug: offline-worker-containers
status: approved
owner: "@codex"
created: 2026-10-11
updated: 2026-10-11
complexity: M
objective: KR-PLATFORM
service_tier: T2
spec: specs/active/039-offline-worker-containers.md
---

# Offline worker implementation

T-213 adds a trusted Docker adapter to approved ledger resources, supervisor and guardian. Persist observed container identity in private SQLite and provide stale-effect cleanup commands. Required Linux CI runs a disposable scratch/busybox isolation drill with no factory credentials. Keep production worker/authority activation disabled pending dedicated worker infrastructure, approved provider egress, native subscription proof and independent verification. Publish a draft until actual Linux AC-4 evidence exists. Refresh affected runtime, ledger, supervisor, receipt recovery and external-effect evidence.
