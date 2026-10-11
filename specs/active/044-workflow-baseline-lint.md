---
id: 044
slug: workflow-baseline-lint
status: approved
owner: "@codex"
created: 2026-10-11
updated: 2026-10-11
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Complete workflow lint baseline

Authorized remaining F-00 clean-actionlint exit evidence. Preserve workflow meaning while eliminating fragile filename handling and intentional-literal warnings without suppression.

## Acceptance criteria

1. **AC-1**: Full actionlint including ShellCheck passes for every shipped workflow, without adding lint disables or weakening checks.
2. **AC-2**: Actual JSON validation step handles spaces/newlines/shell characters in filenames and rejects invalid JSON, absent required roots and failed find execution.
3. **AC-3**: Actual bundle-size step processes filenames as data, requires real build assets, rejects an over-budget compressed bundle and propagates compressor failure without shell injection.
4. **AC-4**: Actual project-update shell preserves literal GraphQL variable references through all three requests. Existing numeric stale-spec count retains zero/matching outcomes; workflow lint and harness validation pass.
