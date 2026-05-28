---
description: Restart a crashed or stopped stream. Reads existing state (brief, task.json, last handoff), spawns fresh session pointed at the same worktree, picks up where the previous session left off.
argument-hint: "<stream-id>"
allowed-tools: Bash, Read, Edit, Write
disable-model-invocation: true
---

# /swarm:respawn — Restart a crashed stream

```bash
stream="$1"

if [ -z "$stream" ]; then
  echo "Usage: /swarm:respawn <stream-id>"
  exit 2
fi

# Sanity: stream dir must exist
if [ ! -d ".swarms/streams/$stream" ]; then
  echo "No such stream: .swarms/streams/$stream"
  exit 1
fi

# Try native respawn first — preserves session state if daemon held it
if claude respawn "$stream" 2>/dev/null; then
  echo "Native respawn succeeded for $stream"
  jq --arg id "$stream" '.fleet[$id].status = "respawned" | .fleet[$id].respawned_at = (now|todate)' \
     .swarms/coordinator/fleet.json > /tmp/fleet.json && mv /tmp/fleet.json .swarms/coordinator/fleet.json
  echo "$(date -Iseconds) $stream     Native respawn" >> .swarms/coordinator/decisions.log
  exit 0
fi

# Native respawn failed — spawn fresh but pointed at the same worktree + brief.
# The agent will read .swarms/streams/<id>/{progress.md, task.json, handoff-*.md}
# to reconstruct partial state. WIP commits in the worktree branch are the
# source of truth for code state.
echo "Native respawn failed; spawning fresh session..."

# The resume context is built into the prompt — there's no `--resume-from-handoff`
# CLI flag; resumability lives in the brief itself plus the agent's reading of
# its own .swarms/streams/<id>/ state files at startup.
resume_prompt=$(cat <<EOF
Resume stream $stream. The previous session may have made partial progress.

BEFORE starting any task:
1. Read .swarms/streams/$stream/brief.md (your scope and allocation)
2. Read .swarms/streams/$stream/task.json (current task + qa_attempts counter)
3. Read .swarms/streams/$stream/progress.md (what was done)
4. Read the latest .swarms/streams/$stream/handoff-*.md (state at last checkpoint)
5. Inspect WIP commits on the branch: \`git log --oneline | grep '^[0-9a-f]\+ WIP:'\` — they hold step-level state

Then continue from where the prior session left off. Use .claude/skills/wip-checkpoint to checkpoint as you go.
EOF
)

sid=$(claude --bg \
     -n "$stream" \
     -w "$stream" \
     --agent feature-stream \
     --append-system-prompt-file ".swarms/streams/$stream/brief.md" \
     --max-turns 200 \
     --max-budget-usd 5 \
     --output-format stream-json \
     -p "$resume_prompt" 2>/dev/null | jq -r '.session_id // empty' | head -1)

if [ -z "$sid" ]; then
  echo "FAILED to spawn fresh session for $stream"
  exit 1
fi

jq --arg id "$stream" --arg sid "$sid" \
   '.fleet[$id] = {sessionId: $sid, status: "respawned", spawned: (now|todate), worktree: (".claude/worktrees/" + $id), branch: $id}' \
   .swarms/coordinator/fleet.json > /tmp/fleet.json && mv /tmp/fleet.json .swarms/coordinator/fleet.json

echo "Respawned $stream as fresh session $sid"
echo "$(date -Iseconds) $stream     Respawned (fresh session $sid, native respawn unavailable)" >> .swarms/coordinator/decisions.log
```

## Notes on resumability

- **No fabricated CLI flag.** Earlier versions of this command referenced `--resume-from-handoff` which is not a documented Claude Code CLI flag. Resumability is achieved by the agent reading its own `.swarms/streams/<id>/` state files at startup — that's why the brief.md + task.json + handoff-*.md + WIP commits matter.
- **Worktree state is canonical.** The branch holds the actual code. State files describe intent and progress.
- **Use `/swarm:abort` if you want a clean restart** instead of resume.

$ARGUMENTS
