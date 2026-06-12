#!/usr/bin/env bash
# PostToolUse hook — Round 7 B.
#
# Whenever roadmap.md is written/edited, append a line to roadmap/changelog.md
# describing the change. Cheap, mechanical, audit-compliant.
#
# Detects diff against last-known state and emits one line per moved initiative.

set -uo pipefail

input=$(cat)
path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // ""')

# Spec 003 AC-16: when tasks/TASKS.md changes, advance any spec whose tasks are
# all done to status: shipped (mirrors the roadmap-state derivation pattern).
case "$path" in
  *tasks/TASKS.md|tasks/TASKS.md|./tasks/TASKS.md)
    # JUSTIFIED: best-effort in a PostToolUse hook — a sync failure must never block the edit
    bash "$(dirname "$0")/../scripts/spec-status-sync.sh" >/dev/null 2>&1 || true

    # Loop-control producer backstop (e2e-audit autopilot-2): direct tool writes
    # to TASKS.md bypass task-status.sh's recorder, so diff status markers
    # against the loop snapshot's sibling status file and feed [!]/[x]
    # transitions to the consecutive-aborts machine. task-status.sh flips never
    # arrive here (awk+mv, not a Write tool call) — no double-recording.
    status_prev=.claude/memory/.cache/.tasks-status-prev
    mkdir -p .claude/memory/.cache
    # JUSTIFIED: grep exits 1 when no task lines exist — an empty status map is valid
    status_now=$(grep -oE '^- \[[ ~xbs!]\] T-[0-9]+' tasks/TASKS.md 2>/dev/null | sed 's/^- \[\(.\)\] \(T-[0-9]*\)/\2 \1/' || true)
    if [ -f "$status_prev" ] && [ -n "$status_now" ]; then
      while read -r tid marker; do
        [ -n "$tid" ] || continue
        prev_marker=$(grep -E "^${tid} " "$status_prev" 2>/dev/null | awk '{print $2}')
        [ "$prev_marker" = "$marker" ] && continue
        case "$marker" in
          x) bash "$(dirname "$0")/../scripts/loop-iteration.sh" record "$tid" progress >/dev/null 2>&1 || true ;;
          !) bash "$(dirname "$0")/../scripts/loop-iteration.sh" record "$tid" abort >/dev/null 2>&1 || true ;;
        esac
      done <<EOF_STATUS
$status_now
EOF_STATUS
    fi
    printf '%s\n' "$status_now" > "$status_prev" 2>/dev/null || true
    # Keep the external-edit snapshot honest for this sanctioned write path
    # JUSTIFIED: best-effort telemetry — a snapshot failure must never block the edit
    { shasum -a 256 tasks/TASKS.md 2>/dev/null | awk '{print $1}' || echo absent; } \
      > .claude/state/tasks-md.snapshot 2>/dev/null || true
    ;;
esac

# Only fire on roadmap.md
[ "$path" = "roadmap.md" ] || [ "$path" = "./roadmap.md" ] || exit 0
[ -f roadmap.md ] || exit 0

mkdir -p roadmap
changelog="roadmap/changelog.md"
[ -f "$changelog" ] || cat > "$changelog" <<'EOF'
# Roadmap changelog

Append-only audit trail of every Now/Next/Later change. Round 7 B.

EOF

# Read previous state if it exists
prev=".claude/memory/.cache/.roadmap-prev.md"
mkdir -p .claude/memory/.cache

ts=$(date -Iseconds)
# JUSTIFIED: git stderr suppressed — an unset user.name is expected in CI/fresh clones; "@claude" is the documented changelog author fallback
author=$(git config user.name 2>/dev/null || echo "@claude")

if [ ! -f "$prev" ]; then
  # First run — just snapshot
  cp roadmap.md "$prev"
  echo "$ts | initial snapshot | - | - | $author" >> "$changelog"
  exit 0
fi

# Generate diff and extract initiative-id moves
# Heuristic: lines that reference initiative IDs (NNN or INIT-NNN) and section markers
{
  # JUSTIFIED: diff stderr suppressed — diff exits 1 when files differ (the normal case here); we want the diff body, not the exit status
  diff "$prev" roadmap.md 2>/dev/null | \
    grep -E '^[<>].*[0-9]{3,}' | \
    head -10 | \
    while IFS= read -r line; do
      direction="changed"
      case "$line" in
        '<'*) direction="removed" ;;
        '>'*) direction="added" ;;
      esac
      id=$(echo "$line" | grep -oE 'INIT-[0-9]+|\b[0-9]{3,}\b' | head -1)
      [ -z "$id" ] && continue
      # Try to extract the section (NOW/NEXT/LATER) by looking backward
      summary=$(echo "$line" | sed 's/^[<>][[:space:]]*//' | head -c 80)
      echo "$ts | $direction | $id | manual roadmap edit | $author"
      echo "  → $summary"
    done
# JUSTIFIED: best-effort changelog append in a PostToolUse hook — a write failure must never block the user's edit, so the append is non-fatal
} >> "$changelog" 2>/dev/null || true

# Update snapshot
cp roadmap.md "$prev"

exit 0
