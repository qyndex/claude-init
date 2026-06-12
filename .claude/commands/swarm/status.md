---
description: Show live status of all swarm streams. Reads claude agents --json + fleet.json + latest handoffs per stream.
argument-hint: "[--follow] [--stream feat-001]"
allowed-tools: Bash, Read, Glob
disable-model-invocation: true
---

# /swarm:status — Live swarm status

Show what every stream is doing right now.

```!
echo "=== Daemon ==="
claude daemon status 2>/dev/null || echo "(daemon command not available)"
```

```!
echo
echo "=== Fleet (background sessions) ==="
claude agents --json 2>/dev/null | jq -r '.[] | select(.background == true) | "\(.name)\t\(.status)\t\(.worktree // "-")\tsid:\(.id[0:12])"' | column -t
```

```!
echo
echo "=== Fleet.json (coordinator's view) ==="
jq -r '.fleet | to_entries[] | "\(.key)\t\(.value.status)\tspawned:\(.value.spawned)"' .swarms/coordinator/fleet.json 2>/dev/null | column -t
```

```!
echo
echo "=== Latest handoffs per stream (NEXUS v1.0 yaml — e2e-audit swarm-5) ==="
for dir in .swarms/streams/*/; do
  stream=$(basename "$dir")
  latest=$(ls -t "$dir"/handoff-*.yaml 2>/dev/null | head -1)
  if [ -n "$latest" ]; then
    status=$(grep -m1 '^status:' "$latest" | sed 's/^status:[[:space:]]*//')
    attempt=$(grep -m1 '^attempt:' "$latest" | sed 's/^attempt:[[:space:]]*//')
    valid=valid
    bash .claude/scripts/validate-handoff.sh "$latest" >/dev/null 2>&1 || valid=INVALID
    echo "$stream: ${status:-?} (attempt ${attempt:-?}, $valid) — $latest"
  else
    echo "$stream: no handoff yet"
  fi
done
```

```!
echo
echo "=== Decisions log (last 10) ==="
tail -10 .swarms/coordinator/decisions.log 2>/dev/null
```

After running, summarize in 3-5 lines:
- N streams running, M completed (QA-PASS), K escalated
- Any stream stuck > 30 min (no new handoff)
- Suggested next: `/swarm:merge` if any PASSes, `/swarm:respawn <id>` if any crashed, `/swarm:stop <id>` if any need killing
