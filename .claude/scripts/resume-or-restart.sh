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
  # JUSTIFIED: git log — 2>/dev/null hides errors on a repo with no commits yet; no WIP commits just prints nothing under the heading
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
  # JUSTIFIED: reading fields from the heartbeat JSON guarded by the enclosing [ -f ]; 2>/dev/null guards a partially-written file from a killed session — a missing field just prints blank in the triage summary
  last_session=$(jq -r '.session_id' .claude/memory/.cache/current-session.json 2>/dev/null)
  # JUSTIFIED: same heartbeat read — tolerant of a truncated file; blank field is acceptable in the human-facing summary
  last_heartbeat=$(jq -r '.last_heartbeat_at' .claude/memory/.cache/current-session.json 2>/dev/null)
  # JUSTIFIED: same heartbeat read — tolerant of a truncated file written by an abruptly-killed session
  turn_count=$(jq -r '.turn_count' .claude/memory/.cache/current-session.json 2>/dev/null)
  # JUSTIFIED: same heartbeat read — tolerant of a truncated file; the value is only used in informational echoes
  uncommitted=$(jq -r '.uncommitted' .claude/memory/.cache/current-session.json 2>/dev/null)
  # JUSTIFIED: same heartbeat read — tolerant of a truncated file; blank branch is acceptable in the summary
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
  # JUSTIFIED: ls glob — 2>/dev/null hides "no match" when the session dir has no .jsonl files; the loop then simply does not iterate
  for jsonl in $(ls -t "$sessions_dir"/*.jsonl 2>/dev/null | head -5); do
    sid=$(basename "$jsonl" .jsonl)
    [ -n "$TARGET" ] && [ "$sid" != "$TARGET" ] && continue

    # JUSTIFIED: BSD/GNU stat portability — BSD `-f` form tried first, GNU `-c` form is the 2>/dev/null fallback; one always succeeds for an existing file
    mtime=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$jsonl" 2>/dev/null || stat -c '%y' "$jsonl" 2>/dev/null | cut -c-16)
    # JUSTIFIED: BSD/GNU stat portability — BSD `-f %z` tried first, GNU `-c %s` is the fallback for the file size
    size=$(stat -f '%z' "$jsonl" 2>/dev/null || stat -c '%s' "$jsonl" 2>/dev/null)
    # JUSTIFIED: wc on a file from the `ls -t` glob that is guaranteed to exist; 2>/dev/null guards a file removed mid-loop, yielding an empty turn count
    turns=$(wc -l < "$jsonl" 2>/dev/null | tr -d ' ')

    # Pull last user message + last assistant action (heuristic from JSONL)
    # JUSTIFIED: best-effort heuristic over JSONL — 2>/dev/null hides jq parse errors on non-uniform session lines; an empty result just omits the "last Q" hint
    last_user=$(jq -r 'select(.role == "user") | .content' "$jsonl" 2>/dev/null | tail -1 | head -c 80)
    # JUSTIFIED: best-effort heuristic — same as above; missing tool_name just omits the "last tool" hint
    last_tool=$(jq -r 'select(.tool_name) | .tool_name' "$jsonl" 2>/dev/null | tail -1)

    count=$((count + 1))
    echo
    echo "  [$count] session: $sid"
    # JUSTIFIED: numfmt is GNU-only — 2>/dev/null + `|| echo "${size}B"` fall back to raw bytes on macOS where numfmt is absent
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
