---
description: Show the current project state — branch, dirty files, active spec/plan, pending tasks, recent commits, CI status. Read-only.
argument-hint: ""
allowed-tools: Bash, Read, Glob
disable-model-invocation: true
---

# /status — Project state snapshot

Run a one-shot snapshot of where the project stands. User-invoked only; never auto-triggers.

```!
echo "=== Branch & dirty ==="
git rev-parse --git-dir > /dev/null 2>&1 && {
  echo "Branch: $(git symbolic-ref --short HEAD 2>/dev/null || echo detached)"
  echo "Dirty files: $(git status --porcelain | wc -l | tr -d ' ')"
  echo "Last commit: $(git log -1 --format='%h %s (%ar)' 2>/dev/null)"
} || echo "Not in a git repo"
```

```!
echo
echo "=== Active spec ==="
ls -t specs/active/*.md 2>/dev/null | head -3 || echo "none"
echo
echo "=== Active plan ==="
ls -t plans/active/*.md 2>/dev/null | head -3 || echo "none"
```

```!
echo
echo "=== Pending tasks ==="
grep -c '^- \[ \]' tasks/TASKS.md 2>/dev/null | xargs -I{} echo "{} pending"
grep -c '^- \[~\]' tasks/TASKS.md 2>/dev/null | xargs -I{} echo "{} in_progress"
grep -c '^- \[x\]' tasks/TASKS.md 2>/dev/null | xargs -I{} echo "{} completed"
```

```!
echo
echo "=== Recent CI runs ==="
command -v gh >/dev/null && gh run list --limit 3 2>/dev/null || echo "(install gh to see CI status)"
```

After running the above, summarize in **3-5 lines max**:
- Where we are (branch, dirty, last commit)
- What's active (spec / plan)
- What's next (top pending task or "spec needed")
- Any obvious blockers (failing CI, stalled task, etc.)

Do not narrate the raw command output — the user can see it.
