---
id: 033
slug: transactional-harness-adoption
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-21
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Transactional reusable harness adoption

Authorized F-07 ownership/rollout scope replaces same-name overwrite and suppressed copy failures. Local installation must not activate external authority.

## Acceptance criteria

1. **AC-1**: Install only tracked process/templates from an immutable clean source, recording source SHA and path hash/mode ownership. Preserve new/existing repository content, exclude active distribution backlog/memory/state/pilot policy/workflows, seed neutral adopter-owned ledgers only when absent and replay without another journal. Dry-run does not mutate the target.
2. **AC-2**: Block foreign collisions and customized/deleted/mode-changed owned files before mutation. Explicit upgrades can change or remove only unchanged owned files; the separately reviewed bounded AC-5 ownership transfer preserves intentional local configuration without treating it as upstream-owned. Guarded revert preserves prior exact images and unknown adopter content; filename alone does not establish ownership.
3. **AC-3**: Store owner-only journals outside the target before atomic file writes. Roll back partial recoverable failures, recover pending exact before/after states, and block later user changes before restoration. Required local tool failures leave no partial installation. Serialize CLI installers by target lock.
4. **AC-4**: Support linked worktrees and spaces/apostrophes; reject unsafe symlink/traversal/dirty-source/non-root paths and malformed ownership. No candidate setup, plugin installation, GitHub mutation or pilot activation occurs. Missing reviewed ruleset blocks adoption handoff. Strict source/boolean/dirty-target wrapper regressions pass; guides describe private recovery and separate per-adopter readiness.

5. **AC-5**: The explicitly approved 2026-10-21 keep-local amendment supports upgrade-only reviewed ownership transfer for exactly `CLAUDE.md`, `.mcp.json`, `.claude/settings.json`. Preserve selected local bytes/modes and source ownership history. Bind a strict bounded resolution plan and explicit approval hash to immutable source SHA, canonical target/repository identity, current manifest fingerprint, original owned/current local/incoming upstream fingerprints. Stale, duplicate, unsafe, nonallowlisted or general-force requests reject before effects. Without a plan, v1 customization rejection stays unchanged. Read existing v1 manifests; new separate local-override ownership metadata makes old updaters fail closed. Subsequent upstream configuration changes require renewed review; selected local configuration is never auto-merged or overwritten. `.claude/CLAUDE.md`, scripts, hooks and framework agents remain strictly managed.
6. **AC-6**: Real isolated adopter-shaped fixtures prove both two-path and three-path local override sets survive byte/mode-exact while remaining managed code updates. Prove no-plan repeat idempotence, stale plan/source/manifest/current bytes/modes/repository and unsafe/release rejection, unowned memory/custom-agent preservation, private metadata journaling and guarded fault recovery, foreign later-change rejection and per-target CLI serialization. Keep adopted configuration values/private journals out of public output; no actual adopter migration, publication, live policy/configuration installation, provider or authority activation is authorized by this implementation/local-test amendment.

## Approved bounded continuation — 2026-10-21

The user approved Option A of the external decision package SHA256 `f7f4a3e0e085058f97db14852b6b7dae369bdbdb99ef7968c1d21ea09082939d`. This approves implementation and local fixtures only. Exact source publication and per-adopter upgrade/cutover remain separate reviewed payloads. The intentional bootstrap overrides must be preserved, never reset to upstream defaults or silently accepted through hand-edited manifests.
