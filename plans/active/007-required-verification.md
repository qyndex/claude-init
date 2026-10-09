---
id: 007
slug: required-verification
spec: specs/active/007-required-verification.md
status: approved
owner: "@codex"
created: 2026-10-09
updated: 2026-10-09
---

# Required verification implementation

Extract task acceptance into a Python standard-library gate with explicit base resolution, duplicate detection and subprocess timeouts. Invoke it from verify for detached checkouts too. Reject skip requests rather than trusting local marker files or CI flags. Validate detection once and account for tests by language rather than a shared Boolean. Regression fixtures use disposable repositories and stub tools, never live merge authority.

- T-173 / AC-1: detached acceptance regression and runner.
- T-174 / AC-2, AC-3: waiver and stack regression and gate changes.

- T-176 / AC-4: fail-closed numeric coverage reports.

The independent evidence contract and complete coverage applicability matrix remain F-01/F-02 work, explicitly tracked in the factory plan.
