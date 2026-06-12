---
description: Kill the whole swarm at once. Stops every running background session, writes ESCALATION handoff per stream, preserves worktrees for inspection. Use when you need to halt all parallel work fast.
argument-hint: "[--force]"
allowed-tools: Bash, Read, Edit, Write
disable-model-invocation: true
---

# /swarm:abort — Stop the entire swarm

Cleanly stop every running stream. Use when:
- You realize the swarm plan was wrong and want to start over
- A shared dependency broke and continuing wastes budget
- You're going home and don't want overnight tokens spent

Process:

```bash
# Get every running stream from fleet.json
running=$(jq -r '.fleet | to_entries[] | select(.value.status == "running" or .value.status == "respawned") | .key' .swarms/coordinator/fleet.json)

# For each, send graceful stop + force after 30s
for stream in $running; do
  echo "  → stopping $stream"
  # Graceful — give it 30s to write a final handoff
  claude attach "$stream" --send "Please write a final handoff with Status: STOPPED and exit cleanly." 2>/dev/null &
done
sleep 30

# Force-stop any still alive
for stream in $running; do
  claude stop "$stream" 2>/dev/null || true

  # Update fleet.json
  jq --arg id "$stream" \
     '.fleet[$id].status = "stopped" | .fleet[$id].stopped_at = (now|todate)' \
     .swarms/coordinator/fleet.json > .swarms/coordinator/.fleet.json.tmp.$$ && mv .swarms/coordinator/.fleet.json.tmp.$$ .swarms/coordinator/fleet.json

  echo "$(date -Iseconds) $stream     Aborted by /swarm:abort" >> .swarms/coordinator/decisions.log
done
```

After completion:
- Print summary table: `<stream> | <status before> | <stopped|forced>`
- Worktrees preserved at `.claude/worktrees/feat-<N>` for inspection
- Suggested next: `/swarm:status` to confirm everything stopped, then `/swarm:plan` to start fresh

`--force` skips the 30s graceful window and force-stops immediately.

$ARGUMENTS
