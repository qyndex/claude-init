---
id: 020
slug: strict-installer-source
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Strict installer source and prerequisites

Begin F-07 adoption by making the installer honor the requested branch/tag/full commit SHA and report failures. This slice tests the installer wrapper with a local source repository and stub reconciliation/setup boundaries; manifest ownership, atomic reconciliation and repository configuration follow separately.

## Acceptance criteria

1. **AC-1**: Fetch only the requested valid branch/tag/full SHA, detach at its resolved commit and report that immutable SHA. Unknown or invalid refs fail before target reconciliation; no silent default-branch fallback occurs. Local fixtures prove SHA/tag selection differs from current default HEAD.
2. **AC-2**: Staged, unstaged and untracked target changes are rejected before cloning/reconciliation unless YES=1 explicitly overrides. YES/UPGRADE/SKIP_SETUP accept only 0/1; 0 never means enabled. Target must be the Git repository root.
3. **AC-3**: Ordinary repositories and linked Git worktrees can be targets, including paths with spaces/apostrophes. Existing project content remains untouched by failed prerequisites; wrapper passes paths as arguments without shell evaluation.
4. **AC-4**: Setup failure exits nonzero and cannot print installation success; explicit SKIP_SETUP=1 remains supported. Local source fixtures and ShellCheck pass. Documentation separates reusable harness capabilities from adopter-specific reporting deployment and identifies remaining reconciliation risks without claiming full F-07 readiness.
