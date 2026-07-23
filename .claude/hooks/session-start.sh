#!/usr/bin/env bash
# SessionStart hook. Boots the session with awareness of the current state.

set -uo pipefail

mkdir -p .claude/hooks/.log
log_file=.claude/hooks/.log/session.log

ts=$(date -Iseconds)
printf '%s session start\n' "$ts" >> "$log_file"

# Emit a short summary as additionalContext (loaded into the next turn)
if git rev-parse --git-dir >/dev/null 2>&1; then
  # JUSTIFIED: git stderr suppressed — a detached HEAD has no symbolic ref; "detached" is the intended display fallback
  branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
  # JUSTIFIED: git stderr suppressed — an unborn repo (no commits) makes git log fail; "none" is the intended display fallback
  last_commit=$(git log -1 --format='%h %s' 2>/dev/null || echo "none")
  # JUSTIFIED: git stderr suppressed — already inside the `git rev-parse` success branch, so any residual error just yields a 0 count for the banner
  uncommitted=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  pending_tasks=0
  if [ -f tasks/TASKS.md ]; then
    # M-07-state (folded gap): the bare '^- \[ \]' also matched the TASKS.md format
    # template line ('- [ ] T-<id> | ...') at the top, inflating the boot count.
    # Require a real T-<number> id, matching the hardened session-start-context.sh.
    # JUSTIFIED: grep -c exits 1 with stderr when no pending tasks match; suppressed + `|| echo 0` so an empty backlog reports 0 in the boot banner
    pending_tasks=$(grep -cE '^- \[ \] T-[0-9]+' tasks/TASKS.md 2>/dev/null || echo 0)
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
