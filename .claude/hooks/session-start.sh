#!/usr/bin/env bash
# SessionStart hook. Boots the session with awareness of the current state.

set -uo pipefail

mkdir -p .claude/hooks/.log
log_file=.claude/hooks/.log/session.log

ts=$(date -Iseconds)
printf '%s session start\n' "$ts" >> "$log_file"

# Emit a short summary as additionalContext (loaded into the next turn)
if git rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
  last_commit=$(git log -1 --format='%h %s' 2>/dev/null || echo "none")
  uncommitted=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  pending_tasks=0
  if [ -f tasks/TASKS.md ]; then
    pending_tasks=$(grep -c '^- \[ \]' tasks/TASKS.md 2>/dev/null || echo 0)
  fi

  ctx="Repo: $(basename "$(pwd)") | Branch: $branch | Last commit: $last_commit | Uncommitted files: $uncommitted | Pending tasks: $pending_tasks"
else
  ctx="Not in a git repo. Consider 'git init' to enable full harness features."
fi

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "[harness boot] $ctx"
  }
}
EOF

exit 0
