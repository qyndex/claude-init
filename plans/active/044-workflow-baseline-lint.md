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
spec: specs/active/044-workflow-baseline-lint.md
---

# Workflow baseline cleanup

T-218 replaces word-split find loops with checked null-delimited manifests, quotes the drift diagnostic, converts literal GraphQL query strings to quoted heredocs and computes bundle sizes through positional filenames with strict failure propagation. Remove remaining stale-check lint findings while preserving zero counts. Execute shipped shell bodies in isolated temporary fixtures with fake external commands; no live deployments/issues/project mutations. This closes lint exit evidence, not native model capacity or autonomous rollout activation.
