#!/usr/bin/env bash
# SubagentStop hook — Round 6 C makes this a DIGEST, not just a log line.
#
# When a subagent completes, parse its final message for a NEXUS YAML handoff
# block. Extract status, files modified, follow-up tasks, blockers. Surface
# the digest back to the parent as additionalContext so the parent doesn't
# have to read 30 turns of transcript to understand what happened.
#
# Also runs `git diff --name-only` against any swarm worktree to surface file
# changes the parent's main worktree can't see.
#
# Output schema (single JSON line to subagent.jsonl):
# {ts, agent_type, session_id, status, files_modified, followup_tasks, blockers}

set -uo pipefail

mkdir -p .claude/hooks/.log

input=$(cat)
agent_type=$(printf '%s' "$input" | jq -r '.agent_type // .tool_input.subagent_type // "unknown"')
session_id=$(printf '%s' "$input" | jq -r '.session_id // ""')
final_message=$(printf '%s' "$input" | jq -r '.tool_response.final_message // .tool_response.content // ""')
ts=$(date -Iseconds)

# Plain log (preserved for backward compat)
printf '%s\tagent=%s\n' "$ts" "$agent_type" >> .claude/hooks/.log/subagent.log

# ─── Round 6 C: extract NEXUS YAML handoff block ────────────────────────
# Look for fenced ```nexus or ```yaml block in the final message.
status=""
handoff_path=""
followup_count=0
blockers_count=0
files_modified=""

if [ -n "$final_message" ]; then
  # Save final message to a temp for grep + extract block content
  tmp_msg=$(mktemp)
  printf '%s' "$final_message" > "$tmp_msg"

  # Look for ```nexus or ```yaml block
  yaml_block=$(awk '
    /^```(nexus|yaml)$/ { in_block=1; next }
    /^```$/ && in_block { in_block=0 }
    in_block { print }
  ' "$tmp_msg")

  if [ -n "$yaml_block" ]; then
    # Crude field extraction (we don't depend on yq; bash + grep is enough for status)
    status=$(echo "$yaml_block" | grep -E '^status:' | head -1 | sed 's/status:[[:space:]]*//' | tr -d '"' | head -c 50)
    followup_count=$(echo "$yaml_block" | awk '/^followup_tasks:/{f=1; next} /^[a-z_]+:/{f=0} f && /^[[:space:]]*-/' | wc -l | tr -d ' ')
    blockers_count=$(echo "$yaml_block" | awk '/^blockers_encountered:/{f=1; next} /^[a-z_]+:/{f=0} f && /^[[:space:]]*-[[:space:]]*description:/' | wc -l | tr -d ' ')
    files_modified=$(echo "$yaml_block" | awk '/^files_modified:/{f=1; next} /^[a-z_]+:/{f=0} f && /^[[:space:]]*-[[:space:]]*path:/' | sed 's/.*path:[[:space:]]*//' | head -10 | tr '\n' ',' | sed 's/,$//')

    # ─── Round 6 D: hard-enforce for swarm streams ──────────────────────
    # feature-stream and coordinator MUST emit valid YAML. Other agents emit
    # but block-validation is soft (warn, accept).
    case "$agent_type" in
      feature-stream|coordinator)
        # Validate the block; non-zero exit blocks the subagent's stop
        if ! echo "$yaml_block" | bash .claude/scripts/validate-handoff.sh --stdin >/dev/null 2>&1; then
          rm -f "$tmp_msg"
          cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStop",
    "additionalContext": "[subagent-stop] BLOCK: ${agent_type} returned an INVALID NEXUS handoff. Re-emit with all required fields per .swarms/templates/handoff.yaml. Run: echo \\\"\$BLOCK\\\" | bash .claude/scripts/validate-handoff.sh --stdin to debug."
  }
}
EOF
          # Log the failure
          printf '%s\tagent=%s\tinvalid_handoff\n' "$ts" "$agent_type" >> .claude/hooks/.log/subagent.log
          exit 2
        fi
        ;;
    esac
  elif [ "$agent_type" = "feature-stream" ] || [ "$agent_type" = "coordinator" ]; then
    # Hard-enforced agent didn't emit a YAML block at all
    rm -f "$tmp_msg"
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStop",
    "additionalContext": "[subagent-stop] BLOCK: ${agent_type} did not emit a NEXUS handoff block (\`\`\`nexus or \`\`\`yaml). This is required for swarm agents. See .claude/skills/handoff/SKILL.md."
  }
}
EOF
    printf '%s\tagent=%s\tmissing_handoff\n' "$ts" "$agent_type" >> .claude/hooks/.log/subagent.log
    exit 2
  fi

  # Find any handoff-<ts>.yaml or .md file the subagent may have written
  handoff_path=$(find .swarms -name 'handoff-*.yaml' -o -name 'handoff-*.md' -newer .claude/hooks/.log/subagent.log -type f 2>/dev/null | head -1)
  rm -f "$tmp_msg"
fi

# ─── Worktree git diff surface (feature-stream only) ────────────────────
worktree_diff=""
if [ "$agent_type" = "feature-stream" ]; then
  # Look up worktree from fleet.json by session_id
  if [ -f .swarms/coordinator/fleet.json ] && command -v jq >/dev/null 2>&1; then
    worktree=$(jq -r --arg sid "$session_id" \
      '.fleet | to_entries[] | select(.value.sessionId == $sid) | .value.worktree' \
      .swarms/coordinator/fleet.json 2>/dev/null | head -1)
    if [ -n "$worktree" ] && [ -d "$worktree" ]; then
      worktree_diff=$(cd "$worktree" && git diff --name-only main...HEAD 2>/dev/null | head -10 | tr '\n' ',' | sed 's/,$//')
    fi
  fi
fi

# ─── Emit structured event ──────────────────────────────────────────────
jq -nc \
  --arg ts "$ts" \
  --arg agent_type "$agent_type" \
  --arg session_id "$session_id" \
  --arg status "${status:-unknown}" \
  --arg handoff_path "${handoff_path:-}" \
  --arg files_modified "${files_modified:-}" \
  --arg worktree_diff "${worktree_diff:-}" \
  --argjson followup_count "${followup_count:-0}" \
  --argjson blockers_count "${blockers_count:-0}" \
  '{
    ts: $ts,
    agent_type: $agent_type,
    session_id: $session_id,
    status: $status,
    handoff_path: $handoff_path,
    files_modified: ($files_modified | split(",") | map(select(length > 0))),
    worktree_diff: ($worktree_diff | split(",") | map(select(length > 0))),
    followup_tasks_count: $followup_count,
    blockers_count: $blockers_count
  }' >> .claude/hooks/.log/subagent.jsonl 2>/dev/null

# ─── Round 6 C: surface digest back to parent ───────────────────────────
# additionalContext flows into the parent's next prompt so the parent sees
# a structured digest instead of having to re-parse the subagent's prose.
digest_parts=()
[ -n "$status" ] && digest_parts+=("status=$status")
[ -n "$handoff_path" ] && digest_parts+=("handoff=$handoff_path")
[ -n "$files_modified" ] && digest_parts+=("files_modified=[$files_modified]")
[ -n "$worktree_diff" ] && digest_parts+=("worktree_diff=[$worktree_diff]")
[ "$followup_count" -gt 0 ] && digest_parts+=("followup_tasks=$followup_count")
[ "$blockers_count" -gt 0 ] && digest_parts+=("blockers=$blockers_count")

if [ "${#digest_parts[@]}" -gt 0 ]; then
  digest=$(IFS=' '; echo "${digest_parts[*]}")
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStop",
    "additionalContext": "[subagent-stop digest] $agent_type: $digest"
  }
}
EOF
fi

exit 0
