#!/usr/bin/env bash
# PreToolUse Write|Edit|NotebookEdit — swarm lane guard (e2e-audit swarm-5/6).
#
# Active ONLY inside a feat-* worktree (a swarm stream's lane). Blocks writes
# outside the stream's files_owned list (.swarms/streams/<id>/task.json at the
# shared root) so cross-stream collisions become impossible by construction
# instead of detected-at-rebase human escalations.
#
# No-ops everywhere else: non-swarm sessions, streams with no files_owned
# declared (no allocation = no lane to guard), missing task.json.
# Exit 2 = hard block. LANE_GUARD=0 disables (operator escape).

set -uo pipefail

[ "${LANE_GUARD:-1}" = "0" ] && exit 0

# Only in a git worktree on a feat-* branch
# JUSTIFIED: outside a git repo there is no lane — the guard must no-op
branch=$(git symbolic-ref --short HEAD 2>/dev/null || true)
stream=$(printf '%s' "$branch" | grep -oE '^feat-[a-z0-9-]+' || true)
[ -z "$stream" ] && exit 0

# jq fail-closed discipline (P1.5): without jq we cannot parse the payload —
# inside a guarded lane that means BLOCK, not silently allow.
if ! command -v jq >/dev/null 2>&1; then
  echo "[lane-guard] jq unavailable — cannot evaluate lane ownership; blocking write" >&2
  exit 2
fi

# Shared swarm root (swarm-1)
# shellcheck source=../scripts/lib/swarm-root.sh
. "$(cd "$(dirname "$0")/../scripts/lib" && pwd)/swarm-root.sh"

task_json="$SWARM_ROOT/.swarms/streams/$stream/task.json"
[ -f "$task_json" ] || exit 0

# JUSTIFIED: jq muted — a malformed task.json yields an empty list, treated as "no allocation declared" (no lane to guard)
owned=$(jq -r '.files_owned[]? // empty' "$task_json" 2>/dev/null)
[ -z "$owned" ] && exit 0

input=$(cat)
path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.notebook_path // ""')
[ -z "$path" ] && exit 0

# Normalize to repo-relative
rel="${path#"$PWD"/}"
rel="${rel#./}"

# Always-allowed lanes: the stream's own .swarms state dir, its verify evidence,
# and its tests (TDD writes tests beside owned code; TASKS.md stays denied —
# the constitution guard owns that rule and the coordinator is the single writer).
case "$rel" in
  .swarms/streams/"$stream"/*|verify/*|*.test.*|*.spec.*|tests/*|test/*) exit 0 ;;
esac

# Glob match against files_owned (patterns may be literal paths or globs)
while IFS= read -r pat; do
  [ -n "$pat" ] || continue
  # shellcheck disable=SC2254  # JUSTIFICATION: unquoted $pat is the point — files_owned entries are GLOBS matched against the path ISSUE: #0
  case "$rel" in
    $pat) exit 0 ;;
  esac
done <<EOF_OWNED
$owned
EOF_OWNED

echo "[lane-guard] BLOCK: $rel is outside stream $stream's files_owned lane. Owned: $(printf '%s' "$owned" | tr '\n' ' '). Need a change here? Signal the owning stream via a TODO in your handoff — do not write cross-lane." >&2
exit 2
