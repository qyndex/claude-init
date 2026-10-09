---
id: 009
slug: protected-factory-activation
spec: specs/active/009-protected-factory-activation.md
status: approved
owner: "@codex"
created: 2026-10-09
updated: 2026-10-09
---

# Protected factory activation

Implement a protected policy and coordinator, with API wrappers isolated from the deterministic evaluator for injected regression tests. Authenticated GitHub runs supply artifacts; approve their workflow definitions by digest, validate artifact bytes and replace embedded check claims with live exact-head check receipts. Pin factory eligibility to the dedicated App in branch protection, preserve existing live constraints, and recheck head/base before conditional merge. Candidate changes to authority files require operator decisions.

Replace every merge trigger with a coordinator request. Local verified-merge can produce/push a PR and request integration, but never revert a locally guessed HEAD or push main.

- T-177: AC-1, AC-2, AC-5 protected coordinator and regression.
- T-178: AC-3 request-only legacy merge routes.
- T-179: AC-4 App bootstrap, policy preflight and draft activation PR.

Publish only owned work on an isolated origin/main worktree; leave the original checkout and five initiative STATE edits untouched. Do not enable live authority before the activation PR has an operator decision and a successful shadow candidate.
