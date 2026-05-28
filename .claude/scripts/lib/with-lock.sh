#!/usr/bin/env bash
# with-lock.sh — portable, race-free critical-section primitive. Round 13 (Fix 2).
#
# Why: the factory runs several automations that mutate shared files (tasks/TASKS.md
# most of all) at overlapping times — the 23:00 overnight build is still running when
# the every-10-min Sentry poll mints a hotfix task, while the 03:00 dream routine and
# the 09:00 appetite breaker also write. Two writers doing the same non-atomic
# read-modify-write clobber each other. This is the one lock everything shares.
#
# Primitive: mkdir() is atomic on every POSIX filesystem (macOS + Linux) and, unlike
# `flock`, ships everywhere (stock macOS has no flock). A held lock is reclaimed if its
# holder PID is dead, or if it is older than LOCK_STALE_S (cross-host / PID-reuse backstop).
#
# Usage:
#   source "$(dirname "$0")/lib/with-lock.sh"
#   with_lock <name> <fn> [args...]      # runs fn inside the named lock
# Returns fn's exit code, or 75 (EX_TEMPFAIL) if the lock could not be acquired in time
# — callers treat 75 as "busy, try again later" rather than a hard error.

# Guard against double-sourcing (libraries may be sourced transitively).
[ -n "${__WITH_LOCK_SH:-}" ] && return 0
__WITH_LOCK_SH=1

# State dir is relative to repo root; every caller cd's to root first (their convention).
LOCK_STATE_DIR="${LOCK_STATE_DIR:-.claude/state/locks}"
LOCK_STALE_S="${LOCK_STALE_S:-120}"   # reclaim a lock older than this (holder presumed dead/gone)
LOCK_WAIT_S="${LOCK_WAIT_S:-30}"      # give up acquiring after this many seconds

# _lock_mtime <path> — epoch seconds of last modification (portable: GNU + BSD stat).
_lock_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

# with_lock <name> <fn> [args...]
with_lock() {
  local name="$1"; shift
  local lockdir="${LOCK_STATE_DIR}/${name}.lock"
  mkdir -p "${LOCK_STATE_DIR}" 2>/dev/null || true

  local waited=0 owner_pid mt age reclaim
  while ! mkdir "$lockdir" 2>/dev/null; do
    owner_pid="$(cat "$lockdir/pid" 2>/dev/null || echo "")"
    reclaim=""
    if [ -n "$owner_pid" ] && kill -0 "$owner_pid" 2>/dev/null; then
      reclaim=""                                  # live local holder — wait, NEVER reclaim
    elif [ -n "$owner_pid" ]; then
      reclaim="dead PID $owner_pid"               # holder crashed — reclaim immediately
    else
      # pid not yet written (acquire race) or cross-host: reclaim only once genuinely
      # stale by age, so a holder mid-acquire gets time to write its pid. A transient
      # stat failure (mt=0) is treated as "vanished, retry" — never as "infinitely old".
      mt="$(_lock_mtime "$lockdir")"
      if [ "${mt:-0}" != "0" ]; then
        age=$(( $(date +%s) - mt ))
        [ "$age" -ge "$LOCK_STALE_S" ] && reclaim="stale age ${age}s (no pid)"
      fi
    fi
    if [ -n "$reclaim" ]; then
      echo "with-lock[$name]: reclaiming lock ($reclaim)" >&2
      rm -rf "$lockdir"; continue
    fi
    if [ "$waited" -ge "$LOCK_WAIT_S" ]; then
      echo "with-lock[$name]: timed out after ${LOCK_WAIT_S}s (held by PID ${owner_pid:-?})" >&2
      return 75   # EX_TEMPFAIL — busy, caller retries later
    fi
    sleep 1; waited=$(( waited + 1 ))
  done

  echo "$$" > "$lockdir/pid"
  # EXIT trap guarantees release even if fn calls `exit`. We snapshot/clear it so we
  # don't permanently hijack a caller-installed EXIT trap (none of our callers set one).
  local prev_trap; prev_trap="$(trap -p EXIT)"
  trap 'rm -rf "'"$lockdir"'"' EXIT
  local rc=0
  "$@" || rc=$?
  rm -rf "$lockdir"
  if [ -n "$prev_trap" ]; then eval "$prev_trap"; else trap - EXIT; fi
  return "$rc"
}
