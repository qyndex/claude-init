#!/usr/bin/env bash
# UserPromptSubmit hook. Injects light context: current branch, dirty status,
# active spec/plan, and recent failing tests. Cheap (<200ms).

set -uo pipefail

# Skip if not in a git repo
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# JUSTIFIED: git error output discarded — a detached HEAD has no symbolic ref, so we fall through to the "detached" literal
branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
# JUSTIFIED: git error output discarded — any status hiccup yields an empty list and a dirty count of 0, acceptable for a context banner
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

# Active spec (most recently modified draft/review)
active_spec=""
if [ -d specs/active ]; then
  # JUSTIFIED: ls error output discarded and tolerated — an empty specs/active dir is normal; active_spec stays empty and the banner simply omits it
  active_spec=$(ls -t specs/active/*.md 2>/dev/null | head -1 || true)
fi

# Active plan
active_plan=""
if [ -d plans/active ]; then
  # JUSTIFIED: ls error output discarded and tolerated — an empty plans/active dir is normal; active_plan stays empty and the banner simply omits it
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
