#!/usr/bin/env bash
# UserPromptSubmit hook. Injects branch + dirty-file count only.
# Spec/plan context (AC-18) was deduplicated: workflow-state.sh already
# includes those fields in its <state> block.

set -uo pipefail

# Skip if not in a git repo
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# JUSTIFIED: git error output discarded — a detached HEAD has no symbolic ref, so we fall through to the "detached" literal
branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
# JUSTIFIED: git error output discarded — any status hiccup yields an empty list and a dirty count of 0, acceptable for a context banner
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

# Emit as additionalContext (JSON)
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "[harness] Branch: $branch | Dirty files: $dirty"
  }
}
EOF
exit 0
