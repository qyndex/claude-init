#!/usr/bin/env bash
# Statusline script. Reads session JSON from stdin and prints a single line
# with: model, cwd, branch, dirty count, active spec/plan, optional cost.

set -uo pipefail

# Read JSON from stdin (best-effort)
session=$(cat 2>/dev/null || echo '{}')

# Helper to read JSON field with fallback
get() { printf '%s' "$session" | jq -r "$1 // empty" 2>/dev/null || echo ""; }

model=$(get '.model.display_name // .model.id')
cwd=$(get '.workspace.current_dir')
cost_dollars=$(get '.cost.total_cost_usd')
context_used=$(get '.context.current_tokens')
context_max=$(get '.context.max_tokens')

# Defaults
[ -z "$model" ] && model="claude"
[ -z "$cwd" ] && cwd="$(pwd)"
project=$(basename "$cwd")

# Git info
branch=""
dirty=""
if cd "$cwd" 2>/dev/null && git rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
  d=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [ "$d" != "0" ]; then dirty="*$d"; fi
fi

# Active spec / plan
spec=""
plan=""
if [ -d "$cwd/specs/active" ]; then
  s=$(ls -t "$cwd/specs/active"/*.md 2>/dev/null | head -1 || true)
  [ -n "$s" ] && spec="spec:$(basename "$s" .md)"
fi
if [ -d "$cwd/plans/active" ]; then
  p=$(ls -t "$cwd/plans/active"/*.md 2>/dev/null | head -1 || true)
  [ -n "$p" ] && plan="plan:$(basename "$p" .md)"
fi

# Context fill (if known)
ctx=""
if [ -n "$context_used" ] && [ -n "$context_max" ] && [ "$context_max" != "0" ]; then
  pct=$(awk "BEGIN { printf \"%d\", ($context_used / $context_max) * 100 }")
  ctx="ctx:${pct}%"
fi

# Cost (if known)
cost=""
if [ -n "$cost_dollars" ]; then
  cost=$(printf 'cost:$%.2f' "$cost_dollars" 2>/dev/null || echo "")
fi

# Assemble
parts=( "[$model]" "$project" )
[ -n "$branch" ] && parts+=( "($branch$dirty)" )
[ -n "$spec" ] && parts+=( "$spec" )
[ -n "$plan" ] && parts+=( "$plan" )
[ -n "$ctx" ] && parts+=( "$ctx" )
[ -n "$cost" ] && parts+=( "$cost" )

printf '%s\n' "${parts[*]}"
