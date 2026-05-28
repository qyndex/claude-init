# Stream Brief — feat-{{ STREAM_ID }}

> Loaded into the background session via `--append-system-prompt-file`. The feature-stream agent reads this first.

## Stream identity
- **Stream ID**: feat-{{ STREAM_ID }}
- **Branch**: {{ BRANCH }} (the worktree is already on this branch)
- **Allocated tasks**: T-{{ ID_A }}, T-{{ ID_B }}, T-{{ ID_C }}
- **Estimated wall-clock**: {{ MINUTES }} min
- **Budget**: ${{ USD }} USD, {{ TURNS }} turns

## Scope

{{ ONE_PARAGRAPH_SCOPE }}

## Files owned (you are the only writer)

- {{ PATH_1 }}
- {{ PATH_2 }}
- {{ PATH_3 }}

## Files shared (designated owner: {{ OWNER_STREAM }})

You may *read* these but **must not write**. If you need a change here, signal the owner via a TODO in your handoff. Stream `{{ OWNER_STREAM }}` will incorporate.

- {{ PATH_X }} — owner: {{ OWNER_STREAM }}

## Acceptance per task

For each task in your allocation, the gate is:

1. `accept:` command in `tasks/TASKS.md` exits 0
2. `bash .claude/scripts/verify.sh` exits 0
3. (If UI change) `webapp-testing` skill captures screenshots in `verify/<date>/T-<id>/`
4. (If auth/data/network/dep change) `semgrep mcp` clean + `gh dependency-review` clean

## Cross-stream dependencies

{{ DEPENDENCIES_TEXT or "none" }}

## Coordinator contract

- After **each task**, write a handoff: `.swarms/streams/feat-{{ STREAM_ID }}/handoff-T-<id>-<ts>.md`
- At **stream end**, write final handoff: `.swarms/streams/feat-{{ STREAM_ID }}/handoff-final-<ts>.md`
- Push branch to origin when done; coordinator opens the PR

## References

- Brief schema: `.claude/skills/parallel-swarm/SKILL.md`
- Handoff format: `.claude/skills/handoff/SKILL.md`
- TDD discipline: `obra/superpowers/skills/test-driven-development`
- Verification gate: `obra/superpowers/skills/verification-before-completion`
