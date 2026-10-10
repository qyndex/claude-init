---
id: 023
slug: slack-split-receipts
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
complexity: M
objective: KR-PLATFORM
service_tier: T2
spec: specs/active/023-slack-split-receipts.md
---

# Split receipt implementation plan

T-196: reproduce split successful response and lost response using the actual hosted/Slack adapters. Validate every matching fragment and require exact whole-report reconstruction before creating an opaque versioned ordered-ID receipt. Preserve all durable state and uncertainty on incomplete recovery; retain single-message compatibility. Prove malicious/partial/duplicate cases, fresh-disk recovery and unchanged repeat runs. Merge only after exact-head gates; rerun the existing pilot against its preserved uncertain checkpoint without resetting or resending.
