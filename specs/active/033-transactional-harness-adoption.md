---
id: 033
slug: transactional-harness-adoption
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Transactional reusable harness adoption

Authorized F-07 ownership/rollout scope replaces same-name overwrite and suppressed copy failures. Local installation must not activate external authority.

## Acceptance criteria

1. **AC-1**: Install only tracked process/templates from an immutable clean source, recording source SHA and path hash/mode ownership. Preserve new/existing repository content, exclude active distribution backlog/memory/state/pilot policy/workflows, seed neutral adopter-owned ledgers only when absent and replay without another journal. Dry-run does not mutate the target.
2. **AC-2**: Block foreign collisions and customized/deleted/mode-changed owned files before mutation. Explicit upgrades can change or remove only unchanged owned files. Guarded revert preserves prior exact images and unknown adopter content; filename alone does not establish ownership.
3. **AC-3**: Store owner-only journals outside the target before atomic file writes. Roll back partial recoverable failures, recover pending exact before/after states, and block later user changes before restoration. Required local tool failures leave no partial installation. Serialize CLI installers by target lock.
4. **AC-4**: Support linked worktrees and spaces/apostrophes; reject unsafe symlink/traversal/dirty-source/non-root paths and malformed ownership. No candidate setup, plugin installation, GitHub mutation or pilot activation occurs. Missing reviewed ruleset blocks adoption handoff. Strict source/boolean/dirty-target wrapper regressions pass; guides describe private recovery and separate per-adopter readiness.
