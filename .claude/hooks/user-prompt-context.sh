#!/usr/bin/env bash
# UserPromptSubmit hook. Injects light context: current branch, dirty status,
# active spec/plan, and recent failing tests. Cheap (<200ms).

set -uo pipefail

# Skip if not in a git repo
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

# Active spec (most recently modified draft/review)
active_spec=""
if [ -d specs/active ]; then
  active_spec=$(ls -t specs/active/*.md 2>/dev/null | head -1 || true)
fi

# Active plan
active_plan=""
if [ -d plans/active ]; then
  active_plan=$(ls -t plans/active/*.md 2>/dev/null | head -1 || true)
fi

# Build context block
ctx="Branch: $branch | Dirty files: $dirty"
[ -n "$active_spec" ] && ctx="$ctx | Active spec: $active_spec"
[ -n "$active_plan" ] && ctx="$ctx | Active plan: $active_plan"

# Emit as additionalContext (JSON)
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "[harness] $ctx"
  }
}
EOF
exit 0
