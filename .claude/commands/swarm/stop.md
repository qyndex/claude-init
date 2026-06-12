---
description: "Cleanly stop a swarm stream. Writes final handoff (status: STOPPED), keeps worktree for inspection."
argument-hint: "<stream-id>"
allowed-tools: Bash, Read, Edit, Write
disable-model-invocation: true
---

# /swarm:stop — Stop a stream cleanly

```bash
stream="$1"

# 1. Tell the stream to wrap up (graceful)
claude attach "$stream" --send "Please write a final handoff with Status: STOPPED and exit cleanly."
sleep 30

# 2. Force stop if still running
claude stop "$stream"

# 3. Update fleet.json
jq --arg id "$stream" '.fleet[$id].status = "stopped"' .swarms/coordinator/fleet.json > .swarms/coordinator/.fleet.json.tmp.$$ && mv .swarms/coordinator/.fleet.json.tmp.$$ .swarms/coordinator/fleet.json

# 4. Log
echo "$(date -Iseconds) $stream     Stopped by user" >> .swarms/coordinator/decisions.log
```

Worktree is preserved so the work can be inspected or resumed via `/swarm:respawn`.
