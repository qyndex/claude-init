---
description: Spawn `claude --bg --worktree feat-<N>` for each planned stream. Pre-flight checks, then bulk dispatch. Updates fleet.json with session IDs. Supports --only (filter) and --dry-run (no spawn).
argument-hint: "[--dry-run] [--only feat-001,feat-002]"
allowed-tools: Read, Glob, Grep, Bash, Edit, Write
disable-model-invocation: true
---

# /swarm:dispatch — Spawn the planned streams

Dispatch all (or filtered) streams as background sessions.

## How $ARGUMENTS are parsed

- `--dry-run` — runs all pre-flight checks and prints what *would* be spawned; spawns nothing
- `--only feat-001,feat-002` — spawn only the listed streams (comma-separated, no spaces)
- `--budget <N>` — override per-stream USD cap (default 5)
- `--max-turns <N>` — override per-stream turn cap (default 200)

## Pre-flight checks (run all; if any fail, abort)

1. `bash .claude/scripts/validate.sh` — harness is valid
2. `git status --porcelain` is empty — main worktree clean
3. `claude daemon status` — daemon healthy (warn-only if not present)
4. `.swarms/streams/<id>/brief.md` exists and non-empty for every stream to dispatch
5. `.swarms/coordinator/fleet.json` exists and is valid JSON

If any check fails, emit a specific actionable error (e.g., "Stream feat-003 has no brief.md — run /swarm:plan first").

## Execute via the dispatch script

Delegate the actual spawning logic to `.claude/scripts/swarm-dispatch.sh`, which:

- Parses `$ARGUMENTS` for `--only`, `--dry-run`, `--budget`, `--max-turns`
- Walks `.swarms/streams/*/` and filters by `--only` if present
- Skips any stream already marked `running` in fleet.json
- For each remaining stream: spawns `claude --bg --worktree feat-<N> ...` and captures session id
- Updates `.swarms/coordinator/fleet.json` atomically
- Appends to `decisions.log`
- On `--dry-run`: emits a table of "would spawn" + exits 0 without side effects

Invoke:

```bash
bash .claude/scripts/swarm-dispatch.sh $ARGUMENTS
```

## After dispatch

```bash
claude agents --json | jq '.[] | select(.background == true) | {id, name, status, worktree}'
```

## Output to chat

- `Dispatched <N> streams.` (or `Dry-run: would dispatch <N> streams.`)
- Table: `feat-NNN | <session-id-short> | <branch>`
- Suggested next: `/swarm:status` to watch

$ARGUMENTS
