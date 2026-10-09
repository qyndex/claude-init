#!/usr/bin/env bash
# Cooperating memory/ledger writers share an OS lock on macOS and Linux.
# The subshell preserves caller functions/variables and isolates descriptor 9.
# Kernel ownership has no age-based stealing window; process exit releases it.
[ -n "${__WITH_LOCK_SH:-}" ] && return 0
__WITH_LOCK_SH=1
LOCK_STATE_DIR="${LOCK_STATE_DIR:-.claude/state/locks}"
LOCK_WAIT_S="${LOCK_WAIT_S:-30}"

with_lock() (
  local name="$1"; shift
  case "$name" in *[!a-zA-Z0-9_-]*|'') return 64 ;; esac
  local file="${LOCK_STATE_DIR}/${name}.oslock"
  mkdir -p "$LOCK_STATE_DIR" || return 1
  # A nested function reuses the same inherited open file description.
  if ! python3 - "$file" <<'PY'
import fcntl,os,sys
try:
 a,b=os.fstat(9),os.stat(sys.argv[1])
 if (a.st_dev,a.st_ino)!=(b.st_dev,b.st_ino): raise ValueError('different lock')
 fcntl.flock(9,fcntl.LOCK_EX|fcntl.LOCK_NB)
except (OSError,ValueError): sys.exit(1)
PY
  then
    exec 9>"$file" || return 1
    python3 - "$LOCK_WAIT_S" <<'PY'
import fcntl,sys,time
try: wait=float(sys.argv[1])
except ValueError: sys.exit(64)
if not 0<=wait<=3600: sys.exit(64)
deadline=time.monotonic()+wait
while True:
 try:
  fcntl.flock(9,fcntl.LOCK_EX|fcntl.LOCK_NB)
  break
 except BlockingIOError:
  if time.monotonic()>=deadline: sys.exit(75)
  time.sleep(.05)
PY
    local lock_rc=$?
    [ "$lock_rc" = 0 ] || return "$lock_rc"
  fi
  local rc=0
  "$@" || rc=$?
  return "$rc"
)
