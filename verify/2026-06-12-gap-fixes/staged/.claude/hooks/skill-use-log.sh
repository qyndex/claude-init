#!/usr/bin/env bash
# PostToolUse hook for the Skill tool — gap-audit G17.
# The skill-router injects hints but nothing recorded whether skills are
# actually invoked, so "never-used skill" and hint-vs-use questions were
# unanswerable. One JSONL line per Skill invocation; consumed by
# harness-doctor.sh and the context-budget skill (invocation ground truth).

set -uo pipefail

input=$(cat 2>/dev/null || true)
[ -z "$input" ] && exit 0

skill=$(printf '%s' "$input" | jq -r '.tool_input.skill // .tool_input.name // ""' 2>/dev/null)
[ -z "$skill" ] && exit 0

mkdir -p .claude/hooks/.log 2>/dev/null || exit 0
# JUSTIFIED: append is best-effort telemetry — a write failure must never fail the tool chain
jq -nc --arg ts "$(date -Iseconds)" --arg skill "$skill" \
  '{ts:$ts, skill:$skill}' >> .claude/hooks/.log/skill-use.jsonl 2>/dev/null || true

exit 0
