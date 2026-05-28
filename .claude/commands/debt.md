---
description: Tech debt register. List `[!]` failed tasks and `[s]` skipped tasks aged by SLA. Rank by impact. Surface debt > 90 days old for triage.
argument-hint: "[list] | [add <description>] | [age] | [triage]"
allowed-tools: Read, Glob, Grep, Bash, Edit, Write
disable-model-invocation: true
---

# /debt — Tech debt register

```bash
mode="${1:-list}"

case "$mode" in
  list)
    echo "# Tech debt register"
    echo
    echo "## Failed tasks ([!])"
    grep -nE '^- \[!\]' tasks/TASKS.md 2>/dev/null | head -40

    echo
    echo "## Skipped tasks ([s])"
    grep -nE '^- \[s\]' tasks/TASKS.md 2>/dev/null | head -40

    echo
    echo "## Deprecations pending"
    grep -E '^\|.*[0-9]{4}-[0-9]{2}-[0-9]{2}' .claude/memory/deprecations/REGISTRY.md 2>/dev/null | head -10

    echo
    echo "## WIP commits older than 30 days (uncleaned)"
    if git rev-parse --git-dir >/dev/null 2>&1; then
      git log --format='%h %s %ar' --grep='^WIP:' --since='90 days ago' --until='30 days ago' 2>/dev/null | head -10
    fi
    ;;

  age)
    echo "# Tech debt aging report"
    echo
    echo "## Items > 30 days"
    # Parse `created:` field from task entries
    awk '/^- \[[!s]\]/{getline; if(match($0, /created: ([0-9-]+T[0-9:]+)/, m)) print m[1] " | " $0}' tasks/TASKS.md \
      | sort | head -20

    echo
    echo "## Items > 90 days (SLA breach)"
    cutoff=$(date -d '90 days ago' -Iseconds 2>/dev/null || date -v -90d -Iseconds)
    awk -v cutoff="$cutoff" '
      /^- \[[!s]\]/{ task=$0; getline; if(match($0, /created: ([0-9-]+T[0-9:]+)/, m) && m[1] < cutoff) print task }
    ' tasks/TASKS.md
    ;;

  triage)
    echo "# Debt triage"
    echo
    echo "Surfacing items needing decisions (>90 days old)..."
    bash "$0" age | grep -A0 "SLA breach" -A 20
    echo
    echo "For each, decide: fix-this-sprint / next-quarter / accept-as-permanent / archive"
    ;;

  add)
    desc="${2:-}"
    if [ -z "$desc" ]; then
      echo "Usage: /debt add \"<description>\""
      exit 1
    fi
    next_id=$(grep -oE '^- \[.\] T-[0-9]+' tasks/TASKS.md | grep -oE '[0-9]+' | sort -n | tail -1)
    next_id=$((next_id + 1))
    cat >> tasks/TASKS.md <<EOF
- [!] T-${next_id}  | priority: debt  | created: $(date -Iseconds)
  summary: $desc
  files: <tbd>
  accept: human decision recorded
  owner: @<owner>
EOF
    echo "Added T-${next_id} as debt item"
    ;;

  *)
    echo "Usage: /debt [list | age | triage | add <desc>]"
    exit 1
    ;;
esac
```

## SLA policy

- Items <30 days old: active backlog
- Items 30-90 days: should be revisited; warn at standup
- Items >90 days: **SLA breach** — surface for triage; either schedule fix or formally accept as "won't fix"

## Hard rules

- **Every `[!]` or `[s]` task has a `created:` field.** Without it, aging can't be computed.
- **Triage monthly.** Debt > 90 days old without a decision becomes permanent. Don't let it.
- **`[s]` (skipped) requires a reason.** Skipping without justification is hiding.

$ARGUMENTS
