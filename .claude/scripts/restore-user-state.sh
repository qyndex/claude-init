#!/usr/bin/env bash
# Round 6 B — restore mirrored ~/.claude/projects/<slug>/ from repo.
#
# Inverse of mirror-user-state.sh. Use when:
#   - Cloning the repo on a new machine
#   - Recovering after a ~/.claude/ wipe
#   - Restoring after a subscription switch that orphaned state
#
# Usage:
#   bash .claude/scripts/restore-user-state.sh           # restore using current slug
#   bash .claude/scripts/restore-user-state.sh --force   # overwrite existing user-state
#   bash .claude/scripts/restore-user-state.sh <old-slug> # restore from a different slug
#                                                          (e.g., repo moved paths)

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

FORCE=0
OLD_SLUG=""
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -*) echo "Unknown flag: $arg" >&2; exit 1 ;;
    *) OLD_SLUG="$arg" ;;
  esac
done

current_slug=$(pwd | sed 's|/|-|g')
src_slug="${OLD_SLUG:-$current_slug}"

archive=".claude/.user-state-mirror/${src_slug}.tar.gz"
manifest=".claude/.user-state-mirror/${src_slug}.manifest.json"
todos_archive=".claude/.user-state-mirror/${src_slug}-todos.tar.gz"

if [ ! -f "$archive" ]; then
  echo "restore: archive not found: $archive" >&2
  echo
  echo "Available archives:"
  # JUSTIFIED: ls stderr suppressed — the glob may match nothing when no mirror exists; "(none)" is the intended user-facing fallback
  ls -1 .claude/.user-state-mirror/*.tar.gz 2>/dev/null | sed 's|^|  |' || echo "  (none)"
  exit 1
fi

dst="$HOME/.claude/projects/${current_slug}"
if [ -d "$dst" ] && [ "$FORCE" != "1" ]; then
  echo "restore: $dst exists. Use --force to overwrite, or back it up first." >&2
  exit 1
fi

mkdir -p "$dst"
echo "→ Restoring from $archive"

# Extract archive (originally rooted at $src_slug; we want it at $current_slug)
if [ "$src_slug" = "$current_slug" ]; then
  tar -C "$HOME/.claude/projects" -xzf "$archive"
else
  # Different slug: extract to temp, rename, then move
  tmp=$(mktemp -d)
  tar -C "$tmp" -xzf "$archive"
  if [ -d "$tmp/$src_slug" ]; then
    # JUSTIFIED: mv stderr suppressed — the glob warns on a dotfile-only extract; the [ -d ] guard already confirmed the source, and the final "restored to $dst" line is the user's confirmation
    mv "$tmp/$src_slug"/* "$dst/" 2>/dev/null
  fi
  rm -rf "$tmp"
fi

# Restore todos if present
if [ -f "$todos_archive" ]; then
  mkdir -p "$HOME/.claude/tasks"
  # JUSTIFIED: best-effort todos restore — a corrupt/partial todos archive must not abort the primary session-state restore that already succeeded above
  tar -C "$HOME/.claude/tasks" -xzf "$todos_archive" 2>/dev/null || true
  echo "  ✓ restored TodoWrite items"
fi

# Manifest age check
if [ -f "$manifest" ]; then
  # JUSTIFIED: the redirect drops jq stderr on a malformed manifest — an empty mirrored_at just prints a blank age line, which is purely informational
  mirrored_at=$(jq -r .mirrored_at "$manifest" 2>/dev/null)
  echo "  mirrored: $mirrored_at"
fi

echo "✓ restored to $dst"
echo
echo "  Next: \`claude --continue\` should pick up the most recent session."
