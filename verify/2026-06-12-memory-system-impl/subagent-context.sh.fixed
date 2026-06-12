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
  # JUSTIFIED: the redirect drops jq stderr on a malformed state file — phase stays empty and the context block simply omits the phase line
  phase=$(jq -r '.phase // ""' .swarms/coordinator/workflow-state.json 2>/dev/null)
  # workflow-state.sh derives spec/plan from `ls -t` but we can re-resolve here
fi

# Fall back to ls -t if state file is missing/empty
if [ -d specs/active ] && [ -z "$spec" ]; then
  # JUSTIFIED: the redirect drops the glob's no-match error — an empty result means no active spec, and the context block omits the spec line
  spec=$(ls -t specs/active/*.md 2>/dev/null | head -1 || echo "")
fi
if [ -d plans/active ] && [ -z "$plan" ]; then
  # JUSTIFIED: the redirect drops the glob's no-match error — an empty result means no active plan, and the context block omits the plan line
  plan=$(ls -t plans/active/*.md 2>/dev/null | head -1 || echo "")
fi

[ -n "$spec" ] && ctx="$ctx Spec: $spec."
[ -n "$plan" ] && ctx="$ctx Plan: $plan."
[ -n "$phase" ] && ctx="$ctx Phase: $phase."

# ─── Initiative living state (memory-system review §7.2) ────────────────
# Point the child at the always-current STATE.md instead of making it re-derive.
# JUSTIFIED: pre-sync repos have no STATE.md — empty result omits the line
init_state=$(ls -t initiatives/active/*.STATE.md 2>/dev/null | head -1 || echo "")
[ -n "$init_state" ] && ctx="$ctx Initiative state: $init_state (machine-current; read instead of re-deriving)."

# Current task (in-progress marker). T-[0-9]+ guard: never match the TASKS.md
# format-template line (memory-system review, 2026-06-12).
if [ -f tasks/TASKS.md ]; then
  # JUSTIFIED: the redirect drops grep stderr and the fallback handles no in-progress task (grep exit 1) — empty result just omits the current-task line
  in_progress=$(grep -m1 -E '^- \[~\] T-[0-9]+' tasks/TASKS.md 2>/dev/null | sed 's/^- \[~\] *//' | head -c 200 || echo "")
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
  # JUSTIFIED: the redirect drops jq stderr if the prompt field is absent — an empty prompt_body just skips stream-lane injection below
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
