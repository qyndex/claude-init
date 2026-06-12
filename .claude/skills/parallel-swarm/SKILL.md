---
name: parallel-swarm
description: Coordinator-led parallel feature development. 5-10 features built simultaneously via native `claude --bg --worktree feat-<N>`. Each stream has own subagent team; coordinator merges. Built on native CC v2.1.144+ primitives — no custom orchestrator.
when_to_use: User says "swarm", "parallel features", "build everything", "swarm-plan", "fan out N streams", "work on these in parallel". `/swarm-plan`, `/swarm-status`, `/swarm-merge` commands invoke this.
model: sonnet
allowed-tools: Read, Glob, Grep, Edit, Write, Bash, TodoWrite
disable-model-invocation: true
---

# Parallel Swarm

Native Claude Code primitives do the heavy lifting; we provide the content (briefs, state files, handoff format).

## Topology

```
COORDINATOR SESSION (foreground, you)
        │
        ├── claude --bg -w feat-001 --agent feature-stream    [streamId 1]
        ├── claude --bg -w feat-002 --agent feature-stream    [streamId 2]
        ├── claude --bg -w feat-003 --agent feature-stream    [streamId 3]
        ├── claude --bg -w feat-004 --agent feature-stream    [streamId 4]
        └── claude --bg -w feat-005 --agent feature-stream    [streamId 5]
```

Each `--bg` is a native daemon-supervised background session. Each `-w feat-<N>` creates a native git worktree at `.claude/worktrees/feat-<N>/`. Coordinator monitors via `claude agents --json`.

## State files

Everything lives under `.swarms/`:

```
.swarms/
├── coordinator/
│   ├── plan.md                # Overall plan
│   ├── fleet.json             # {streamId: {sessionId, worktree, status, branch, taskIds}}
│   └── decisions.log          # Append-only
└── streams/
    └── <stream-id>/
        ├── brief.md           # Loaded into the background session via --append-system-prompt-file
        ├── task.json          # ccg-workflow schema
        ├── analysis.md        # ccpm-style: scope, files-owned, files-shared-with-owner
        ├── progress.md        # Updated by stream
        ├── context.jsonl      # Spec refs auto-injected into subagents
        └── handoff-<ts>.yaml  # NEXUS v1.0
```

## Process

### 1. Plan (coordinator)
- Read `tasks/TASKS.md`. Identify independent streams (tasks with `parallel: yes` and no cross-deps).
- Group tasks into 5-10 streams. Each stream owns a coherent feature area.
- For each stream, write `analysis.md`:
  - Scope (1 paragraph)
  - Files owned (this stream is the only writer)
  - Files shared (one designated owner per file — see CCPM)
  - Acceptance commands (machine-verifiable)
- Write `brief.md` for each stream (this becomes the system-prompt extension for the background session).

### 2. Dispatch (coordinator)
- For each stream:
  ```bash
  sid=$(claude --bg -w feat-<N> \
       --agent feature-stream \
       --append-system-prompt-file .swarms/streams/<N>/brief.md \
       --max-turns 200 \
       --max-budget-usd 5 \
       --output-format stream-json \
       -p "Begin stream <N>. Read .swarms/streams/<N>/brief.md and execute.")
  echo "Spawned stream <N>: $sid"
  ```
- Update `.swarms/coordinator/fleet.json` with each session ID.

### 3. Monitor (coordinator, interactive)
- Use `claude agents` (TUI) or `claude agents --json` (scriptable).
- Watch for handoff files appearing in `.swarms/streams/<N>/`.
- If a stream hits `QA-FAIL` 3x, mark it for escalation; consider re-dispatching with refined brief.

### 4. Merge (coordinator)
- When a stream reports `QA-PASS` and writes its final handoff:
  - Coordinator: `gh pr create` from the stream's branch
  - Wait for CI (claude-review + claude-security + ci + e2e-preview)
  - Squash-merge once green
  - Delete the worktree: `git worktree remove .claude/worktrees/feat-<N>`

### 5. Conflict resolution (coordinator)
- Streams should not collide because each owns its file set.
- If two streams need to write to the same file: only the *designated owner* writes; other streams `git pull --rebase` after the owner commits.
- If conflicts arise anyway: coordinator merges manually with the human in the loop (do not auto-resolve code conflicts).

## Hard rules

- **One implementer per file at a time.** Worktree isolation isn't enough — if two streams need file X, designate an owner.
- **`tasks/TASKS.md` is coordinator-owned.** Feature-streams report task completion via their NEXUS handoff; only the coordinator marks `[x]` / `[!]` / `[s]` in the live `tasks/TASKS.md`. This prevents merge conflicts when multiple streams finish tasks concurrently.
- **No nested swarms.** A feature stream never spawns its own swarm. Spawn subagents in-stream, not streams-in-streams.
- **Budget per stream.** `--max-budget-usd` is mandatory. Default 5 USD per stream.
- **Resumable.** Streams write WIP checkpoints continuously (per `wip-checkpoint` skill). If a stream session crashes, `claude respawn <id>` brings it back.
- **Coordinator never edits code.** It only orchestrates, monitors, merges. Code edits happen inside the streams.

## Commands

- `/swarm-plan <N>` — plan N independent streams from the backlog
- `/swarm-dispatch` — spawn the planned streams as `--bg` sessions
- `/swarm-status` — pretty-print `claude agents --json` + fleet.json
- `/swarm-merge` — for each PASS stream, open PR and merge
- `/swarm-stop <stream>` — stop one stream cleanly
- `/swarm-respawn <stream>` — restart a crashed stream

## References

- Native Claude Code v2.1.144+ CLI (--bg, -w, agents, attach/logs/stop/respawn, --teammate-mode)
- automazeio/ccpm (stream-analysis schema, designated owner for shared files)
- ccg-workflow/templates (task.json schema, hooks)
- obra/superpowers/skills/using-git-worktrees (native-first principle)
- obra/superpowers/skills/dispatching-parallel-agents (when to fan out, when not to)
- msitarzewski/agency-agents (NEXUS handoff format)
