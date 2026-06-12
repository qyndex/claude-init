---
description: Restart a crashed or stopped stream. Reads existing state (brief, task.json, last handoff), spawns fresh session pointed at the same worktree, picks up where the previous session left off.
argument-hint: "<stream-id>"
allowed-tools: Bash, Read
disable-model-invocation: true
---

# /swarm:respawn — Restart a crashed stream

The logic lives in `.claude/scripts/swarm-respawn.sh` (e2e-audit swarm-4: extracted
so `fleet-reconcile.sh --respawn` and the coordinator can invoke it programmatically;
fleet writes are atomic same-dir tempfiles, not the old fixed /tmp path).

```bash
bash .claude/scripts/swarm-respawn.sh "$1"
```

Flags: `--budget <usd>` (default 5), `--max-turns <n>` (default 200).

For fleet-wide crash detection first, run:

```bash
bash .claude/scripts/fleet-reconcile.sh            # diff fleet.json vs claude agents --json
bash .claude/scripts/fleet-reconcile.sh --respawn  # also respawn crashed streams (≤ MAX_RESPAWNS=3)
```

## Notes on resumability

- The resume context is built into the prompt — there's no `--resume-from-handoff`
  CLI flag; resumability lives in the brief itself plus the agent reading its own
  `.swarms/streams/<id>/` state files at startup.
- WIP commits in the worktree branch are the source of truth for code state.
- `qa_attempts` in task.json survives the respawn — the self-heal cap cannot be
  reset by crashing.
