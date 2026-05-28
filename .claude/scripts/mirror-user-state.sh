#!/usr/bin/env bash
# Round 6 B — snapshot ~/.claude/projects/<slug>/ into the repo.
#
# Why: project-state lives in ./.claude/** (git-tracked). User-state (auto-memory,
# session transcripts, TodoWrite items) lives in ~/.claude/projects/<path-slug>/
# — per-machine, lost on home-wipe, orphaned if the repo moves paths.
#
# This script mirrors that user-state into .claude/.user-state-mirror/<slug>.tar.gz
# so the next clone/machine/subscription has a recovery point.
#
# Wired into session-end.sh (runs at every graceful exit).
# Manual invocation: bash .claude/scripts/mirror-user-state.sh

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

slug=$(pwd | sed 's|/|-|g')
src="$HOME/.claude/projects/${slug}"
dst_dir=".claude/.user-state-mirror"
dst_file="${dst_dir}/${slug}.tar.gz"
mkdir -p "$dst_dir"

if [ ! -d "$src" ]; then
  echo "mirror: no user-state at $src — nothing to mirror" >&2
  exit 0
fi

# Use --exclude to drop large/regenerable artifacts (paste-cache, telemetry)
tar -C "$HOME/.claude/projects" \
    --exclude='*/paste-cache/*' \
    --exclude='*/telemetry/*' \
    --exclude='*/ide/*' \
    --exclude='*/stats-cache.json' \
    -czf "$dst_file" "$slug" 2>/dev/null

# Include any todos referencing this project's session ids (best-effort)
if [ -d "$HOME/.claude/tasks" ]; then
  todos_tmp=$(mktemp -d)
  for j in "$HOME"/.claude/tasks/*.json; do
    [ -f "$j" ] || continue
    # Heuristic: copy todos modified in the last 7 days
    if [ "$(find "$j" -mtime -7 -print 2>/dev/null)" ]; then
      cp "$j" "$todos_tmp/"
    fi
  done
  if [ -n "$(ls -A "$todos_tmp" 2>/dev/null)" ]; then
    tar -C "$todos_tmp" -czf "${dst_dir}/${slug}-todos.tar.gz" . 2>/dev/null
  fi
  rm -rf "$todos_tmp"
fi

# Manifest for restore-user-state.sh to know what's in the archive
size_h=$(du -h "$dst_file" 2>/dev/null | cut -f1)
cat > "${dst_dir}/${slug}.manifest.json" <<EOF
{
  "mirrored_at": "$(date -Iseconds)",
  "src": "$src",
  "slug": "$slug",
  "archive": "${slug}.tar.gz",
  "archive_size": "$size_h",
  "todos_archive": "${slug}-todos.tar.gz"
}
EOF

echo "mirror: $dst_file ($size_h)"
