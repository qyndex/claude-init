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

# M-23-26: user-state lives under CLAUDE_CONFIG_DIR when set (e.g. a per-tenant
# ~/.claude-qyndex), NOT always $HOME/.claude. Hardcoding $HOME/.claude read the
# WRONG dir on such installs → empty tar → silent false success. Derive the config
# root from CLAUDE_CONFIG_DIR, falling back to $HOME/.claude for back-compat.
cfg_root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
slug=$(pwd | sed 's|/|-|g')
src="$cfg_root/projects/${slug}"
dst_dir=".claude/.user-state-mirror"
dst_file="${dst_dir}/${slug}.tar.gz"
mkdir -p "$dst_dir"

if [ ! -d "$src" ]; then
  # M-23-26: fail LOUD, not silent success. A mirror step that finds nothing is a
  # real signal (wrong config dir, orphaned repo path) — exit non-zero so the
  # caller/CI notices, rather than pretending a snapshot was taken.
  echo "mirror: no user-state at $src (CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-unset}) — nothing to mirror" >&2
  exit 1
fi

# Use --exclude to drop large/regenerable artifacts (paste-cache, telemetry)
# M-23-26: the slug ALWAYS starts with '-' (leading '/' → '-'), so a bare "$slug"
# operand was parsed by tar as a flag ("Can't specify both -r and -c") and the
# archive silently came out empty — the false-success this fix closes. Prefix
# with './' (safe under -C) so it is unambiguously a path, and DON'T mute the real
# error: fail loud if tar can't build the archive.
tar -C "$cfg_root/projects" \
    --exclude='*/paste-cache/*' \
    --exclude='*/telemetry/*' \
    --exclude='*/ide/*' \
    --exclude='*/stats-cache.json' \
    -czf "$dst_file" "./$slug" \
  || { echo "mirror: tar failed to archive $src" >&2; exit 1; }

# Include any todos referencing this project's session ids (best-effort)
if [ -d "$cfg_root/tasks" ]; then
  todos_tmp=$(mktemp -d)
  for j in "$cfg_root"/tasks/*.json; do
    [ -f "$j" ] || continue
    # Heuristic: copy todos modified in the last 7 days
    # JUSTIFIED: find stderr suppressed — a file vanishing mid-loop (concurrent session) is benign; empty result just skips the copy
    if [ "$(find "$j" -mtime -7 -print 2>/dev/null)" ]; then
      cp "$j" "$todos_tmp/"
    fi
  done
  # JUSTIFIED: ls stderr suppressed — empty/absent temp dir yields empty, correctly treated as "no todos to archive"
  if [ -n "$(ls -A "$todos_tmp" 2>/dev/null)" ]; then
    # JUSTIFIED: tar stderr suppressed — best-effort todos snapshot; a packaging hiccup must not fail the SessionEnd mirror
    tar -C "$todos_tmp" -czf "${dst_dir}/${slug}-todos.tar.gz" . 2>/dev/null
  fi
  rm -rf "$todos_tmp"
fi

# Manifest for restore-user-state.sh to know what's in the archive
# JUSTIFIED: du stderr suppressed — purely cosmetic size string for the manifest; an empty value is harmless
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
