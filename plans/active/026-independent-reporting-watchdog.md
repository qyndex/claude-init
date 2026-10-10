---
id: 026
slug: independent-reporting-watchdog
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
complexity: M
objective: KR-PLATFORM
service_tier: T2
spec: specs/active/026-independent-reporting-watchdog.md
---

# Independent timer implementation plan

T-199: implement a read-only hosted checkpoint/remote receipt health probe usable outside Actions. Add disabled-by-default protected heartbeat integration after successful delivery, with an empty-body canonical Healthchecks UUID endpoint and strict acknowledgement/redirect handling. Prove normal/file receipts, no writes, grace/DST boundaries and negative configuration/proof/endpoint cases. Document external timer setup and recovery drills; user selects/provisions live monitor separately. Do not claim a GitHub-only status check detects scheduler outages. Merge after exact-head gates.
