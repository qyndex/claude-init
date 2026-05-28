---
description: Spec lifecycle operations — pause, drop, supersede, status. Spec-level companion to /roadmap (initiative-level) and /pivot (cross-cutting orchestrator). Round 7 A.
argument-hint: "<verb> <id> [flags]"
allowed-tools: Read, Glob, Grep, Bash, Edit, Write, TodoWrite
disable-model-invocation: true
---

# /spec — Spec lifecycle operations

Pauses and lifecycle changes that affect a single spec without invoking the full pivot ceremony.

## Verbs

```
/spec pause <id> --until <YYYY-MM-DD> [--reason <text>]
/spec resume <id>
/spec drop <id> --reason <text>                # delegates to /pivot drop
/spec supersede <old-id> --by <new-id>         # delegates to /pivot supersede
/spec status <id>                              # show frontmatter status + activity
```

## Implementation

```bash
verb="${1:-}"
id="${2:-}"
shift 2 2>/dev/null

reason=""
until_date=""
new_id=""
while [ $# -gt 0 ]; do
  case "$1" in
    --reason) reason="$2"; shift 2 ;;
    --until) until_date="$2"; shift 2 ;;
    --by) new_id="$2"; shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

# Locate spec file
spec=""
for f in specs/active/${id}*.md specs/active/${id}-*.md; do
  [ -f "$f" ] && { spec="$f"; break; }
done
[ -z "$spec" ] && { echo "Spec not found: $id"; exit 1; }

case "$verb" in
  pause)
    [ -z "$until_date" ] && { echo "/spec pause requires --until <date>"; exit 1; }
    sed -i.bak "s/^status:[[:space:]]*[a-z]*/status: paused/" "$spec" && rm -f "${spec}.bak"
    # Append to Change history section
    cat >> "$spec" <<EOF

<!-- spec pause -->
EOF
    # Insert change history line — preserved by /spec resume
    awk -v date="$(date -I)" -v reason="$reason" -v until_d="$until_date" '
      /^## Change history/ { found=1 }
      found && /^```/ && lines==0 { lines=1; print; next }
      lines==1 && /^- 2/ { print; next }
      lines==1 && /^```/ {
        print "- " date " | @claude | paused | until " until_d " — " reason
        lines=2
      }
      { print }
    ' "$spec" > "${spec}.tmp" && mv "${spec}.tmp" "$spec"

    # Mark in-progress tasks for this spec as [b]
    if [ -f tasks/TASKS.md ]; then
      spec_short=$(basename "$spec" .md | grep -oE '^[0-9]+' || echo "")
      [ -n "$spec_short" ] && sed -i.bak -E "s/^- \\[~\\]([^|]*\\|[^|]*spec:${spec_short})/- [b]\\1 | blocked_by: paused-until-$until_date/g" tasks/TASKS.md
      rm -f tasks/TASKS.md.bak
    fi

    echo "✓ Paused $spec until $until_date"
    echo "  Run /spec resume $id when ready"
    ;;

  resume)
    sed -i.bak "s/^status:[[:space:]]*paused/status: approved/" "$spec" && rm -f "${spec}.bak"
    # Unblock tasks
    if [ -f tasks/TASKS.md ]; then
      spec_short=$(basename "$spec" .md | grep -oE '^[0-9]+' || echo "")
      [ -n "$spec_short" ] && sed -i.bak -E "s/^- \\[b\\]([^|]*\\|[^|]*spec:${spec_short})[^|]*\\| blocked_by: paused-until-[^|]*/- [ ]\\1/g" tasks/TASKS.md
      rm -f tasks/TASKS.md.bak
    fi
    echo "✓ Resumed $spec — tasks unblocked"
    ;;

  drop)
    bash .claude/commands/pivot.md drop "$id" --reason "$reason"
    ;;

  supersede)
    [ -z "$new_id" ] && { echo "/spec supersede requires --by <new-id>"; exit 1; }
    bash .claude/commands/pivot.md supersede "$id" --by "$new_id" --reason "$reason"
    ;;

  status)
    awk '/^---$/{c++; if(c==2)exit} {print}' "$spec"
    echo
    echo "Tasks for this spec:"
    grep -E "spec:${id}" tasks/TASKS.md 2>/dev/null | head -10
    echo
    echo "Recent commits:"
    git log --oneline -5 --all --grep="Spec: $spec" 2>/dev/null
    ;;

  *) echo "Usage: /spec pause|resume|drop|supersede|status <id> [flags]"; exit 1 ;;
esac
```

## Hard rules

- **pause needs --until.** A pause without a resume date becomes abandonment by neglect.
- **resume is one command.** Pause → resume should be the same cost as creating a comment.
- **drop and supersede delegate to /pivot.** Single source of truth for the manifest + audit trail.

$ARGUMENTS
