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
} >> "$changelog" 2>/dev/null || true

# Update snapshot
cp roadmap.md "$prev"

exit 0
