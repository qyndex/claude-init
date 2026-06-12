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
  # JUSTIFIED: the redirect drops grep stderr when TASKS.md does not yet exist — an empty result makes ${n:-0}+1 yield id 1, the correct first id for a fresh ledger
  n="$(grep -oE '^- \[.\] T-[0-9]+' "${TASKS_FILE}" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1)"
  echo $(( ${n:-0} + 1 ))
}

# tasks_id_exists <n> — true if T-<n> already exists as a task marker (dup guard).
tasks_id_exists() {
  # JUSTIFIED: the redirect drops grep stderr when TASKS.md is absent — a non-zero (no-match) exit correctly reports the id as not existing, which is true for a missing ledger
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

# tasks_set_status <id> <marker> — flip the status marker of task T-<id> in place
# and verify the flip landed. <id> accepts "T-12" or "12". <marker> is one of the
# canonical single chars: " " ~ x ! b s. Returns 2 on bad marker, 3 when the task
# id does not exist, 4 when the post-write re-grep cannot see the new marker
# (write did not land — caller must treat as failure, not success).
# MUST run inside the lock (with_tasks_lock tasks_set_status T-12 x).
tasks_set_status() {
  local id="${1#T-}" marker="$2" tmp="${TASKS_FILE}.tmp.$$"
  case "$marker" in
    " "|"~"|"x"|"!"|"b"|"s") ;;
    *) echo "tasks_set_status: invalid marker '${marker}' (one of: ' ' ~ x ! b s)" >&2; return 2 ;;
  esac
  case "$id" in
    *[!0-9]*|"") echo "tasks_set_status: invalid task id '${1}'" >&2; return 3 ;;
  esac
  if ! tasks_id_exists "$id"; then
    echo "tasks_set_status: T-${id} not found in ${TASKS_FILE}" >&2; return 3
  fi
  awk -v id="$id" -v m="$marker" '
    $0 ~ ("^- \\[.\\] T-" id "([^0-9]|$)") { sub(/^- \[.\]/, "- [" m "]") }
    { print }
  ' "${TASKS_FILE}" > "$tmp" && mv "$tmp" "${TASKS_FILE}"
  grep -qE "^- \[${marker}\] T-${id}([^0-9]|\$)" "${TASKS_FILE}" || {
    echo "tasks_set_status: flip of T-${id} to [${marker}] did not land" >&2; return 4
  }
}

# tasks_get_status <id> — print the current single-char marker of T-<id>, or
# return 3 when absent. Read-only; safe outside the lock for advisory reads.
tasks_get_status() {
  local id="${1#T-}" line
  line="$(grep -E "^- \[.\] T-${id}([^0-9]|\$)" "${TASKS_FILE}" 2>/dev/null | head -1)"
  [ -n "$line" ] || return 3
  printf '%s\n' "$line" | sed -E 's/^- \[(.)\].*/\1/'
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
