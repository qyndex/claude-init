#!/usr/bin/env bash
# tasks-lib.sh — concurrency-safe TASKS.md mutation primitives. Round 13 (Fix 2).
#
# tasks/TASKS.md is the SOLE source of truth for task state (Round 11). Several
# automations append to it at overlapping times:
#   - hotfix-to-task.sh    (every-10-min Sentry poll → top-of-queue hotfix)
#   - findings-to-tasks.sh (drift / ADR-walk / postmortem follow-ups)
#   - appetite-check.sh    (09:00 circuit-breaker breaches)
#   - the overnight build   (23:00–04:30, marks tasks done)
# They each ran the SAME non-atomic read-modify-write to mint the next T-id:
#   next_id=$(grep ... | sort -n | tail -1); next_id=$((next_id+1))
# Run concurrently, two writers mint the SAME id and the second `mv` clobbers the
# first writer's whole append. This library centralizes ID minting + section
# inserts behind the shared with_lock so every mutation is serialized.
#
# Always mutate inside the lock:
#   source "$(dirname "$0")/lib/tasks-lib.sh"
#   _mutate() { local id; id="$(tasks_next_id)"; tasks_insert_top "$(build_entry "$id")"; }
#   with_tasks_lock _mutate

[ -n "${__TASKS_LIB_SH:-}" ] && return 0
__TASKS_LIB_SH=1

# Resolve sibling with-lock.sh regardless of caller CWD.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/with-lock.sh"

TASKS_FILE="${TASKS_FILE:-tasks/TASKS.md}"

# with_tasks_lock <fn> [args...] — run a mutation fn under the single TASKS.md lock.
with_tasks_lock() { with_lock "tasks" "$@"; }

# tasks_next_id — next integer id (no "T-" prefix). Scans every task-marker line
# (any state, Active + Archive) so ids are never reused. MUST run inside the lock.
tasks_next_id() {
  local n
  n="$(grep -oE '^- \[.\] T-[0-9]+' "${TASKS_FILE}" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1)"
  echo $(( ${n:-0} + 1 ))
}

# tasks_id_exists <n> — true if T-<n> already exists as a task marker (dup guard).
tasks_id_exists() {
  grep -qE "^- \[.\] T-${1}([^0-9]|\$)" "${TASKS_FILE}" 2>/dev/null
}

# The entry is multi-line. We pass it to awk via a temp file read with getline,
# NOT `awk -v entry=...` — BSD awk (stock macOS) rejects literal newlines in a -v
# value ("newline in string"), so -v would silently break on the dev box while
# working on Linux/gawk. The temp file is PID-suffixed; mutations run under the lock.

# tasks_insert_top <entry> — insert immediately after the "## Active" header
# (top of queue — used by hotfix).
tasks_insert_top() {
  local entry="$1" tmp="${TASKS_FILE}.tmp.$$" ef="${TASKS_FILE}.entry.$$"
  printf '%s\n' "$entry" > "$ef"
  awk -v ef="$ef" '
    BEGIN { while ((getline l < ef) > 0) e = e l "\n"; sub(/\n$/, "", e) }
    /^## Active$/ { print; print ""; print e; next }
    { print }
  ' "${TASKS_FILE}" > "$tmp" && mv "$tmp" "${TASKS_FILE}"
  rm -f "$ef"
}

# tasks_append_active <entry> — append at the END of the ## Active section,
# before the next "## " header or EOF (used by findings / appetite). Also the fix
# for appetite-check.sh, which previously `cat >>`'d to the very end of the file —
# landing breach tasks below ## Archive instead of inside ## Active.
tasks_append_active() {
  local entry="$1" tmp="${TASKS_FILE}.tmp.$$" ef="${TASKS_FILE}.entry.$$"
  printf '%s\n' "$entry" > "$ef"
  awk -v ef="$ef" '
    BEGIN { while ((getline l < ef) > 0) e = e l "\n"; sub(/\n$/, "", e) }
    /^## Active$/ { print; in_active=1; next }
    in_active && /^## / && !/^## Active/ { print e; in_active=0 }
    { print }
    END { if (in_active) print e }
  ' "${TASKS_FILE}" > "$tmp" && mv "$tmp" "${TASKS_FILE}"
  rm -f "$ef"
}
