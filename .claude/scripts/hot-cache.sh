#!/usr/bin/env bash
# hot-cache.sh — regenerate the "hot context" session cache (M-22).
#
# Writes .claude/memory/.cache/hot.md: a tiny, capped digest of the few most
# session-relevant items so a boot hook can inject it cheaply (<200ms). It holds
# the current in-progress ([~]) task, the last N completed tasks, and the top
# memory-recall hits for the working set. Regenerable idempotently: the body is a
# pure function of the ledger + recall, and the only volatile line is a single
# leading `generated:` timestamp (excluded from any diff by consumers).
#
# The boot-injection wiring (session-start-context.sh) is a separate concern —
# this script only produces the artifact.
#
# Overridable for tests: ROOT_OVERRIDE (fixture repo root), HOT_CAP (line budget).
# The cache file is memory-plane → the write is serialized under with_lock.

set -uo pipefail
SCRIPT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# ROOT_OVERRIDE lets tests point at a hermetic fixture tree; default is the repo.
ROOT="${ROOT_OVERRIDE:-$SCRIPT_ROOT}"
cd "$ROOT"

# shellcheck source=lib/with-lock.sh
. "$SCRIPT_ROOT/.claude/scripts/lib/with-lock.sh"

HOT_CAP="${HOT_CAP:-20}"
RECENT_DONE="${HOT_RECENT_DONE:-5}"

TASKS_FILE="$ROOT/tasks/TASKS.md"
CACHE_DIR="$ROOT/.claude/memory/.cache"
CACHE="$CACHE_DIR/hot.md"

_gen_hot() {
  mkdir -p "$CACHE_DIR"
  local body_tmp; body_tmp="$(mktemp)"

  {
    # In-progress task (there should be at most one; take the first).
    if [ -f "$TASKS_FILE" ]; then
      # JUSTIFIED: grep miss (no in-progress task) is fine — the section is simply omitted
      local inprog
      inprog=$(grep -m1 -E '^- \[~\] ' "$TASKS_FILE" 2>/dev/null || true)
      if [ -n "$inprog" ]; then
        echo "## In progress"
        # Keep only the marker line's leading identity fields (id + summary hint).
        echo "$inprog" | sed -E 's/ \| (created|last_touched|deps|parallel|est|priority):.*//'
      fi

      # Last N completed tasks (terse marker line only).
      # JUSTIFIED: grep miss (no done tasks yet) yields an empty section, which is correct
      local done_lines
      done_lines=$(grep -E '^- \[x\] ' "$TASKS_FILE" 2>/dev/null | tail -n "$RECENT_DONE" || true)
      if [ -n "$done_lines" ]; then
        echo "## Recent done"
        # Terse form: keep `- [x] T-NNN | spec:NNN`, plus the completion date when
        # the line carries one; drop every other field.
        echo "$done_lines" | sed -E \
          's/^(- \[x\] T-[0-9A-Za-z]+[[:space:]]*\|[[:space:]]*spec:[0-9A-Za-z]+).*(completed: [0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1 | \2/; t
               s/^(- \[x\] T-[0-9A-Za-z]+[[:space:]]*\|[[:space:]]*spec:[0-9A-Za-z]+).*/\1/'
      fi
    fi

    # Top memory-recall hits for the working set (best-effort; empty when none).
    local recall
    # JUSTIFIED: recall is advisory context — a failure or empty result must not fail cache generation
    recall=$(bash "$SCRIPT_ROOT/.claude/scripts/memory-recall.sh" --limit 3 2>/dev/null || true)
    if [ -n "$recall" ]; then
      echo "## Recall"
      echo "$recall"
    fi
  } >"$body_tmp"

  # Enforce the line budget: 1 line for the timestamp header + (HOT_CAP-1) of body.
  local body_budget=$(( HOT_CAP - 1 ))
  [ "$body_budget" -lt 1 ] && body_budget=1

  {
    echo "generated: $(date -Iseconds 2>/dev/null || date)"
    head -n "$body_budget" "$body_tmp"
  } >"$CACHE"

  rm -f "$body_tmp"
}

with_lock "memory-plane" _gen_hot
