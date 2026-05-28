#!/usr/bin/env bash
# Round 6 B — session triage tool.
#
# When a session was killed (terminal died, computer crashed, ctrl-c, OOM, ...),
# this script tells the operator what session(s) are recoverable and how.
#
# Usage:
#   bash .claude/scripts/resume-or-restart.sh           # list recent + recommend
#   bash .claude/scripts/resume-or-restart.sh --clean   # wipe heartbeat + WIP commits
#   bash .claude/scripts/resume-or-restart.sh <id>      # show details for one session

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

CLEAN=0
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN=1 ;;
    -*) echo "Unknown flag: $arg" >&2; exit 1 ;;
    *) TARGET="$arg" ;;
  esac
done

if [ "$CLEAN" = "1" ]; then
  echo "→ Cleaning heartbeat + listing WIP commits for review"
  rm -f .claude/memory/.cache/current-session.json
  echo "  ✓ removed .claude/memory/.cache/current-session.json"
  echo
  echo "  WIP commits on current branch (review before discarding):"
  git log --grep='^WIP:' --oneline -10 2>/dev/null | sed 's/^/    /'
  echo
  echo "  To discard WIP commits: git reset --keep HEAD~<N>"
  echo "  To start a clean session: claude"
  exit 0
fi

# Determine project hash (Claude Code's path-slug)
slug=$(pwd | sed 's|/|-|g')
sessions_dir="$HOME/.claude/projects/${slug}"

echo "→ Session resume triage"
echo "  Project: $(pwd)"
echo "  Hash:    $slug"
echo

# ─── Heartbeat check: was the last session killed? ──────────────────────
if [ -f .claude/memory/.cache/current-session.json ]; then
  last_session=$(jq -r '.session_id' .claude/memory/.cache/current-session.json 2>/dev/null)
  last_heartbeat=$(jq -r '.last_heartbeat_at' .claude/memory/.cache/current-session.json 2>/dev/null)
  turn_count=$(jq -r '.turn_count' .claude/memory/.cache/current-session.json 2>/dev/null)
  uncommitted=$(jq -r '.uncommitted' .claude/memory/.cache/current-session.json 2>/dev/null)
  branch=$(jq -r '.branch' .claude/memory/.cache/current-session.json 2>/dev/null)

  echo "⚠ STALE HEARTBEAT — previous session was killed (no graceful exit)"
  echo "  session_id:   $last_session"
  echo "  last beat:    $last_heartbeat"
  echo "  turns:        $turn_count"
  echo "  branch:       $branch"
  echo "  uncommitted:  $uncommitted files"
  echo
  if [ "$uncommitted" -gt 0 ]; then
    echo "  ⚠ ${uncommitted} uncommitted files — see \`git status\` before resuming."
  fi
  echo
fi

# ─── Recent session list ────────────────────────────────────────────────
echo "→ Recent sessions for this project"
if [ -d "$sessions_dir" ]; then
  count=0
  for jsonl in $(ls -t "$sessions_dir"/*.jsonl 2>/dev/null | head -5); do
    sid=$(basename "$jsonl" .jsonl)
    [ -n "$TARGET" ] && [ "$sid" != "$TARGET" ] && continue

    mtime=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$jsonl" 2>/dev/null || stat -c '%y' "$jsonl" 2>/dev/null | cut -c-16)
    size=$(stat -f '%z' "$jsonl" 2>/dev/null || stat -c '%s' "$jsonl" 2>/dev/null)
    turns=$(wc -l < "$jsonl" 2>/dev/null | tr -d ' ')

    # Pull last user message + last assistant action (heuristic from JSONL)
    last_user=$(jq -r 'select(.role == "user") | .content' "$jsonl" 2>/dev/null | tail -1 | head -c 80)
    last_tool=$(jq -r 'select(.tool_name) | .tool_name' "$jsonl" 2>/dev/null | tail -1)

    count=$((count + 1))
    echo
    echo "  [$count] session: $sid"
    echo "      mtime:  $mtime ($(numfmt --to=iec --suffix=B "$size" 2>/dev/null || echo "${size}B"))"
    echo "      turns:  $turns"
    [ -n "$last_user" ] && echo "      last Q: $last_user..."
    [ -n "$last_tool" ] && echo "      last:   $last_tool"
    echo "      resume: claude --resume $sid"
  done

  if [ "$count" = "0" ]; then
    echo "  (no sessions found at $sessions_dir)"
  fi
else
  echo "  (sessions dir does not exist: $sessions_dir)"
  echo
  echo "  ⚠ This might mean: home directory was wiped, OR you're on a new"
  echo "    machine. If you have .claude/.user-state-mirror/${slug}.tar.gz,"
  echo "    restore via: bash .claude/scripts/restore-user-state.sh"
fi

echo
echo "→ Recommended actions"
echo
echo "  Continue the most recent session:"
echo "    claude --continue"
echo
echo "  Resume a specific session:"
echo "    claude --resume <session-id>"
echo
echo "  Inspect in-flight handoff (project-local, survives home-dir wipe):"
echo "    cat .claude/memory/in-flight.md"
echo
echo "  Clean start (discards WIP + heartbeat):"
echo "    bash $0 --clean && claude"

# ─── In-flight summary ──────────────────────────────────────────────────
if [ -f .claude/memory/in-flight.md ]; then
  echo
  echo "→ In-flight brief (from prior session-end):"
  head -20 .claude/memory/in-flight.md | sed 's/^/    /'
fi
