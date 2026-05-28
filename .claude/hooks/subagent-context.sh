#!/usr/bin/env bash
# PreToolUse hook for Agent/Task. Injects spec + task context into subagent
# invocations so they don't need to be re-primed manually.
#
# Round 6 C: prefer authoritative state from workflow-state.json (written by
# workflow-state.sh on every UserPromptSubmit) over `ls -t` newest-by-mtime.
# Two active specs + parent working on the older one → child should see the
# older one as "Current", not whichever was touched most recently.

set -uo pipefail

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')

# Only act on Agent / Task (subagent dispatch) tools
if [ "$tool" != "Agent" ] && [ "$tool" != "Task" ]; then
  exit 0
fi

agent_type=$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // .tool_input.agent // ""')

# Build a compact context block
ctx=""

# ─── Authoritative state from workflow-state.json (preferred) ───────────
spec=""
plan=""
phase=""
if [ -f .swarms/coordinator/workflow-state.json ] && command -v jq >/dev/null 2>&1; then
  phase=$(jq -r '.phase // ""' .swarms/coordinator/workflow-state.json 2>/dev/null)
  # workflow-state.sh derives spec/plan from `ls -t` but we can re-resolve here
fi

# Fall back to ls -t if state file is missing/empty
if [ -d specs/active ] && [ -z "$spec" ]; then
  spec=$(ls -t specs/active/*.md 2>/dev/null | head -1 || echo "")
fi
if [ -d plans/active ] && [ -z "$plan" ]; then
  plan=$(ls -t plans/active/*.md 2>/dev/null | head -1 || echo "")
fi

[ -n "$spec" ] && ctx="$ctx Spec: $spec."
[ -n "$plan" ] && ctx="$ctx Plan: $plan."
[ -n "$phase" ] && ctx="$ctx Phase: $phase."

# Current task (in-progress marker)
if [ -f tasks/TASKS.md ]; then
  in_progress=$(grep -m1 '^- \[~\]' tasks/TASKS.md 2>/dev/null | sed 's/^- \[~\] *//' | head -c 200 || echo "")
  if [ -n "$in_progress" ]; then
    ctx="$ctx Current task: $in_progress."
  fi
fi

# ─── Round 6 C: feature-stream-specific lane injection ──────────────────
# feature-stream agents must respect `files-owned` in analysis.md. Without
# this injection, the child has to read CLAUDE.md to learn it should look
# for analysis.md — wasteful and often skipped.
if [ "$agent_type" = "feature-stream" ]; then
  # Try to find which stream this is from the dispatch prompt (best-effort)
  prompt_body=$(printf '%s' "$input" | jq -r '.tool_input.prompt // ""' 2>/dev/null)
  stream_id=$(echo "$prompt_body" | grep -oE 'feat-[0-9]+|[a-z][a-z0-9-]+(-stream|--worktree)' | head -1)
  if [ -n "$stream_id" ] && [ -f ".swarms/streams/${stream_id}/analysis.md" ]; then
    ctx="$ctx [STREAM-LANE] Read .swarms/streams/${stream_id}/analysis.md for your files-owned + contracts-consumed. Do NOT touch files outside files-owned."
  fi
fi

# ─── NEXUS handoff schema reminder ──────────────────────────────────────
ctx="$ctx [HANDOFF] On completion, end your final message with a fenced \`\`\`nexus or \`\`\`yaml block per .claude/skills/handoff/SKILL.md. Parent parses this."

if [ -z "$ctx" ]; then
  exit 0
fi

# Emit as additionalContext — Claude Code merges this into the Agent invocation
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "[subagent-context]$ctx"
  }
}
EOF

exit 0
