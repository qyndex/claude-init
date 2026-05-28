#!/usr/bin/env bash
# Findings → TASKS.md — Round 5 E1.
#
# Single helper that closes three broken learning loops:
#   Loop 6: /spec-drift-check prints drift but doesn't open follow-ups
#   Loop 7: /adr-walk surfaces stale ADRs but doesn't assign owners
#   Loop 8: postmortem action items live as checkboxes; never become tasks
#
# Usage:
#   bash .claude/scripts/findings-to-tasks.sh <input-file> \
#       --priority <pri> [--source <slug>] [--default-owner @<user>] [--dry-run]
#
# Parses any markdown checkbox list (`- [ ] description (owner: @x)`) and
# emits matching TASKS.md entries. Idempotent: skips lines already in TASKS.md
# (matched by summary text).
#
# Priority taxonomy (matches tasks/TASKS.md doc):
#   hotfix (top — prod alert) | incident-followup | security | P1-spec | debt
#   normal | cleanup | deprecation | adr-reverify | spec-drift | postmortem
#   (hotfix tasks are created by hotfix-to-task.sh, not this script)

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# Concurrency-safe TASKS.md mutation (Round 13 Fix 2).
. "$ROOT/.claude/scripts/lib/tasks-lib.sh"

INPUT=""
PRIORITY="normal"
SOURCE=""
DEFAULT_OWNER="@unassigned"
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --priority) PRIORITY="$2"; shift 2 ;;
    --source) SOURCE="$2"; shift 2 ;;
    --default-owner) DEFAULT_OWNER="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *) INPUT="$1"; shift ;;
  esac
done

if [ -z "$INPUT" ] || [ ! -f "$INPUT" ]; then
  echo "findings-to-tasks: input file required and must exist" >&2
  echo "Usage: $0 <findings.md> --priority <pri> [--source <slug>] [--default-owner @<u>]" >&2
  exit 1
fi

mkdir -p tasks
[ -f tasks/TASKS.md ] || cat > tasks/TASKS.md <<'EOF'
# Tasks

## Active

## Archive
EOF

created=0
skipped=0
now_iso=$(date -Iseconds)

# The whole batch (mint → idempotent-skip → append) runs under one TASKS.md lock so
# ids don't collide with a concurrent overnight/hotfix writer. We mint the starting
# id inside the lock and increment locally — no other writer can interleave (Round 13 Fix 2).
_process_findings() {
  local next_id task_id text owner summary entry
  next_id=$(tasks_next_id)

  # Parse each unchecked-task line: `- [ ] <text>` or `- [ ] <text> (owner: @x)`
  while IFS= read -r line; do
    text=$(echo "$line" | sed -E 's/^- \[[ x]\] *//;s/  +/ /g')
    [ -z "$text" ] && continue

    # JUSTIFIED: the fallback yields empty when no owner tag is present (grep exit 1) — the next line substitutes DEFAULT_OWNER, so an unowned finding still gets a task
    owner=$(echo "$text" | grep -oE 'owner: @[a-zA-Z0-9_-]+' | sed 's/owner: //' || true)
    [ -z "$owner" ] && owner="$DEFAULT_OWNER"
    summary=$(echo "$text" | sed -E 's/ *\(owner:[^)]*\)//;s/ *— owner:.*$//' | head -c 200)

    # Idempotent skip if summary already in TASKS.md (also dedups within this batch)
    # JUSTIFIED: the redirect drops grep stderr when TASKS.md is absent — a non-zero (no-match) exit correctly falls through to create the task rather than skipping it
    if grep -qF "summary: $summary" tasks/TASKS.md 2>/dev/null; then
      skipped=$((skipped + 1))
      continue
    fi

    task_id="T-${next_id}"
    next_id=$((next_id + 1))

    entry=$(cat <<EOF
- [ ] $task_id  | priority: $PRIORITY  | created: $now_iso  | last_touched: $now_iso
  summary: $summary
  files: <tbd>
  accept: <human decision required — see source>
  owner: $owner
  source: ${SOURCE:-$(basename "$INPUT")}
EOF
)

    if [ "$DRY_RUN" = "1" ]; then
      echo "[dry-run] would create:"
      echo "$entry"
      echo
    else
      tasks_append_active "$entry"
    fi
    created=$((created + 1))
    # JUSTIFIED: the redirect drops grep stderr if the input file is missing — the loop then reads nothing and the run reports zero findings created
  done < <(grep -E '^[- ]*\[ \]' "$INPUT" 2>/dev/null)
}

if [ "$DRY_RUN" = "1" ]; then
  _process_findings                          # no writes — skip the lock
else
  with_tasks_lock _process_findings
  if [ "$?" -eq 75 ]; then
    echo "findings-to-tasks: TASKS.md lock contended — try again shortly" >&2
    exit 75
  fi
fi

echo "findings-to-tasks: created=$created skipped=$skipped (priority=$PRIORITY source=${SOURCE:-$(basename "$INPUT")})"
