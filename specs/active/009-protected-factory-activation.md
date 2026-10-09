---
id: 009
slug: protected-factory-activation
status: approved
owner: "@codex"
human_owner: "@operator"
created: 2026-10-09
updated: 2026-10-09
complexity: L
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Protected factory activation

The operator requested factory activation and authorized preparing a private qyndex-factory GitHub App. Implementation is approved; live merge/security policy changes require the operator's decision on the concrete activation PR.

## Acceptance criteria

1. **AC-1**: A default-branch coordinator evaluates authenticated GitHub data and approved policy. Missing App configuration, approved spec, exact-head evidence, pinned check producers, active target protection, or artifact integrity blocks. It never executes candidate code with merge credentials.
2. **AC-2**: Checks and evidence use exact head/base/spec/policy binding. Trusted artifact run/workflow identity and workflow definition digests are verified. Changes to authority paths, renamed protected paths and out-of-scope files block autonomous merging. Recheck head/base immediately before merging, use GitHub's conditional SHA and record the returned merge SHA.
3. **AC-3**: Ordinary, dependency, release and local verified-merge routes request the same coordinator. Environment bypasses are removed. Local integration does not claim merged until a remote receipt confirms it; dangerous local-HEAD revert/push-to-main is removed.
4. **AC-4**: Prepare a least-privilege private App registration document, disabled bootstrap policy, activation preflight and operator checklist. No secret bytes are printed or committed. Draft PR publication preserves existing initiative modifications and unrelated branch commits.
5. **AC-5**: Offline injected snapshots prove rejection of stale heads/bases, fake receipts, mismatched producers, policy self-changes, protection drift and API failure; a valid fixture merges only the pinned head and emits a receipt.

## Constraints

Production remains disabled until deployment/health/rollback gates are implemented. The new coordinator initially requires an approved complete specification per PR; partial/multi-spec deliveries need a later explicit authority contract. Missing verdict producers cannot be replaced by action-success or PR comments. Merge receipts are external CI artifacts; durable reconciliation and Slack delivery remain activation dependencies.
