---
id: 028
slug: slack-file-activation-canary
status: approved
owner: "@codex"
created: 2028-10-10
updated: 2028-10-10
complexity: S
objective: KR-PLATFORM
service_tier: T2
spec: specs/active/028-slack-file-activation-canary.md
---

# Live file canary plan

T-201: implement explicit manual protected canary, exact remote file lookup, first-run allocation fence and repeat reconciliation. Prove loss/hidden history does not resend. Merge after exact-head gates, dispatch once and repeat to establish live file transport without digest cursor changes. Monitoring provider remains disabled per revised user decision.
