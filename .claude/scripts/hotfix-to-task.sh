#!/usr/bin/env bash
# Hotfix → TASKS.md — Round 12 C.
#
# Inserts a prod-alert as a top-of-queue hotfix task. Dedup-guarded so one
# outage (one Sentry fingerprint) = one task, not 500. Reads dedup state from
# the LEDGER (tasks/TASKS.md), never from GitHub — preserves Round 11 authority.
#
# Usage: hotfix-to-task.sh <fingerprint> <SEV1|SEV2|SEV3|SEV4> "<title>" "<permalink>"
# Exit 0 always (no-op on dedup); prints the created T-id or a skip reason.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# Concurrency-safe TASKS.md mutation (the Sentry poll fires every 10 min and can
# land while the overnight build is mid-write — Round 13 Fix 2).
. "$ROOT/.claude/scripts/lib/tasks-lib.sh"

FP="${1:-}"
SEV="${2:-SEV3}"
TITLE="${3:-untitled prod alert}"
PERMALINK="${4:-}"
COOLDOWN_MIN="${HOTFIX_COOLDOWN_MIN:-120}"

[ -z "$FP" ] && { echo "Usage: hotfix-to-task.sh <fingerprint> <SEV> <title> <permalink>"; exit 1; }
[ -f tasks/TASKS.md ] || { echo "tasks/TASKS.md missing"; exit 1; }

# ─── Guard 1: severity threshold (only SEV1/SEV2 auto-triage) ───────────
case "$SEV" in
  SEV1|SEV2) ;;
  *) echo "skip: $SEV below auto-triage threshold (SEV3/4 batch into weekly /triage)"; exit 0 ;;
esac

# ─── Guard 2: one open hotfix per fingerprint (read the LEDGER) ─────────
# Factored into a helper so the in-lock re-check below uses identical logic.
_open_hotfix_exists() {
  awk -v fp="$1" '
    /^- \[[ ~b]\]/ { open=1 }
    /^- \[[x!s]\]/ { open=0 }
    /fingerprint:/ { if ($0 ~ fp && open) { found=1 } }
    END { exit !found }
  ' tasks/TASKS.md
}
if _open_hotfix_exists "$FP"; then
  echo "dedup: open hotfix task already exists for fingerprint $FP"
  exit 0
fi

# ─── Guard 3: cooldown (suppress flapping) ──────────────────────────────
# JUSTIFIED: the redirect drops grep stderr when TASKS.md is absent — an empty last skips the cooldown check entirely, which is the correct behaviour for a never-seen fingerprint
last=$(grep -A8 "fingerprint: ${FP}" tasks/TASKS.md 2>/dev/null | grep -m1 'last_touched:' | grep -oE '[0-9T:+-]+' | head -1)
if [ -n "$last" ]; then
  # JUSTIFIED: GNU and BSD date parse timestamps with different flags — the redirects let each form fail quietly and the final fallback yields epoch 0, which the guard below treats as "unparseable, skip cooldown"
  last_epoch=$(date -d "$last" +%s 2>/dev/null || date -j -f '%Y-%m-%dT%H:%M:%S%z' "$last" +%s 2>/dev/null || echo 0)
  if [ "$last_epoch" -gt 0 ]; then
    age_min=$(( ( $(date +%s) - last_epoch ) / 60 ))
    if [ "$age_min" -lt "$COOLDOWN_MIN" ]; then
      echo "cooldown: fingerprint $FP touched ${age_min}m ago (< ${COOLDOWN_MIN}m)"
      exit 0
    fi
  fi
fi

# ─── Insert at TOP of ## Active with priority: hotfix ───────────────────
# Mint + insert happen INSIDE the shared TASKS.md lock, with a dedup re-check, so
# two simultaneous SEV1s for the same fingerprint can't both insert (TOCTOU) and
# can't mint a colliding T-id with a concurrent overnight/findings writer.
CREATED_TID=""
_create_hotfix_task() {
  if _open_hotfix_exists "$FP"; then return 0; fi   # re-check under lock; leave CREATED_TID empty
  local tid now entry
  tid="T-$(tasks_next_id)"
  now="$(date -Iseconds)"
  entry=$(cat <<EOF
- [ ] ${tid}  | spec:HOTFIX  | phase:0  | priority: hotfix  | created: ${now}  | last_touched: ${now}  | parallel: no  | est: 30m
  summary: hotfix ${TITLE} (${SEV})
  files: <tbd — debugger Phase 0 fills>
  accept: regression test reproducing fingerprint ${FP} exits 0
  owner: implementer
  source: sentry:${FP}
  fingerprint: ${FP}
  sentry: ${PERMALINK}
  hotfix_issue: <set by tasks-to-issues.sh projector>
EOF
)
  tasks_insert_top "$entry"
  CREATED_TID="$tid"
}

with_tasks_lock _create_hotfix_task
rc=$?
if [ "$rc" -eq 75 ]; then
  echo "busy: TASKS.md lock contended — Sentry poll will retry next cycle"; exit 0
fi
if [ -z "$CREATED_TID" ]; then
  echo "dedup: open hotfix task already appeared for fingerprint $FP (race)"; exit 0
fi

echo "✓ Created hotfix task ${CREATED_TID} at TOP of queue (priority: hotfix, fingerprint ${FP})"
echo "${CREATED_TID}"
