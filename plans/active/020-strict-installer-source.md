---
id: 020
slug: strict-installer-source
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
spec: specs/active/020-strict-installer-source.md
---

# Strict source installation plan

Inspect root/dirty state first, allowing linked worktrees without assuming `.git` is a directory. Validate explicit boolean options. Initialize a temporary source checkout, fetch only the requested ref, resolve FETCH_HEAD to a commit and detach. Do not fall back to remote default HEAD when a ref is wrong. Leave staging outside the target and preserve exact argument boundaries. Propagate setup failure even though reconciliation may already have written files; tell the operator the candidate is incomplete. Test with disposable local Git sources and a stub reconciler/setup to isolate this wrapper. Versioned ownership and transactional reconciliation are the next F-07 slice, not established by these fixtures.
