---
id: 024
slug: reporting-receipt-projection
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
complexity: M
objective: KR-PLATFORM
service_tier: T2
spec: specs/active/024-reporting-receipt-projection.md
---

# Hosted receipt projection plan

T-197: extract shared artifact authentication from runtime mutation; preserve the current-revision requirement for runtime and use authenticated merge-time spec bytes for historical reporting. Paginate configured coordinator history, reject duplicate/over-limit/conflicting evidence, and atomically build local reporting-only tables. Wire trusted checkout policy and Actions read permission into the due hosted runner. Prove fresh-disk digest mapping, negative authentication, unchanged runtime behavior, disabled-authority operation, preserved public checkpoint schema and all regressions. Merge only after exact-head required gates pass. Do not enable producers or merge authority; authenticated live receipts require the separate quota-restoration/shadow package.
